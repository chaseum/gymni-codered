"""Trained-model artifacts: one directory = metadata.json + model.joblib (sklearn) or model.pt (GRU).
Shared by training (save) and live inference (load). Loading always works on CPU."""
import json
from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np

from .features import FEATURE_NAMES, aggregate
from .sequence import gru_inputs, input_size, resample_seen

@dataclass(frozen=True)
class GRUParams:
    """Everything that shapes a GRU model; stored in metadata["gru"] so loading rebuilds the same network."""
    hidden: int = 64
    layers: int = 1
    dropout: float = 0.0
    lr: float = 1e-3
    batch: int = 64
    steps: int = 48     # each window is resampled to this many time steps
    mask: bool = False           # add a "joint was actually seen" channel per feature
    velocity: bool = False       # add step-to-step change per feature
    bidirectional: bool = False  # read the window forwards and backwards
    attention: bool = False      # weight time steps instead of using only the final state
    augment: bool = False        # training only: mirror / tilt / hidden-limb / noise variants each epoch

    @classmethod
    def from_meta(cls, meta: dict) -> "GRUParams":
        return cls(**meta["gru"]) if "gru" in meta else cls(hidden=meta["hidden"], steps=meta["steps"])

    def as_meta(self) -> dict:
        return asdict(self)


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
        self._params = GRUParams.from_meta(self.meta)
        self._net = build_gru(len(self.labels), self._params)
        self._net.load_state_dict(state)
        self._net.eval()
        self._mean = np.array(self.meta["norm_mean"])
        self._std = np.array(self.meta["norm_std"])

    def _gru_proba(self, matrix, timestamps_ms):
        import torch
        values, seen = resample_seen(matrix, timestamps_ms, self._params.steps)
        x = gru_inputs(values, seen, self._mean, self._std, self._params.mask, self._params.velocity)
        with torch.no_grad():
            logits = self._net(torch.tensor(x[None]))
        return torch.softmax(logits / self.meta.get("temperature", 1.0), -1)[0].numpy()


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


def build_gru(n_labels: int, params: GRUParams):
    import torch
    import torch.nn as nn

    directions = 2 if params.bidirectional else 1
    width = params.hidden * directions

    class GRUClassifier(nn.Module):
        def __init__(self):
            super().__init__()
            self.gru = nn.GRU(input_size(params.mask, params.velocity), params.hidden, num_layers=params.layers,
                              batch_first=True, bidirectional=params.bidirectional,
                              dropout=params.dropout if params.layers > 1 else 0.0)
            if params.attention:
                self.score = nn.Linear(width, 1)
            self.drop = nn.Dropout(params.dropout)  # no weights: older state dicts still load
            self.head = nn.Linear(width, n_labels)

        def forward(self, x):
            out, h = self.gru(x)
            if params.attention:
                weights = torch.softmax(self.score(out).squeeze(-1), dim=1)
                pooled = (weights.unsqueeze(-1) * out).sum(1)
            else:
                pooled = torch.cat([h[-2], h[-1]], dim=-1) if params.bidirectional else h[-1]
            return self.head(self.drop(pooled))

    return GRUClassifier()


def fit_temperature(logits: np.ndarray, labels: np.ndarray) -> float:
    """Temperature T minimising validation negative log-likelihood of softmax(logits / T). T > 1 softens an
    overconfident network so that "90% sure" is right about 90% of the time; it never changes the argmax."""
    def nll(t):
        z = logits / t
        z = z - z.max(1, keepdims=True)
        log_p = z - np.log(np.exp(z).sum(1, keepdims=True))
        return -log_p[np.arange(len(labels)), labels].mean()
    grid = np.geomspace(0.25, 20, 200)
    return float(grid[np.argmin([nll(t) for t in grid])])


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
