"""Dataset manifests: one row per video with participant, view, exercise, variation and labels.

Everything downstream reads only the manifest, so adding a dataset = adding an adapter here.
Adapters never guess: a file whose labels can't be parsed is skipped and reported.

Verified from the dataset pages (2026-10-10):
- MyDeadlift (CC BY 4.0): files "<CLASS>_S<subject>_R<rep>.mp4"; GB = correct, PB = rounded back,
  LLK = knees beyond toes; 7 subjects, side view, one repetition per video. Official test subjects: S04, S07.
- Multi-View Fitness (CC BY 4.0): 26 subjects, front/side/diagonal, good/bad quality, files named
  subject_<ID>_<exercise>_<quality>_<view>.mp4 (README). Shipped as three 3.1 GB zips with the same videos
  in different folder layouts: download one; files are de-duplicated by name anyway.
  Its curl is the *alternating* dumbbell curl and its squat is *bodyweight*. It has no deadlift.
- MyDeadlift's public release contains NO videos, only Extracted_keypoints.csv (per-frame knee, hip and
  back-to-vertical angles). It can't go through this video manifest; see training/deadlift_angles.py.
"""
import csv
import re
from collections import Counter
from dataclasses import asdict, dataclass, fields
from pathlib import Path

VIDEO_SUFFIXES = {".mp4", ".mov", ".avi", ".mkv", ".m4v"}
from ..config import EXERCISES as _CONFIGURED

EXERCISES = (*_CONFIGURED, "other")  # "other" = movement we have no analyzer for


@dataclass
class Row:
    video_id: str
    path: str
    dataset: str
    participant_id: str
    camera_view: str        # front | side | diagonal | unknown
    exercise: str           # an id from config.EXERCISES, or "other"
    variation: str
    form_label: str = ""    # good | bad | "" (unlabelled)
    issue_label: str = ""   # none | <specific labelled error> | ""
    license: str = ""


COLUMNS = [f.name for f in fields(Row)]


def read(path: Path) -> list[Row]:
    with open(path, newline="") as f:
        rows = [Row(**{c: r.get(c, "") or "" for c in COLUMNS}) for r in csv.DictReader(f)]
    for r in rows:
        if r.exercise not in EXERCISES:
            raise ValueError(f"{r.video_id}: exercise {r.exercise!r} not in {EXERCISES}")
    return rows


def write(path: Path, rows: list[Row]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, COLUMNS)
        w.writeheader()
        w.writerows(asdict(r) for r in rows)


def summary(rows: list[Row]) -> str:
    counts = Counter((r.dataset, r.exercise, r.variation, r.camera_view, r.form_label or "-", r.issue_label or "-") for r in rows)
    people = Counter(r.dataset for r in {(r.dataset, r.participant_id): r for r in rows}.values())
    lines = [f"{len(rows)} videos; participants per dataset: {dict(people)}"]
    lines += [f"  {n:4d}  " + " / ".join(k) for k, n in sorted(counts.items())]
    return "\n".join(lines)


def _videos(root: Path):
    return sorted(p for p in root.rglob("*") if p.suffix.lower() in VIDEO_SUFFIXES and p.is_file())


# --- MyDeadlift (names only: the release has no videos; training/deadlift_angles.py uses its CSV) ---
MYDEADLIFT_NAME = re.compile(r"^(GB|PB|LLK)_S(\d+)_R(\d+)$", re.IGNORECASE)
MYDEADLIFT_ISSUE = {"GB": "none", "PB": "rounded_back", "LLK": "knees_past_toes"}


# --- Multi-View Fitness -------------------------------------------------------------------------
# README (v3): every video is named subject_<ID>_<exercise>_<quality>_<view>.mp4 in all three layouts.
# One published file says "bicep" instead of "bicep_curl" (subject_003_bicep_good_side.mp4, in bicep_curl/good/side/).
MULTIVIEW_NAME = re.compile(r"^subject_(\d+)_(abs|back|bicep(?:_curl)?|push_up|shoulder|squat|tricep)_(good|bad)_(front|side|diagonal)$",
                            re.IGNORECASE)
MULTIVIEW_EXERCISE = {  # dataset class -> (our id, variation per the dataset description)
    "bicep_curl": ("curl", "standing_dumbbell_alternating"),
    "squat": ("squat", "bodyweight"),
    "abs": ("side_bend", "standing_dumbbell"),
    "back": ("row", "bent_over_dumbbell"),
    "push_up": ("push_up", "standard"),
    "shoulder": ("shoulder_press", "standing_dumbbell"),
    "tricep": ("triceps_extension", "overhead_dumbbell"),
}


def multiview(root: Path) -> tuple[list[Row], list[str]]:
    rows, skipped, seen = [], [], set()
    for p in _videos(root):
        m = MULTIVIEW_NAME.match(p.stem)
        if not m:
            skipped.append(str(p))
            continue
        if p.name.lower() in seen:  # the same file appears in each of the three layouts
            continue
        seen.add(p.name.lower())
        subject, dataset_class, quality, view = int(m.group(1)), *(g.lower() for g in m.groups()[1:])
        exercise, variation = MULTIVIEW_EXERCISE["bicep_curl" if dataset_class == "bicep" else dataset_class]
        rows.append(Row(
            video_id=f"multiview:{p.name.lower()}", path=str(p), dataset="multiview",
            participant_id=f"multiview-{subject:03d}", camera_view=view, exercise=exercise, variation=variation,
            form_label=quality, issue_label="", license="CC-BY-4.0"))
    return rows, skipped


# --- Your own clips -----------------------------------------------------------------------------
def own_csv(path: Path) -> tuple[list[Row], list[str]]:
    """Your recordings: a CSV with the manifest columns (path relative to the CSV). Consent required."""
    rows = read(path)
    for r in rows:
        r.path = str((path.parent / r.path).resolve())
        r.video_id = r.video_id or f"own:{Path(r.path).name}"
        r.dataset = r.dataset or "own"
    missing = [r.path for r in rows if not Path(r.path).is_file()]
    return [r for r in rows if Path(r.path).is_file()], missing


ADAPTERS = {"multiview": multiview, "csv": own_csv}
