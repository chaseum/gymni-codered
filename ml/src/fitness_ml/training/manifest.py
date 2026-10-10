"""Dataset manifests: one row per video with participant, view, exercise, variation and labels.

Everything downstream reads only the manifest, so adding a dataset = adding an adapter here.
Adapters never guess: a file whose labels can't be parsed is skipped and reported.

Verified from the dataset pages (2026-10-10):
- MyDeadlift (CC BY 4.0): files "<CLASS>_S<subject>_R<rep>.mp4"; GB = correct, PB = rounded back,
  LLK = knees beyond toes; 7 subjects, side view, one repetition per video. Official test subjects: S04, S07.
- Multi-View Fitness (CC BY 4.0): 26 subjects, front/side/diagonal, good/bad quality; the same videos are
  shipped in three folder layouts, so files are de-duplicated. File naming is NOT documented: the adapter
  reads subject/exercise/quality/view from folder and file names; check the skipped list on first run.
  Its curl is the *alternating* dumbbell curl and its squat is *bodyweight*. It has no deadlift.
"""
import csv
import re
from collections import Counter
from dataclasses import asdict, dataclass, fields
from pathlib import Path

VIDEO_SUFFIXES = {".mp4", ".mov", ".avi", ".mkv", ".m4v"}
EXERCISES = ("curl", "squat", "deadlift", "other")


@dataclass
class Row:
    video_id: str
    path: str
    dataset: str
    participant_id: str
    camera_view: str        # front | side | diagonal | unknown
    exercise: str           # curl | squat | deadlift | other
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


# --- MyDeadlift ---------------------------------------------------------------------------------
MYDEADLIFT_NAME = re.compile(r"^(GB|PB|LLK)_S(\d+)_R(\d+)$", re.IGNORECASE)
MYDEADLIFT_ISSUE = {"GB": "none", "PB": "rounded_back", "LLK": "knees_past_toes"}


def mydeadlift(root: Path) -> tuple[list[Row], list[str]]:
    rows, skipped = [], []
    for p in _videos(root):
        m = MYDEADLIFT_NAME.match(p.stem)
        if not m:
            skipped.append(str(p))
            continue
        cls, subject = m.group(1).upper(), int(m.group(2))
        rows.append(Row(
            video_id=f"mydeadlift:{p.relative_to(root)}", path=str(p), dataset="mydeadlift",
            participant_id=f"mydeadlift-S{subject:02d}", camera_view="side", exercise="deadlift",
            variation="unspecified",  # page doesn't say conventional vs sumo: check the videos before relying on it
            form_label="good" if cls == "GB" else "bad", issue_label=MYDEADLIFT_ISSUE[cls], license="CC-BY-4.0"))
    return rows, skipped


# --- Multi-View Fitness -------------------------------------------------------------------------
# (pattern on the lower-cased relative path, exercise id, variation). Each video must match exactly one.
MULTIVIEW_EXERCISES = [
    (r"curl", "curl", "standing_dumbbell_alternating"),
    (r"squat", "squat", "bodyweight"),
    (r"tricep", "other", "overhead_dumbbell_triceps_extension"),
    (r"shoulder[ _-]?press|\bpress\b", "other", "standing_dumbbell_shoulder_press"),
    (r"push[ _-]?up|pushup", "other", "push_up"),
    (r"\brow\b|bent[ _-]?over", "other", "bent_over_dumbbell_row"),
    (r"side[ _-]?bend|\bbend\b", "other", "standing_dumbbell_side_bend"),
]
QUALITY = {"good": "good", "correct": "good", "bad": "bad", "incorrect": "bad", "wrong": "bad"}
VIEWS = {"front": "front", "side": "side", "diagonal": "diagonal", "diag": "diagonal"}
SUBJECT = re.compile(r"^(?:subject|sub|participant|person|s|p)[ _-]?0*(\d{1,3})$", re.IGNORECASE)


def multiview(root: Path) -> tuple[list[Row], list[str]]:
    rows, skipped, seen = [], [], set()
    for p in _videos(root):
        key = (p.name, p.stat().st_size)  # the three layouts contain the same files
        if key in seen:
            continue
        seen.add(key)
        rel = str(p.relative_to(root)).lower()
        exercise = [(pattern, ex, var) for pattern, ex, var in MULTIVIEW_EXERCISES if re.search(pattern, rel)]
        # Strip the exercise name first: "side bend" must not read as the "side" camera view.
        rest = re.sub(exercise[0][0], " ", rel) if len(exercise) == 1 else rel
        tokens = [t for t in re.split(r"[^a-z0-9]+", rest) if t]
        quality = {QUALITY[t] for t in tokens if t in QUALITY}
        view = {VIEWS[t] for t in tokens if t in VIEWS}
        joined = [a + b for a, b in zip(tokens, tokens[1:]) if b.isdigit()]  # "subject 01" -> "subject01"
        subject = {int(m.group(1)) for t in tokens + joined if (m := SUBJECT.match(t))}
        if len(exercise) != 1 or len(quality) != 1 or len(view) != 1 or len(subject) != 1:
            skipped.append(f"{p}  (exercise={[e[1:] for e in exercise]} quality={quality} view={view} subject={subject})")
            continue
        (_, ex, var), = exercise
        rows.append(Row(
            video_id=f"multiview:{p.relative_to(root)}", path=str(p), dataset="multiview",
            participant_id=f"multiview-{subject.pop():02d}", camera_view=view.pop(), exercise=ex, variation=var,
            form_label=quality.pop(), issue_label="", license="CC-BY-4.0"))
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


ADAPTERS = {"mydeadlift": mydeadlift, "multiview": multiview, "csv": own_csv}
