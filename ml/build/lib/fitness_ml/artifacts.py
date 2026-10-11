"""Trained-model artifacts: one directory = metadata.json + model.joblib (sklearn) or model.pt (GRU).
Shared by training (save) and live inference (load). Loading always works on CPU."""
import json
from pathlib import Path

import numpy as np

from .features import FEATURE_NAMES, aggregate, resample

# Models trained on MyDeadlift's published angles (no videos) see only these three, from the tracked side.
ANGLE_FEATURES = ("knee_angle_deg", "hip_angle_deg", "trunk_lean_deg")


class Artifact:
    def __init__(self, directory: str | Path):
        self.dir = Path(directory)
        self.meta = json.loads((self.dir / "metadata.json").read_text())
        self.angle_model = self.meta.get("feature_set") == "side_angles"
        if not self.angle_model and self.meta["feature_names"] != FEATURE_NAMES:
            raise ValueError(f"{self.dir}: feature schema differs from this code; retrain or check out "
                             f"code revision {self.meta.get('code_revision')}")
        self.labels: list[str] = self.meta["labels"]
        self.version: str = self.meta["model_version"]
        if self.meta["model"] == "gru":
            self._load_gru()
        else:
            import joblib
            self._est = joblib.load(self.dir / "model.joblib")
            self._order = [list(self._est.classes_).index(label) for label in self.labels]
            guard = self.meta.get("guard")
            self._guard = joblib.load(self.dir / guard["file"]) if guard else None

    @property
    def calibration_reps(self) -> int:
        """Clean reps the user must do first; later reps are judged relative to them (0 = no calibration)."""
        return int(self.meta.get("calibration_reps", 0))

    @property
    def fault_threshold(self) -> float | None:
        """Report a fault only at or above this probability (chosen by cross-validation at training time)."""
        return self.meta.get("fault_threshold")

    def rep_vector(self, matrix: np.ndarray, timestamps_ms: np.ndarray, side: str | None = None) -> np.ndarray:
        """One rep's model input. Angle models use the tracked side's knee/hip + trunk lean."""
        if self.meta.get("feature_fn") == "keypose_curve_v1":
            return keypose_curve(side_angles(matrix, side or "left"), timestamps_ms)
        if self.angle_model:
            matrix = side_angles(matrix, side or "left")
        return aggregate(matrix, timestamps_ms)

    def baseline_fault(self, vector: np.ndarray) -> tuple[str, float] | None:
        """For calibration reps: (most likely fault, P(any fault)) if the uncalibrated guard model rates this rep
        as clearly faulty, else None. Models without a guard accept every baseline rep."""
        if self._guard is None:
            return None
        proba = self._guard.predict_proba(vector[None])[0]
        classes = list(self._guard.classes_)
        p_fault = 1 - proba[classes.index("none")]
        if p_fault < self.meta["guard"]["threshold"]:
            return None
        faults = [(p, c) for p, c in zip(proba, classes) if c != "none"]
        return max(faults)[1], round(float(p_fault), 3)

    def predict_vector(self, vector: np.ndarray) -> np.ndarray:
        return self._est.predict_proba(vector[None])[0][self._order]

    def predict_proba(self, matrix: np.ndarray, timestamps_ms: np.ndarray, side: str | None = None,
                      reference: np.ndarray | None = None) -> np.ndarray:
        """(T, F) frame features of one window -> probability per label, in `self.labels` order.
        `reference` = mean rep_vector of the user's calibration reps, for calibrated models."""
        if self.meta["model"] == "gru":
            return self._gru_proba(side_angles(matrix, side or "left") if self.angle_model else matrix, timestamps_ms)
        vector = self.rep_vector(matrix, timestamps_ms, side)
        return self.predict_vector(vector - reference if reference is not None else vector)

    def _load_gru(self):
        import torch
        state = torch.load(self.dir / "model.pt", map_location="cpu", weights_only=True)
        self._net = build_gru(len(FEATURE_NAMES), len(self.labels), self.meta["hidden"])
        self._net.load_state_dict(state)
        self._net.eval()
        self._mean = np.array(self.meta["norm_mean"])
        self._std = np.array(self.meta["norm_std"])

    def _gru_proba(self, matrix, timestamps_ms):
        import torch
        seq = (resample(matrix, timestamps_ms, self.meta["steps"]) - self._mean) / self._std
        with torch.no_grad():
            logits = self._net(torch.tensor(seq[None], dtype=torch.float32))
        return torch.softmax(logits, -1)[0].numpy()


