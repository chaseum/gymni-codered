"""Count-validation CSV: run annotated clips through the real pipeline and compare against human counts.

annotations.csv columns: path, exercise, actual_reps[, variation, notes]   (path relative to the CSV)
"""
import csv
import time
from collections import Counter
from pathlib import Path

import numpy as np

from .analyzer import Analyzer
from .config import Config
from .pipeline import Step, observe
from .pose import PoseEstimator
from .sources import VideoFile

COLUMNS = ["clip", "exercise", "variation", "source", "actual_reps", "predicted_reps", "over_count", "missed",
           "frames", "lost_frames", "low_visibility_frames", "unassessable_frames", "observed_issues",
           "unassessable_checks", "fps", "mean_latency_ms", "p95_latency_ms", "notes"]


class ClipStats:
    def __init__(self):
        self.tracking: Counter = Counter()
        self.issues: Counter = Counter()
        self.unassessable: Counter = Counter()
        self.latencies: list[float] = []
        self.reps = 0
        self._started = time.perf_counter()

    def add(self, step: Step) -> None:
        self.tracking[step.result.observation.tracking_status] += 1
        self.latencies.append(step.latency_ms)
        self.reps = step.result.local_rep_count
        for a in step.result.candidates:
            if a.status == "issue":
                self.issues[a.code] += 1
            elif a.status == "unassessable":
                self.unassessable[f"{a.code}:{a.evidence.get('reason')}"] += 1

    def row(self, clip: str, exercise: str, variation: str, source: str, actual: int | None, notes: str = "") -> dict:
        frames = sum(self.tracking.values())
        elapsed = time.perf_counter() - self._started
        lat = np.array(self.latencies or [0.0])
        return {"clip": clip, "exercise": exercise, "variation": variation, "source": source,
                "actual_reps": actual, "predicted_reps": self.reps,
                "over_count": None if actual is None else max(0, self.reps - actual),
                "missed": None if actual is None else max(0, actual - self.reps),
                "frames": frames, "lost_frames": self.tracking["lost"],
                "low_visibility_frames": self.tracking["low_visibility"],
                "unassessable_frames": self.tracking["unassessable"],
                "observed_issues": _fmt_counts(self.issues), "unassessable_checks": _fmt_counts(self.unassessable),
                "fps": round(frames / elapsed, 1) if elapsed else None,
                "mean_latency_ms": round(float(lat.mean()), 1), "p95_latency_ms": round(float(np.percentile(lat, 95)), 1),
                "notes": notes}


def validate_clips(annotations: Path, out: Path, pose_model: Path, config: Config) -> list[dict]:
    rows = []
    with open(annotations, newline="") as f:
        for ann in csv.DictReader(f):
            clip = VideoFile(annotations.parent / ann["path"])
            exercise = ann["exercise"]
            variation = ann.get("variation") or config.exercises[exercise].variation
            analyzer = Analyzer(exercise, "validation", "recorded", clip_id=clip.clip_id, variation=variation, config=config)
            stats = ClipStats()
            with PoseEstimator(pose_model) as estimator:  # fresh estimator per clip: timestamps restart
                for step in observe(clip, estimator, analyzer):
                    stats.add(step)
            rows.append(stats.row(ann["path"], exercise, variation, "recorded", int(ann["actual_reps"]), ann.get("notes", "")))
            print(f"{ann['path']}: actual {ann['actual_reps']} predicted {stats.reps}")
    append_rows(out, rows)
    return rows


def append_rows(out: Path, rows: list[dict]) -> None:
    new = not out.exists()
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "a", newline="") as f:
        writer = csv.DictWriter(f, COLUMNS)
        if new:
            writer.writeheader()
        writer.writerows(rows)


def _fmt_counts(counts: Counter) -> str:
    return ";".join(f"{k}x{v}" for k, v in sorted(counts.items()))
