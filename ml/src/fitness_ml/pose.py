"""MediaPipe Tasks Pose Landmarker (VIDEO mode) behind a small adapter we own."""
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np

MODEL_URL = ("https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
             "pose_landmarker_{v}/float16/latest/pose_landmarker_{v}.task")
VARIANTS = ("lite", "full", "heavy")
LANDMARKS = [p.name.lower() for p in mp.tasks.vision.PoseLandmark]  # 33 names, index-aligned
INDEX = {name: i for i, name in enumerate(LANDMARKS)}
CONNECTIONS = [(c.start, c.end) for c in mp.tasks.vision.PoseLandmarksConnections.POSE_LANDMARKS]


@dataclass
class Pose:
    image: np.ndarray        # (33, 5): x, y (0..1 of width/height), z, visibility, presence
    world: np.ndarray | None  # (33, 3): estimated metres, hip-centred
    width: int
    height: int

    def visibility(self, name: str) -> float:
        return float(self.image[INDEX[name], 3])

    def in_frame(self, name: str) -> bool:
        x, y = self.image[INDEX[name], :2]
        return 0.0 <= x <= 1.0 and 0.0 <= y <= 1.0


def model_path(models_dir: Path, variant: str = "lite") -> Path:
    return Path(models_dir) / f"pose_landmarker_{variant}.task"


def download_model(models_dir: Path, variant: str = "lite") -> Path:
    if variant not in VARIANTS:
        raise ValueError(f"variant must be one of {VARIANTS}")
    path = model_path(models_dir, variant)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".part")
    urllib.request.urlretrieve(MODEL_URL.format(v=variant), tmp)
    if not zipfile.is_zipfile(tmp):  # .task bundles are zip archives
        tmp.unlink()
        raise RuntimeError("downloaded file is not a .task bundle")
    tmp.replace(path)
    return path


class PoseEstimator:
    """One instance per source run: VIDEO mode requires strictly increasing timestamps,
    so a replay or source switch must open a new estimator."""

    def __init__(self, model: Path, min_detection: float = 0.5, min_presence: float = 0.5, min_tracking: float = 0.5):
        if not Path(model).is_file():
            raise FileNotFoundError(f"{model} missing; run `fitness-ml download-model`")
        vision = mp.tasks.vision
        options = vision.PoseLandmarkerOptions(
            base_options=mp.tasks.BaseOptions(model_asset_path=str(model)),  # CPU delegate by default
            running_mode=vision.RunningMode.VIDEO, num_poses=1,
            min_pose_detection_confidence=min_detection, min_pose_presence_confidence=min_presence,
            min_tracking_confidence=min_tracking)
        self._landmarker = vision.PoseLandmarker.create_from_options(options)
        self._last_ms = -1

    def detect(self, bgr: np.ndarray, timestamp_ms: float) -> Pose | None:
        t = max(int(timestamp_ms), self._last_ms + 1)
        self._last_ms = t
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        result = self._landmarker.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), t)
        if not result.pose_landmarks:
            return None
        image = np.array([[l.x, l.y, l.z, _or_nan(l.visibility), _or_nan(l.presence)] for l in result.pose_landmarks[0]])
        world = (np.array([[l.x, l.y, l.z] for l in result.pose_world_landmarks[0]])
                 if result.pose_world_landmarks else None)
        return Pose(image, world, bgr.shape[1], bgr.shape[0])

    def close(self):
        self._landmarker.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()


def _or_nan(v) -> float:
    return float("nan") if v is None else float(v)
