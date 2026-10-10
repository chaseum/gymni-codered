"""Evaluate an artifact on the held-out participants recorded in its own metadata (same split, same windows).
Predictions go through Artifact.predict_proba, i.e. exactly the code path live inference uses."""
import json
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

from ..artifacts import Artifact
from .dataset import windows_for
from .manifest import read

REJECT_THRESHOLDS = (0.0, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9)


def evaluate(artifact_dir: Path, manifest: Path, cache: Path, split_name: str = "test") -> dict:
    art = Artifact(artifact_dir)
    meta = art.meta
    windows = windows_for(read(manifest), set(meta["split"][split_name]), cache, meta["task"], meta["exercise"],
                          meta["window_ms"], meta["stride_ms"])
    if not windows:
        raise ValueError(f"no {split_name} windows")
    proba = np.array([art.predict_proba(w.matrix, w.ts) for w in windows])
    y_true = np.array([w.label for w in windows])
    y_pred = np.array(art.labels)[proba.argmax(1)]
    report = {"artifact": meta["model_version"], "split": split_name, "participants": meta["split"][split_name],
              "windows": len(windows), "videos": len({w.row.video_id for w in windows}),
              **score(y_true, y_pred, proba.max(1), art.labels, meta["task"]),
              "by_camera_view": _breakdown(windows, y_true, y_pred, art.labels, lambda w: w.row.camera_view),
              "by_dataset": _breakdown(windows, y_true, y_pred, art.labels, lambda w: w.row.dataset),
              "by_video_majority_accuracy": _video_vote(windows, y_pred)}
    return write_report(report, Path(artifact_dir) / f"metrics_{split_name}.json")


def score(y_true: np.ndarray, y_pred: np.ndarray, confidence: np.ndarray, labels: list[str], task: str) -> dict:
    """Metrics shared by every trainer. Labels the model never trained on count as 'unseen': the right
    answer for them is a rejection (confidence below threshold), which the sweep measures."""
    from sklearn.metrics import classification_report, confusion_matrix, f1_score

    seen = np.isin(y_true, labels)
    report = {
        "support": dict(Counter(y_true.tolist())),
        "unseen_labels": sorted(set(y_true[~seen].tolist())),
        "per_class": classification_report(y_true[seen], y_pred[seen], labels=labels, output_dict=True, zero_division=0),
        "macro_f1": round(float(f1_score(y_true[seen], y_pred[seen], labels=labels, average="macro", zero_division=0)), 4),
        "confusion": {"labels": labels, "matrix": confusion_matrix(y_true[seen], y_pred[seen], labels=labels).tolist()},
        "rejection": [_reject_stats(th, y_true, y_pred, confidence, seen) for th in REJECT_THRESHOLDS],
    }
    if task != "recognition":
        negative = "good" if task == "form_binary" else "none"
        clean = y_true == negative
        report["false_correction_rate"] = round(float((y_pred[clean] != negative).mean()), 4) if clean.any() else None
        report["false_correction_definition"] = f"share of '{negative}' samples predicted as a problem"
    return report


def write_report(report: dict, path: Path) -> dict:
    path.write_text(json.dumps(report, indent=2))
    _print(report)
    print(f"wrote {path}")
    return report


def _breakdown(windows, y_true, y_pred, labels, key) -> dict:
    from sklearn.metrics import f1_score
    groups = defaultdict(list)
    for i, w in enumerate(windows):
        if w.label in labels:
            groups[key(w)].append(i)
    return {g: {"windows": len(ix), "macro_f1": round(float(f1_score(y_true[ix], y_pred[ix], labels=labels,
                                                                       average="macro", zero_division=0)), 4)}
            for g, ix in sorted(groups.items())}


def _video_vote(windows, y_pred) -> float:
    votes, truth = defaultdict(Counter), {}
    for w, p in zip(windows, y_pred):
        votes[w.row.video_id][p] += 1
        truth[w.row.video_id] = w.label
    return round(float(np.mean([votes[v].most_common(1)[0][0] == truth[v] for v in votes])), 4)


def _reject_stats(threshold, y_true, y_pred, confidence, seen) -> dict:
    accepted = confidence >= threshold
    known = accepted & seen
    return {"threshold": threshold,
            "coverage_of_known": round(float(known.sum() / seen.sum()), 4) if seen.any() else None,
            "accuracy_on_accepted_known": round(float((y_true[known] == y_pred[known]).mean()), 4) if known.any() else None,
            "unseen_accepted": round(float((accepted & ~seen).sum() / (~seen).sum()), 4) if (~seen).any() else None}


def _print(r) -> None:
    print(f"{r['artifact']} on {r['split']}: macro-F1 {r['macro_f1']}  support {r['support']}  unseen {r['unseen_labels']}")
    print("confusion (rows=true, cols=pred)", r["confusion"]["labels"])
    for label, row in zip(r["confusion"]["labels"], r["confusion"]["matrix"]):
        print(f"  {label:>20} {row}")
    for key in ("by_camera_view", "by_dataset"):
        if key in r:
            print(key, r[key])
    for s in r["rejection"]:
        print("  reject", s)
    if "false_correction_rate" in r:
        print("false correction rate", r["false_correction_rate"])
