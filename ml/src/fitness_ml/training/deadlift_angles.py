"""Deadlift form model from MyDeadlift's published per-frame angles. The public release has no videos,
only Extracted_keypoints.csv: Split;Label;Video;Frame;Sudut_Lutut;Sudut_Pinggul;Sudut_Punggung_Vertikal
(knee, hip, back-to-vertical; semicolon-separated, decimal comma; 30 fps; one rep per video).

At runtime the same three angles come from our 2D side-view features (tracked side's knee and hip, trunk
lean). The dataset computed its angles with its own MediaPipe setup, so expect some domain shift: check the
live behaviour on your own side-view deadlifts before trusting the model.
"""
import csv
import json
import time
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from ..artifacts import ANGLE_FEATURES
from ..features import aggregate
from .dataset import sha256
from .evaluate import score, write_report
from .manifest import MYDEADLIFT_ISSUE, MYDEADLIFT_NAME
from .train import git, package_version

FPS = 30.0


@dataclass
class Clip:
    video: str
    subject: str
    split: str          # "training" | "testing" (the dataset's own subject-wise split: S04, S07 in testing)
    label: str          # none | rounded_back | knees_past_toes
    ts: np.ndarray
    angles: np.ndarray  # (T, 3) knee, hip, back-to-vertical


def load(path: Path) -> list[Clip]:
    frames = defaultdict(list)
    meta = {}
    with open(path, newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f, delimiter=";"):
            video = row["Video"].strip()
            m = MYDEADLIFT_NAME.match(Path(video).stem)
            if not m:
                raise ValueError(f"unexpected video name {video!r}")
            meta[video] = (f"mydeadlift-S{int(m.group(2)):02d}", row["Split"].strip().lower(), MYDEADLIFT_ISSUE[m.group(1).upper()])
            frames[video].append((int(row["Frame"]), *(_num(row[c]) for c in
                                                       ("Sudut_Lutut", "Sudut_Pinggul", "Sudut_Punggung_Vertikal"))))
    clips = []
    for video, rows in sorted(frames.items()):
        rows.sort()
        arr = np.array(rows, dtype=float)
        subject, split, label = meta[video]
        clips.append(Clip(video, subject, split, label, (arr[:, 0] - 1) * 1000 / FPS, arr[:, 1:]))
    return clips


def train_deadlift_angles(csv_path: Path, out_root: Path, model: str, seed: int) -> Path:
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.impute import SimpleImputer
    from sklearn.neighbors import KNeighborsClassifier
    from sklearn.pipeline import make_pipeline
    from sklearn.preprocessing import StandardScaler
    import joblib

    clips = load(csv_path)
    train = [c for c in clips if c.split.startswith("train")]
    test = [c for c in clips if c.split.startswith("test")]
    overlap = {c.subject for c in train} & {c.subject for c in test}
    if overlap:
        raise ValueError(f"subjects in both splits: {overlap}")
    estimator = (RandomForestClassifier(n_estimators=300, class_weight="balanced", random_state=seed, n_jobs=-1)
                 if model == "rf" else KNeighborsClassifier(n_neighbors=5, weights="distance"))
    pipe = make_pipeline(SimpleImputer(strategy="median", keep_empty_features=True), StandardScaler(), estimator)
    pipe.fit(x(train), y(train))

    revision = git("rev-parse", "HEAD")
    version = f"form_issue-deadlift-angles-{model}-{time.strftime('%Y%m%d-%H%M%S')}-{(revision or 'norev')[:7]}"
    out = Path(out_root) / version
    out.mkdir(parents=True, exist_ok=True)
    joblib.dump(pipe, out / "model.joblib")
    labels = sorted(set(y(train)))
    (out / "metadata.json").write_text(json.dumps({
        "model_version": version, "task": "form_issue", "exercise": "deadlift", "model": model, "labels": labels,
        "feature_set": "side_angles", "feature_names": list(ANGLE_FEATURES), "window": "one rep (whole clip)",
        "source": "MyDeadlift Extracted_keypoints.csv (CC BY 4.0)", "csv_sha256": sha256(csv_path),
        "split": {"train": sorted({c.subject for c in train}), "test": sorted({c.subject for c in test}),
                  "rule": "dataset's published subject-wise split"},
        "train_clips": {lbl: int((y(train) == lbl).sum()) for lbl in labels}, "seed": seed,
        "code_revision": revision, "code_dirty": bool(git("status", "--porcelain", "--", "ml/src")),
        "packages": {p: package_version(p) for p in ("numpy", "scikit-learn")},
        "trained_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    }, indent=2))
    proba = pipe.predict_proba(x(test))
    order = [list(pipe.classes_).index(lbl) for lbl in labels]
    proba = proba[:, order]
    report = {"artifact": version, "split": "test", "participants": sorted({c.subject for c in test}),
              "clips": len(test), **score(y(test), np.array(labels)[proba.argmax(1)], proba.max(1), labels, "form_issue")}
    write_report(report, out / "metrics_test.json")
    print(f"saved {out}")
    return out


def x(clips: list[Clip]) -> np.ndarray:
    return np.array([aggregate(c.angles, c.ts) for c in clips])


def y(clips: list[Clip]) -> np.ndarray:
    return np.array([c.label for c in clips])


def _num(text: str) -> float:
    text = text.strip()
    return float(text.replace(",", ".")) if text else float("nan")
