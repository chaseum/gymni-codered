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


def extract(rows: list[Row], cache_dir: Path, pose_model: Path, every: int = 1, force: bool = False,
            workers: int = 1) -> None:
    """Pose once per video into the cache. Videos already cached are skipped, so a stopped run resumes.
    `workers` > 1 runs one video per process (MediaPipe on CPU uses ~1 core per video)."""
    Path(cache_dir).mkdir(parents=True, exist_ok=True)
    todo = [r for r in rows if force or not cache_file(cache_dir, r.video_id).exists()]
    print(f"{len(rows) - len(todo)} cached, {len(todo)} to extract with {workers} worker(s)")
    if workers <= 1:
        for n, row in enumerate(todo, 1):
            print(f"[{n}/{len(todo)}] {_extract_one(row, cache_dir, pose_model, every)}")
        return
    from concurrent.futures import ProcessPoolExecutor, as_completed
    with ProcessPoolExecutor(workers) as pool:
        jobs = [pool.submit(_extract_one, row, cache_dir, pose_model, every) for row in todo]
        for n, job in enumerate(as_completed(jobs), 1):
            print(f"[{n}/{len(todo)}] {job.result()}", flush=True)


def _extract_one(row: Row, cache_dir: Path, pose_model: Path, every: int) -> str:
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
    out = cache_file(cache_dir, row.video_id)
    tmp = out.with_suffix(".tmp.npz")  # write-then-rename: a killed run never leaves a half-written cache file
    np.savez_compressed(tmp, video_id=row.video_id, ts=np.array(ts), image=np.array(image).reshape(-1, 33, 5),
                        world=np.array(world).reshape(-1, 33, 3), width=size[0], height=size[1], every=every)
    tmp.replace(out)
    tracked = sum(1 for img in image if not np.isnan(img[0, 0]))
    return f"{row.video_id}: {len(ts)} frames, pose on {tracked}"


def load_poses(path: Path) -> tuple[np.ndarray, list[Pose | None]]:
    z = np.load(path)
    w, h = int(z["width"]), int(z["height"])
    poses = [None if np.isnan(img[0, 0]) else Pose(img, None if np.isnan(wld[0, 0]) else wld, w, h)
             for img, wld in zip(z["image"], z["world"])]
    return z["ts"], poses
