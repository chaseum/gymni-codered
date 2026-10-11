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


# --- Kaggle "Workout/Exercises Video" (Hasyim Abdillah, CC BY-NC-SA 4.0) ------------------------
# https://www.kaggle.com/datasets/hasyimabdillah/workoutfitness-video  - one folder per exercise, mostly YouTube clips.
# No person IDs are published, so each video is its own "participant": splits are video-disjoint, NOT person-disjoint
# (two clips of the same creator can land on both sides), so its test scores are optimistic.
KAGGLE_EXERCISE = {  # folder -> (our id, variation); everything else becomes "other" (a real reject class)
    "deadlift": ("deadlift", "unspecified"),
    "squat": ("squat", "unspecified"),
    "push-up": ("push_up", "standard"),
    "barbell biceps curl": ("curl", "standing_barbell"),
    "hammer curl": ("curl", "hammer"),
    "shoulder press": ("shoulder_press", "unspecified"),
    "t bar row": ("row", "t_bar"),
    # "romanian deadlift" starts standing (our deadlift counter starts at the floor): kept as "other" on purpose.
}


def kaggle_workout(root: Path) -> tuple[list[Row], list[str]]:
    rows = []
    for p in _videos(root):
        folder = p.parent.name.lower()
        exercise, variation = KAGGLE_EXERCISE.get(folder, ("other", folder.replace(" ", "_")))
        rows.append(Row(
            video_id=f"kaggle:{folder}/{p.name}", path=str(p), dataset="kaggle_workout",
            participant_id=f"kaggle-video-{folder.replace(' ', '_')}-{p.stem.rsplit('_', 1)[-1]}",
            camera_view="unknown", exercise=exercise, variation=variation, license="CC-BY-NC-SA-4.0"))
    return rows, []


# --- weggry/deadlift-classifier (MDPI AI 2025, doi:10.3390/ai6070148) ---------------------------
# https://github.com/weggry/deadlift-classifier "Raw MP4 Videos": <style>_<fault>_<n>[_flipped].mp4, side view,
# one rep per clip, 50 clips per style x fault. NO LICENSE is published: use for this non-commercial project only,
# credit the paper, never commit or redistribute the videos. No person IDs either, so splits are per video (optimistic).
# "_flipped" files are mirror copies of the originals: skipped, otherwise a clip and its mirror could straddle
# train/test.
WEGGRY_NAME = re.compile(r"^(conv|S|R)_(corr|ehe|oe|rb)_(\d+)(_flipped)?$")
WEGGRY_STYLE = {"conv": ("deadlift", "conventional"), "S": ("deadlift", "sumo"),
                "R": ("other", "romanian_deadlift")}  # RDL starts standing; our deadlift counter starts at the floor
WEGGRY_FAULT = {"corr": "none", "ehe": "hips_rise_early", "oe": "back_overextension", "rb": "rounded_back"}


def weggry_deadlift(root: Path) -> tuple[list[Row], list[str]]:
    rows, skipped = [], []
    for p in _videos(root):
        m = WEGGRY_NAME.match(p.stem)
        if not m:
            skipped.append(str(p))
            continue
        style, fault, n, flipped = m.groups()
        if flipped:
            continue
        exercise, variation = WEGGRY_STYLE[style]
        rows.append(Row(
            video_id=f"weggry:{p.name}", path=str(p), dataset="weggry_deadlift",
            participant_id=f"weggry-video-{style}-{fault}-{n}", camera_view="side", exercise=exercise,
            variation=variation, form_label="good" if fault == "corr" else "bad", issue_label=WEGGRY_FAULT[fault],
            license="no license published; non-commercial project use, credited, not redistributed"))
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


def add_clips(manifest: Path, videos: list[Path], exercise: str, participant: str, view: str,
              variation: str = "", form_label: str = "") -> list[Row]:
    """Append your own recordings to `manifest` (created if missing). Re-adding a clip replaces its row."""
    if exercise not in EXERCISES:
        raise ValueError(f"exercise must be one of {EXERCISES}")
    rows = {r.video_id: r for r in read(manifest)} if manifest.exists() else {}
    if not variation and exercise in _CONFIGURED:
        variation = _CONFIGURED[exercise].variation
    for video in videos:
        if not video.is_file():
            raise FileNotFoundError(video)
        row = Row(video_id=f"own:{participant}:{video.name}", path=str(video.resolve()), dataset="own",
                  participant_id=f"own-{participant}", camera_view=view, exercise=exercise,
                  variation=variation,
                  form_label=form_label, license="own recording (consented)")
        rows[row.video_id] = row
    write(manifest, list(rows.values()))
    return list(rows.values())


ADAPTERS = {"multiview": multiview, "kaggle_workout": kaggle_workout, "weggry_deadlift": weggry_deadlift,
            "csv": own_csv}
