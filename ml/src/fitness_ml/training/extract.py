"""Video -> landmark cache (.npz per video). Pose runs once; features can change without re-running it.
Caches hold landmarks only (no pixels), which is what should travel to a cloud GPU."""
import hashlib
from pathlib import Path

import numpy as np

from ..pose import Pose, PoseEstimator
from ..sources import VideoFile
from .manifest import Row


def cache_file(cache_dir: Path, video_id: str) -> Path:
    return Path(cache_dir) / f"{hashlib.sha1(video_id.encode()).hexdigest()[:16]}.npz"


def extract(rows: list[Row], cache_dir: Path, pose_model: Path, every: int = 1, force: bool = False) -> None:
    Path(cache_dir).mkdir(parents=True, exist_ok=True)
    for n, row in enumerate(rows, 1):
        out = cache_file(cache_dir, row.video_id)
        if out.exists() and not force:
            continue
        ts, image, world, size = [], [], [], (0, 0)
        with PoseEstimator(pose_model) as estimator:
            for frame in VideoFile(row.path).frames():
                if frame.index % every:
                    continue
                pose = estimator.detect(frame.image, frame.timestamp_ms)
                size = frame.image.shape[1], frame.image.shape[0]
                ts.append(frame.timestamp_ms)
                image.append(pose.image if pose else np.full((33, 5), np.nan))
                world.append(pose.world if pose is not None and pose.world is not None else np.full((33, 3), np.nan))
        np.savez_compressed(out, video_id=row.video_id, ts=np.array(ts), image=np.array(image).reshape(-1, 33, 5),
                            world=np.array(world).reshape(-1, 33, 3), width=size[0], height=size[1], every=every)
        tracked = int(np.sum(~np.isnan(np.array(image).reshape(-1, 33, 5)[:, 0, 0]))) if image else 0
        print(f"[{n}/{len(rows)}] {row.video_id}: {len(ts)} frames, pose on {tracked}")


def load_poses(path: Path) -> tuple[np.ndarray, list[Pose | None]]:
    z = np.load(path)
    w, h = int(z["width"]), int(z["height"])
    poses = [None if np.isnan(img[0, 0]) else Pose(img, None if np.isnan(wld[0, 0]) else wld, w, h)
             for img, wld in zip(z["image"], z["world"])]
    return z["ts"], poses
