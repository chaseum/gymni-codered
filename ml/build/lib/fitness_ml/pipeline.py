"""Video -> observations loop shared by `fitness-ml run` and `fitness-ml validate`."""
import time
from collections.abc import Iterator
from dataclasses import dataclass

from .analyzer import Analyzer, FrameResult
from .pose import Pose, PoseEstimator
from .sources import Frame


@dataclass
class Step:
    frame: Frame
    pose: Pose | None
    result: FrameResult
    latency_ms: float  # pose + analysis time for this frame


def observe(source, estimator: PoseEstimator, analyzer: Analyzer) -> Iterator[Step]:
    for frame in source.frames():
        yield process(frame, estimator, analyzer)


def process(frame: Frame, estimator: PoseEstimator, analyzer: Analyzer) -> Step:
    started = time.perf_counter()
    pose = estimator.detect(frame.image, frame.timestamp_ms)
    result = analyzer.analyze_frame(pose, frame.timestamp_ms)
    return Step(frame, pose, result, (time.perf_counter() - started) * 1000)
