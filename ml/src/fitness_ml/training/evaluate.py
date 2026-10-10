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
    from sklearn.metrics import classification_report, confusion_matrix, f1_score

    art = Artifact(artifact_dir)
    meta = art.meta
    windows = windows_for(read(manifest), set(meta["split"][split_name]), cache, meta["task"], meta["exercise"],
                          meta["window_ms"], meta["stride_ms"])
    if not windows:
        raise ValueError(f"no {split_name} windows")
    proba = np.array([art.predict_proba(w.matrix, w.ts) for w in windows])
    y_true = np.array([w.label for w in windows])
    y_pred = np.array(art.labels)[proba.argmax(1)]
    confidence = proba.max(1)
    seen = np.isin(y_true, art.labels)

    report = {
        "artifact": meta["model_version"], "split": split_name, "participants": meta["split"][split_name],
        "windows": len(windows), "videos": len({w.row.video_id for w in windows}),
        "support": dict(Counter(y_true.tolist())),
        "unseen_labels": sorted(set(y_true[~seen].tolist())),
        "per_class": classification_report(y_true, y_pred, labels=art.labels, output_dict=True, zero_division=0),
        "macro_f1": round(float(f1_score(y_true, y_pred, labels=art.labels, average="macro", zero_division=0)), 4),
        "confusion": {"labels": art.labels,
                      "matrix": confusion_matrix(y_true[seen], y_pred[seen], labels=art.labels).tolist()},
        "by_camera_view": _breakdown(windows, y_true, y_pred, art.labels, lambda w: w.row.camera_view),
        "by_dataset": _breakdown(windows, y_true, y_pred, art.labels, lambda w: w.row.dataset),
        "by_video_majority_accuracy": _video_vote(windows, y_pred),
        "rejection": [_reject_stats(th, y_true, y_pred, confidence, meta["task"]) for th in REJECT_THRESHOLDS],
    }
    if meta["task"] != "recognition":
        negative = "good" if meta["task"] == "form_binary" else "none"
        clean = y_true == negative
        report["false_correction_rate"] = (round(float((y_pred[clean] != negative).mean()), 4) if clean.any() else None)
        report["false_correction_definition"] = f"share of '{negative}' windows predicted as a problem"
    out = Path(artifact_dir) / f"metrics_{split_name}.json"
    out.write_text(json.dumps(report, indent=2))
    _print(report)
    print(f"wrote {out}")
    return report


def _breakdown(windows, y_true, y_pred, labels, key) -> dict:
    from sklearn.metrics import f1_score
    groups = defaultdict(list)
    for i, w in enumerate(windows):
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


def _reject_stats(threshold, y_true, y_pred, confidence, task) -> dict:
    accepted = confidence >= threshold
    stats = {"threshold": threshold, "coverage": round(float(accepted.mean()), 4),
             "accuracy_on_accepted": round(float((y_true[accepted] == y_pred[accepted]).mean()), 4) if accepted.any() else None}
    if task == "recognition":
        other = y_true == "other"
        supported_pred = np.isin(y_pred, ["curl", "squat", "deadlift"])
        stats["other_accepted_as_supported"] = (round(float((accepted & other & supported_pred).sum() / other.sum()), 4)
                                                if other.any() else None)
        stats["supported_rejected"] = (round(float((~accepted & ~other).sum() / (~other).sum()), 4)
                                       if (~other).any() else None)
    return stats


def _print(r) -> None:
    print(f"{r['artifact']} on {r['split']} ({r['windows']} windows, {r['videos']} videos, people {r['participants']})")
    print(f"macro-F1 {r['macro_f1']}  support {r['support']}  unseen labels {r['unseen_labels']}")
    print("confusion (rows=true, cols=pred)", r["confusion"]["labels"])
    for label, row in zip(r["confusion"]["labels"], r["confusion"]["matrix"]):
        print(f"  {label:>16} {row}")
    print("by view", r["by_camera_view"])
    for s in r["rejection"]:
        print("  reject", s)
    if "false_correction_rate" in r:
        print("false correction rate", r["false_correction_rate"])
