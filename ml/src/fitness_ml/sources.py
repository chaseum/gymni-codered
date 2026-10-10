"""Frame sources. Both yield BGR frames with strictly increasing per-source timestamps (ms).

Live: monotonic clock since the source opened. Recorded: the container's presentation timestamp
(CAP_PROP_POS_MSEC) when it moves forward, else frame_index * 1000 / fps. Neither is epoch time.
"""
import time
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np


@dataclass
class Frame:
    image: np.ndarray
    timestamp_ms: float
    index: int


class Webcam:
    source = "live"
    time_base = "capture_monotonic"
    clip_id = None

    def __init__(self, index: int = 0, width: int | None = None, height: int | None = None):
        self.index, self.width, self.height = index, width, height

    def frames(self) -> Iterator[Frame]:
        cap = cv2.VideoCapture(self.index)
        if self.width:
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.width)
        if self.height:
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.height)
        if not cap.isOpened():
            raise RuntimeError(f"cannot open camera {self.index} (macOS: grant Camera access to your terminal)")
        t0, last, i = time.monotonic(), -1.0, 0
        try:
            while True:
                ok, image = cap.read()
                if not ok:
                    return
                t = max((time.monotonic() - t0) * 1000, last + 1)
                last = t
                yield Frame(image, t, i)
                i += 1
        finally:
            cap.release()


class VideoFile:
    source = "recorded"
    time_base = "video_pts"

    def __init__(self, path: str | Path):
        self.path = Path(path)
        if not self.path.is_file():
            raise FileNotFoundError(self.path)
        self.clip_id = self.path.stem

    def frames(self) -> Iterator[Frame]:
        cap = cv2.VideoCapture(str(self.path))
        if not cap.isOpened():
            raise RuntimeError(f"cannot decode {self.path}")
        fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
        last, i = -1.0, 0
        try:
            while True:
                ok, image = cap.read()
                if not ok:
                    return
                last = recorded_timestamp(cap.get(cv2.CAP_PROP_POS_MSEC), i, fps, last)
                yield Frame(image, last, i)
                i += 1
        finally:
            cap.release()


def recorded_timestamp(pts_ms: float, index: int, fps: float, last_ms: float) -> float:
    """PTS when it advances; otherwise the nominal frame time; never <= the previous timestamp."""
    t = pts_ms if pts_ms > last_ms else index * 1000.0 / fps
    return max(t, last_ms + 1)


def open_source(kind: str, video: str | None = None, camera: int = 0):
    if kind == "live":
        return Webcam(camera)
    if not video:
        raise ValueError("--video is required for a recorded source")
    return VideoFile(video)
