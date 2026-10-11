"""Deadlift form model from MyDeadlift's published per-frame angles. The public release has no videos,
only Extracted_keypoints.csv: Split;Label;Video;Frame;Sudut_Lutut;Sudut_Pinggul;Sudut_Punggung_Vertikal
(knee, hip, back-to-vertical; semicolon-separated, decimal comma; 30 fps; one rep per video).

Why calibration: within each lifter the classes are cleanly ordered (setup knee angle: knees-past-toes <
correct < rounded back), but absolute angles differ more *between* lifters than between classes. So each rep
is judged relative to the lifter's own first clean reps (`calibration_reps`), exactly as the live analyzer
does. Those calibration reps are never trained on or scored.

Honesty rules: model, features and fault threshold are chosen by leave-one-subject-out CV on the training
subjects; the dataset's test subjects (S04, S07) are scored once, at the end.
"""
import csv
import json
import time
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from ..artifacts import ANGLE_FEATURES, keypose_curve
from .dataset import sha256
from .evaluate import score, write_report
from .manifest import MYDEADLIFT_ISSUE, MYDEADLIFT_NAME
from .train import git, package_version

FPS = 30.0
NONE = "none"
THRESHOLDS = (0.0, 0.4, 0.5, 0.6, 0.7, 0.8)
# A calibration rep the *uncalibrated* model rates P(fault) >= this is refused as baseline. Chosen by
# subject-wise CV on training lifters (2026-10-10): refuses 57% of faulty reps, 13% of clean ones.
GUARD_THRESHOLD = 0.7


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


def train_deadlift_angles(csv_path: Path, out_root: Path, model: str, seed: int, calibration_reps: int = 3,
                          max_false_correction: float = 0.10) -> Path:
    clips = load(csv_path)
    rng = np.random.default_rng(seed)
    raw = np.array([keypose_curve(c.angles, c.ts) for c in clips])
    y = np.array([c.label for c in clips])
    subjects = np.array([c.subject for c in clips])
    is_train = np.array([c.split.startswith("train") for c in clips])
    if set(subjects[is_train]) & set(subjects[~is_train]):
        raise ValueError("subjects appear in both splits")
    x, scored = _calibrate(raw, y, subjects, calibration_reps, rng)
    labels = sorted(set(y))

    cv = _loso_cv(x, y, subjects, is_train & scored, labels, model, seed)
    threshold = _pick_threshold(cv, max_false_correction)
    final = _fit(model, seed, x[is_train & scored], y[is_train & scored])

    out = _save(Path(out_root), final, model, labels, csv_path, clips, is_train, scored, seed, calibration_reps,
                threshold, cv)
    if calibration_reps:
        _save_guard(out, raw, y, subjects, is_train, labels, model, seed)
    test = ~is_train & scored
    proba = _proba(final, x[test], labels)
    pred = _apply_threshold(proba, labels, threshold)
    report = {"artifact": out.name, "split": "test", "participants": sorted(set(subjects[test])),
              "clips_scored": int(test.sum()), "calibration_reps_excluded": int((~is_train & ~scored).sum()),
              "fault_threshold": threshold, **score(y[test], pred, proba.max(1), labels, "form_issue"),
              "without_threshold": {k: v for k, v in score(y[test], np.array(labels)[proba.argmax(1)], proba.max(1),
                                                           labels, "form_issue").items()
                                    if k in ("macro_f1", "false_correction_rate")}}
    write_report(report, out / "metrics_test.json")
    print(f"saved {out}")
    return out


def _save_guard(out: Path, raw, y, subjects, is_train, labels, model, seed) -> None:
    """Uncalibrated model used only to refuse obviously faulty baseline reps. Its CV refusal rates go in metadata."""
    import joblib
    cv = _loso_cv(raw, y, subjects, is_train, labels, model, seed)
    p_fault = 1 - cv["proba"][:, labels.index(NONE)]
    clean = cv["y"] == NONE
    joblib.dump(_fit(model, seed, raw[is_train], y[is_train]), out / "guard.joblib")
    meta = json.loads((out / "metadata.json").read_text())
    meta["guard"] = {"threshold": GUARD_THRESHOLD, "file": "guard.joblib",
                     "cv_faulty_reps_refused": round(float((p_fault[~clean] >= GUARD_THRESHOLD).mean()), 4),
                     "cv_clean_reps_refused": round(float((p_fault[clean] >= GUARD_THRESHOLD).mean()), 4)}
    (out / "metadata.json").write_text(json.dumps(meta, indent=2))
    print(f"baseline guard: CV refuses {meta['guard']['cv_faulty_reps_refused']:.0%} of faulty reps, "
          f"{meta['guard']['cv_clean_reps_refused']:.0%} of clean reps")


