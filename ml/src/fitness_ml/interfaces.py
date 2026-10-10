"""Pipeline seams so each stage can be built and tested alone. No implementations yet."""
from collections.abc import Iterator
from typing import Any, Protocol

from .types import CompletedRep, Issue, Observation, Phase, Recognized, Tracking


class Frame(Protocol):
    image: Any            # BGR ndarray
    timestamp_ms: float   # from the capture/video clock, monotonic within a source


class VideoSource(Protocol):
    """Webcam (source="live") or MP4 (source="recorded"); recorded clips use the video PTS."""
    source: str
    clip_id: str | None
    def frames(self) -> Iterator[Frame]: ...


class PoseEstimator(Protocol):
    """MediaPipe Tasks Pose Landmarker in VIDEO mode. Returns 33 landmarks or None."""
    def detect(self, frame: Frame) -> Any | None: ...


class FeatureExtractor(Protocol):
    """Normalized landmarks -> named measurements + per-joint visibility -> tracking status."""
    def extract(self, landmarks: Any | None) -> tuple[dict[str, float | None], Tracking]: ...


class RepCounter(Protocol):
    """Per-exercise hysteresis state machine. Returns CompletedRep only on the completing transition."""
    def update(self, measurements: dict[str, float | None], tracking: Tracking, t_ms: float) -> tuple[Phase, CompletedRep | None]: ...
    def reset(self) -> None: ...


class FormAnalyzer(Protocol):
    """Reviewed rules or a trained model; only emits issue codes with measured evidence."""
    def evaluate(self, window: list[dict[str, float | None]]) -> list[Issue]: ...


class ExerciseRecognizer(Protocol):
    """Temporal-window classifier over curl/squat/deadlift/other; "unknown" when it should reject."""
    def predict(self, window: list[dict[str, float | None]]) -> tuple[Recognized, float | None]: ...


class ObservationSink(Protocol):
    def send(self, obs: Observation) -> None: ...
