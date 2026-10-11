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


class CameraLost(RuntimeError):
    """The live camera stopped delivering frames and did not come back."""


class Webcam:
    source = "live"
    time_base = "capture_monotonic"
    clip_id = None
    RECONNECT_S = 5.0  # an iPhone Continuity Camera that locks or drifts out of range often returns within seconds

    def __init__(self, index: int = 0, width: int | None = None, height: int | None = None):
        self.index, self.width, self.height = index, width, height

    def frames(self) -> Iterator[Frame]:
        cap = self._open()
        t0, last, i = time.monotonic(), -1.0, 0
        try:
            while True:
                ok, image = cap.read()
                if not ok:
                    cap.release()
                    cap, image = self._reconnect(delivered=i)
                t = max((time.monotonic() - t0) * 1000, last + 1)
                last = t
                yield Frame(image, t, i)
                i += 1
        finally:
            cap.release()

    def _open(self):
        cap = cv2.VideoCapture(self.index)
        cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        if self.width:
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.width)
        if self.height:
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.height)
        if not cap.isOpened():
            raise CameraLost(f"cannot open camera {self.index} (macOS: allow Camera access for your terminal app; "
                             f"`fitness-ml cameras` lists what's available)")
        return cap

    def _reconnect(self, delivered: int):
        print(f"camera {self.index} stopped sending frames; retrying for {self.RECONNECT_S:.0f} s...", flush=True)
        deadline = time.monotonic() + self.RECONNECT_S
        while time.monotonic() < deadline:
            time.sleep(0.5)
            cap = cv2.VideoCapture(self.index)
            ok, image = cap.read() if cap.isOpened() else (False, None)
            if ok:
                print("camera reconnected", flush=True)
                return cap, image
            cap.release()
        raise CameraLost(
            f"camera {self.index} stopped sending frames after {delivered} frames. If it is your iPhone "
            f"(Continuity Camera), it may have locked, moved or disconnected. Run `fitness-ml cameras` and pick the "
            f"built-in one with --camera N.")


def list_cameras(max_index: int = 4) -> list[tuple[int, str]]:
    """(index, description) for every camera OpenCV can open. Resolution identifies devices: the 2020 MacBook
    FaceTime HD camera is 1280x720; an iPhone Continuity Camera is usually 1920x1080."""
    found = []
    for index in range(max_index):
        cap = cv2.VideoCapture(index)
        ok, image = cap.read() if cap.isOpened() else (False, None)
        cap.release()
        if ok:
            h, w = image.shape[:2]
            hint = " (likely iPhone / Continuity Camera)" if w >= 1920 else " (likely built-in FaceTime camera)" if w <= 1280 else ""
            found.append((index, f"{w}x{h}{hint}"))
    return found


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
        recorded_times = _sidecar_times(self.path)
        last, i = -1.0, 0
        try:
            while True:
                ok, image = cap.read()
                if not ok:
                    return
                if i < len(recorded_times):  # a `fitness-ml run --record` capture: use the true capture times
                    last = max(recorded_times[i], last + 1)
                else:
                    last = recorded_timestamp(cap.get(cv2.CAP_PROP_POS_MSEC), i, fps, last)
                yield Frame(image, last, i)
                i += 1
        finally:
            cap.release()


def recorded_timestamp(pts_ms: float, index: int, fps: float, last_ms: float) -> float:
    """PTS when it advances; otherwise the nominal frame time; never <= the previous timestamp."""
    t = pts_ms if pts_ms > last_ms else index * 1000.0 / fps
    return max(t, last_ms + 1)


def _sidecar_times(video: Path) -> list[float]:
    sidecar = video.with_suffix(".timestamps.csv")
    if not sidecar.is_file():
        return []
    return [float(line.split(",")[1]) for line in sidecar.read_text().splitlines()[1:] if line]


def open_source(kind: str, video: str | None = None, camera: int = 0):
    if kind == "live":
        return Webcam(camera)
    if not video:
        raise ValueError("--video is required for a recorded source")
    return VideoFile(video)
