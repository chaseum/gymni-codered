"""Participant-disjoint splits, then windows. Splitting happens on people BEFORE any windowing,
so frames, reps and windows of one person never appear on both sides."""
import hashlib
import json
import random
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from ..features import frame_features, to_matrix
from .extract import cache_file, load_poses
from .manifest import Row

MIN_TRACKED_FRAC = 0.6


@dataclass
class Window:
    matrix: np.ndarray      # (T, F) frame features
    ts: np.ndarray          # (T,) ms
    label: str
    row: Row


# --- split -------------------------------------------------------------------------------------
def make_split(rows: list[Row], manifest: Path, seed: int, test_frac: float, val_frac: float,
               test_participants: list[str] | None = None) -> dict:
    """Per dataset, shuffle participants and cut test/val/train. `test_participants` pins the test set
    (e.g. MyDeadlift's official S04/S07); the rest of that dataset still gets a val cut."""
    rng = random.Random(seed)
    pinned = set(test_participants or [])
    by_dataset = defaultdict(set)
    for r in rows:
        by_dataset[r.dataset].add(r.participant_id)
    split = {"train": [], "val": [], "test": []}
    for dataset in sorted(by_dataset):
        people = sorted(by_dataset[dataset])
        test = [p for p in people if p in pinned]
        rest = [p for p in people if p not in pinned]
        rng.shuffle(rest)
        if not test:
            n_test = max(1, round(test_frac * len(people))) if len(people) >= 3 else 0
            test, rest = rest[:n_test], rest[n_test:]
        n_val = max(1, round(val_frac * len(people))) if len(rest) >= 3 else 0
        split["test"] += test
        split["val"] += rest[:n_val]
        split["train"] += rest[n_val:]
    assert not (set(split["train"]) & set(split["test"])) and not (set(split["val"]) & set(split["test"]))
    split.update(seed=seed, test_frac=test_frac, val_frac=val_frac, pinned_test=sorted(pinned),
                 manifest_sha256=sha256(manifest))
    return split


def sha256(path: Path) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load_split(path: Path) -> dict:
    return json.loads(Path(path).read_text())


# --- labels ------------------------------------------------------------------------------------
def label_of(row: Row, task: str, exercise: str | None) -> str | None:
    """recognition: the exercise. form_binary: good/bad. form_issue: none/<labelled error>. None = not usable."""
    if task == "recognition":
        return row.exercise
    if row.exercise != exercise:
        return None
    value = row.form_label if task == "form_binary" else row.issue_label
    return value or None


# --- windows -----------------------------------------------------------------------------------
def windows_for(rows: list[Row], participants: set[str], cache_dir: Path, task: str, exercise: str | None,
                window_ms: float, stride_ms: float, segment: str = "window") -> list[Window]:
    """segment="window": fixed windows every stride (recognition, which sees rolling windows live).
    segment="rep": one sample per rep found by the live rep counter, incl. the setup pre-roll, exactly what the
    form models receive live; videos where the counter finds no rep fall back to fixed windows (reported)."""
    out, no_reps, videos = [], 0, 0
    for row in rows:
        label = label_of(row, task, exercise)
        if row.participant_id not in participants or label is None:
            continue
        path = cache_file(cache_dir, row.video_id)
        if not path.exists():
            raise FileNotFoundError(f"{row.video_id}: no landmark cache, run `fitness-train extract` first")
        ts, poses = load_poses(path)
        if len(ts) < 2:
            continue
        videos += 1
        matrix = to_matrix([frame_features(p) for p in poses])
        bounds = rep_bounds(ts, poses, row.exercise) if segment == "rep" else []
        if not bounds:
            no_reps += segment == "rep"
            bounds = window_bounds(ts, window_ms, stride_ms)
        for lo, hi in bounds:
            m = matrix[lo:hi]
            if hi - lo >= 2 and (~np.isnan(m).all(axis=1)).mean() >= MIN_TRACKED_FRAC:
                out.append(Window(m, ts[lo:hi], label, row))
    if segment == "rep" and videos:
        print(f"rep segmentation: {videos - no_reps}/{videos} videos cut into reps; {no_reps} had no counted rep "
              f"and used fixed windows")
    return out


def rep_bounds(ts: np.ndarray, poses: list, exercise: str) -> list[tuple[int, int]]:
    """Index ranges of the reps the live analyzer counts in this video, each starting form_preroll_ms early."""
    from ..analyzer import Analyzer
    analyzer = Analyzer(exercise, "training", "recorded")
    preroll = analyzer.config.form_preroll_ms
    bounds = []
    for t, pose in zip(ts, poses):
        rep = analyzer.analyze_frame(pose, t).observation.completed_rep
        if rep:
            start = t - (rep.duration_ms or 0) - preroll
            bounds.append((int(np.searchsorted(ts, start)), int(np.searchsorted(ts, t, side="right"))))
    return bounds


def window_bounds(ts: np.ndarray, window_ms: float, stride_ms: float) -> list[tuple[int, int]]:
    """Index ranges of fixed-duration windows. A clip shorter than one window is one window (e.g. single-rep clips)."""
    if ts[-1] - ts[0] <= window_ms:
        return [(0, len(ts))]
    bounds = []
    start = ts[0]
    while start + window_ms <= ts[-1]:
        lo, hi = np.searchsorted(ts, start), np.searchsorted(ts, start + window_ms, side="right")
        if hi - lo >= 2:
            bounds.append((int(lo), int(hi)))
        start += stride_ms
    return bounds