def keypose_curve(angles: np.ndarray, timestamps_ms: np.ndarray) -> np.ndarray:
    """(T, 3) knee, hip, back-to-vertical over ONE rep (setup -> lockout -> down) -> 43 numbers:
    setup pose (first 10%), lockout pose (max hip angle), extremes and ranges, setup knee-hip gap, duration,
    and each angle resampled to 10 evenly spaced points. Selected by subject-wise CV on MyDeadlift (2026-10-10)."""
    angles = _fill_gaps(angles)
    knee, hip, back = angles.T
    n = len(knee)
    setup = slice(0, max(3, n // 10))
    lock = int(np.nanargmax(hip))
    duration_s = (timestamps_ms[-1] - timestamps_ms[0]) / 1000
    curves = [np.interp(np.linspace(0, n - 1, 10), np.arange(n), a) for a in (knee, hip, back)]
    return np.r_[knee[setup].mean(), hip[setup].mean(), back[setup].mean(), knee[lock], hip[lock], back[lock],
                 knee.min(), back.max(), knee.max() - knee.min(), hip.max() - hip.min(), back.max() - back.min(),
                 knee[setup].mean() - hip[setup].mean(), duration_s, np.concatenate(curves)]


def _fill_gaps(angles: np.ndarray) -> np.ndarray:
    """Linear-interpolate untracked frames per column so short tracking dropouts don't poison a rep."""
    out = angles.astype(float).copy()
    idx = np.arange(len(out))
    for j in range(out.shape[1]):
        ok = ~np.isnan(out[:, j])
        if ok.any() and not ok.all():
            out[~ok, j] = np.interp(idx[~ok], idx[ok], out[ok, j])
    return out


def side_angles(matrix: np.ndarray, side: str) -> np.ndarray:
    names = [f"{side}_knee_angle_deg", f"{side}_hip_angle_deg", "trunk_lean_deg"]
    return matrix[:, [FEATURE_NAMES.index(n) for n in names]]


def build_gru(n_features: int, n_labels: int, hidden: int):
    import torch.nn as nn

    class GRUClassifier(nn.Module):
        def __init__(self):
            super().__init__()
            self.gru = nn.GRU(n_features, hidden, batch_first=True)
            self.head = nn.Linear(hidden, n_labels)

        def forward(self, x):
            _, h = self.gru(x)
            return self.head(h[-1])

    return GRUClassifier()


def discover(models_dir: str | Path) -> tuple[Path | None, dict[str, Path]]:
    """Newest recognizer trained on every class, and the newest form model per exercise
    (a specific-fault model beats a good/bad one). Directories without metadata are ignored."""
    found = []
    for meta_file in Path(models_dir).glob("*/metadata.json"):
        try:
            found.append((json.loads(meta_file.read_text()), meta_file.parent))
        except (OSError, json.JSONDecodeError):
            continue
    found.sort(key=lambda m: m[0].get("trained_at", ""))
    recognizer = None
    forms: dict[str, tuple[int, Path]] = {}
    for meta, directory in found:  # oldest -> newest, so later entries win
        if meta.get("task") == "recognition" and not meta.get("excluded_labels"):
            recognizer = directory
        elif meta.get("task") in ("form_issue", "form_binary") and meta.get("exercise"):
            rank = 1 if meta["task"] == "form_issue" else 0
            if rank >= forms.get(meta["exercise"], (-1, None))[0]:
                forms[meta["exercise"]] = (rank, directory)
    return recognizer, {exercise: directory for exercise, (_, directory) in forms.items()}


def test_score(directory: str | Path) -> float | None:
    """Held-out macro-F1 from `fitness-train evaluate` (None if not evaluated yet)."""
    path = Path(directory) / "metrics_test.json"
    return json.loads(path.read_text()).get("macro_f1") if path.exists() else None
