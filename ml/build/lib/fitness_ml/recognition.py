"""Exercise recognition over a rolling pose-feature window, with rejection to "unknown".
The session plan is context only: without a trained model nothing is recognised."""
from collections import deque

import numpy as np

from .artifacts import Artifact
from .features import FEATURE_NAMES

MIN_TRACKED_FRAC = 0.6  # windows with less tracked pose than this are not classified


class Recognizer:
    def __init__(self, artifact: Artifact, window_ms: float, stride_ms: float, reject_below: float):
        self.artifact, self.window_ms, self.stride_ms, self.reject_below = artifact, window_ms, stride_ms, reject_below
        self.reset()

    def reset(self) -> None:
        self._frames: deque[tuple[float, list[float]]] = deque()
        self._next_ms = None
        self.label, self.confidence = "unknown", None

    def update(self, t_ms: float, features: dict[str, float]) -> tuple[str, float | None]:
        self._frames.append((t_ms, [features[n] for n in FEATURE_NAMES]))
        while self._frames and self._frames[0][0] < t_ms - self.window_ms:
            self._frames.popleft()
        if self._next_ms is None:
            self._next_ms = t_ms + self.window_ms  # first prediction once a full window exists
        if t_ms >= self._next_ms:
            self._next_ms = t_ms + self.stride_ms
            self.label, self.confidence = self._predict()
        return self.label, self.confidence

    def _predict(self) -> tuple[str, float | None]:
        ts = np.array([t for t, _ in self._frames])
        matrix = np.array([row for _, row in self._frames], dtype=float)
        tracked = ~np.isnan(matrix).all(axis=1)
        if tracked.mean() < MIN_TRACKED_FRAC:
            return "unknown", None
        proba = self.artifact.predict_proba(matrix, ts)
        best = int(np.argmax(proba))
        confidence = round(float(proba[best]), 3)
        return (self.artifact.labels[best] if confidence >= self.reject_below else "unknown"), confidence