def _calibrate(x, y, subjects, n, rng):
    """Subtract each subject's mean of `n` randomly chosen clean reps. Returns (x, scored_mask)."""
    scored = np.ones(len(x), dtype=bool)
    if n <= 0:
        return x, scored
    x = x.copy()
    for s in sorted(set(subjects)):
        clean = np.where((subjects == s) & (y == NONE))[0]
        if len(clean) <= n:
            raise ValueError(f"{s} has only {len(clean)} clean reps; need more than {n} to calibrate")
        ref = rng.choice(clean, n, replace=False)
        scored[ref] = False
        x[subjects == s] -= x[ref].mean(0)
    return x, scored


def _loso_cv(x, y, subjects, mask, labels, model, seed) -> dict:
    """Leave-one-subject-out over the training subjects; returns pooled out-of-fold probabilities."""
    idx = np.where(mask)[0]
    proba = np.zeros((len(idx), len(labels)))
    for s in sorted(set(subjects[idx])):
        held = subjects[idx] == s
        m = _fit(model, seed, x[idx[~held]], y[idx[~held]])
        proba[held] = _proba(m, x[idx[held]], labels)
    return {"y": y[idx], "proba": proba, "labels": labels}


def _pick_threshold(cv: dict, max_false_correction: float) -> float:
    """Lowest threshold whose CV false-correction rate is within budget (keeps the most faults caught)."""
    from sklearn.metrics import f1_score
    rows = []
    for th in THRESHOLDS:
        pred = _apply_threshold(cv["proba"], cv["labels"], th)
        clean = cv["y"] == NONE
        fc = float((pred[clean] != NONE).mean())
        recall = float((pred[~clean] != NONE).mean())
        f1 = float(f1_score(cv["y"], pred, labels=cv["labels"], average="macro"))
        rows.append((th, fc, recall, f1))
        print(f"  CV threshold {th}: macro-F1 {f1:.3f}  false corrections {fc:.2f}  faults caught {recall:.2f}")
    cv["table"] = [dict(threshold=t, false_correction=round(fc, 4), fault_recall=round(r, 4), macro_f1=round(f, 4))
                   for t, fc, r, f in rows]
    within = [t for t, fc, _, _ in rows if fc <= max_false_correction]
    return within[0] if within else THRESHOLDS[-1]


def _apply_threshold(proba, labels, threshold) -> np.ndarray:
    """Predict the most likely fault only if its probability >= threshold, otherwise 'none'."""
    best = np.array(labels)[proba.argmax(1)]
    return np.where((best != NONE) & (proba.max(1) >= threshold), best, NONE)


def _fit(model, seed, x, y):
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.impute import SimpleImputer
    from sklearn.neighbors import KNeighborsClassifier
    from sklearn.pipeline import make_pipeline
    from sklearn.preprocessing import StandardScaler
    estimator = (RandomForestClassifier(n_estimators=300, class_weight="balanced", random_state=seed, n_jobs=-1)
                 if model == "rf" else KNeighborsClassifier(n_neighbors=5, weights="distance"))
    return make_pipeline(SimpleImputer(strategy="median", keep_empty_features=True), StandardScaler(), estimator).fit(x, y)


def _proba(model, x, labels):
    return model.predict_proba(x)[:, [list(model.classes_).index(label) for label in labels]]


def _save(out_root, model, kind, labels, csv_path, clips, is_train, scored, seed, calibration_reps, threshold, cv) -> Path:
    import joblib
    revision = git("rev-parse", "HEAD")
    version = f"form_issue-deadlift-angles-{kind}-{time.strftime('%Y%m%d-%H%M%S')}-{(revision or 'norev')[:7]}"
    out = out_root / version
    out.mkdir(parents=True, exist_ok=True)
    joblib.dump(model, out / "model.joblib")
    subjects = np.array([c.subject for c in clips])
    (out / "metadata.json").write_text(json.dumps({
        "model_version": version, "task": "form_issue", "exercise": "deadlift", "model": kind, "labels": labels,
        "feature_set": "side_angles", "feature_fn": "keypose_curve_v1", "feature_names": list(ANGLE_FEATURES),
        "calibration_reps": calibration_reps, "fault_threshold": threshold,
        "window": "one rep, including the setup posture before the lift",
        "source": "MyDeadlift Extracted_keypoints.csv (CC BY 4.0)", "csv_sha256": sha256(csv_path),
        "split": {"train": sorted(set(subjects[is_train])), "test": sorted(set(subjects[~is_train])),
                  "rule": "dataset's published subject-wise split"},
        "train_clips": {lbl: int(((np.array([c.label for c in clips]) == lbl) & is_train & scored).sum()) for lbl in labels},
        "cv": {"method": "leave-one-subject-out on training subjects", "thresholds": cv["table"]},
        "seed": seed, "code_revision": revision, "code_dirty": bool(git("status", "--porcelain", "--", "ml/src")),
        "packages": {p: package_version(p) for p in ("numpy", "scikit-learn")},
        "trained_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    }, indent=2))
    return out


def _num(text: str) -> float:
    text = text.strip()
    return float(text.replace(",", ".")) if text else float("nan")
