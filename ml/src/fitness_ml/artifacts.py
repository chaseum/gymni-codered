"""Trained-model artifacts: one directory = metadata.json + model.joblib (sklearn) or model.pt (GRU).
Shared by training (save) and live inference (load). Loading always works on CPU."""
import json
from pathlib import Path

import numpy as np

from .features import FEATURE_NAMES, aggregate, resample


class Artifact:
    def __init__(self, directory: str | Path):
        self.dir = Path(directory)
        self.meta = json.loads((self.dir / "metadata.json").read_text())
        if self.meta["feature_names"] != FEATURE_NAMES:
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

    def predict_proba(self, matrix: np.ndarray, timestamps_ms: np.ndarray) -> np.ndarray:
        """(T, F) frame features of one window -> probability per label, in `self.labels` order."""
        if self.meta["model"] == "gru":
            return self._gru_proba(matrix, timestamps_ms)
        return self._est.predict_proba(aggregate(matrix, timestamps_ms)[None])[0][self._order]

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
