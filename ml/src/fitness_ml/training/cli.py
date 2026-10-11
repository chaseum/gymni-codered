"""fitness-train: ingest -> extract -> split -> train -> evaluate. Same commands on a laptop or a GPU box.

    fitness-train ingest multiview --root ml/data/raw/multiview --out ml/data/manifest.csv
    fitness-train extract
    fitness-train split
    fitness-train train --task recognition --model rf
    fitness-train train --task form_binary --exercise push_up --model rf
    fitness-train evaluate --artifact ml/models/<model_version>
    fitness-train deadlift-angles --csv ml/data/raw/mydeadlift/Extracted_keypoints.csv
"""
import argparse
import json
import os
import sys
from pathlib import Path

from ..config import EXERCISES, Config

DATA = Config().models_dir.parent / "data"
DEFAULTS = {"manifest": DATA / "manifest.csv", "cache": DATA / "cache", "split": DATA / "splits.json"}


def main() -> int:
    args = _parser().parse_args()
    if args.cmd == "ingest":
        return _ingest(args)
    if args.cmd == "merge":
        from .manifest import read, summary, write
        rows = [r for p in args.manifests for r in read(Path(p))]
        if len({r.video_id for r in rows}) != len(rows):
            raise SystemExit("duplicate video_id across manifests")
        write(Path(args.out), rows)
        print(summary(rows))
    elif args.cmd == "add-clip":
        from .manifest import add_clips, summary
        rows = add_clips(Path(args.manifest), [Path(v) for v in args.videos], args.exercise, args.participant,
                         args.view, args.variation or "", args.form or "")
        print(summary(rows))
        print(f"-> {args.manifest}. Retrain: ingest multiview -> merge -> extract -> split -> train (ml/training/README.md)")
    elif args.cmd == "extract":
        from ..pose import VARIANTS, model_path
        from .extract import extract
        from .manifest import read
        model = model_path(Config().models_dir, args.pose_model) if args.pose_model in VARIANTS else Path(args.pose_model)
        rows = read(Path(args.manifest))
        extract(rows[: args.limit] if args.limit else rows, Path(args.cache), model, args.every, args.force, args.workers)
    elif args.cmd == "split":
        from .dataset import make_split
        from .manifest import read
        pinned = [p for p in (args.test_participants or "").split(",") if p]
        split = make_split(read(Path(args.manifest)), Path(args.manifest), args.seed, args.test_frac, args.val_frac, pinned)
        Path(args.out).write_text(json.dumps(split, indent=2))
        print({k: len(split[k]) for k in ("train", "val", "test")}, "->", args.out)
    elif args.cmd == "train":
        from .train import train
        train(Path(args.manifest), Path(args.cache), Path(args.split), args.task, args.exercise, args.model,
              Path(args.out_dir), args.window_ms, args.stride_ms, args.seed, args.device, args.epochs, args.patience,
              tuple(x for x in (args.exclude_labels or "").split(",") if x))
    elif args.cmd == "deadlift-angles":
        from .deadlift_angles import train_deadlift_angles
        train_deadlift_angles(Path(args.csv), Path(args.out_dir), args.model, args.seed, args.calibration_reps,
                              args.max_false_correction)
    elif args.cmd == "sweep":
        from .sweep import ALL_TASKS, sweep
        grid = {"window_ms": args.window_ms, "hidden": args.hidden, "layers": args.layers, "dropout": args.dropout,
                "lr": args.lr, "batch": args.batch, "steps": args.steps}
        tasks = ALL_TASKS if args.task == "all" else [(args.task, args.exercise)]
        for task, exercise in tasks:
            sweep(Path(args.manifest), Path(args.cache), Path(args.split), task, exercise, Path(args.out_dir), grid,
                  args.seed, args.device, args.epochs, args.patience)
    elif args.cmd == "calibrate-reject":
        from .evaluate import calibrate_reject
        calibrate_reject(Path(args.artifact), args.target_accuracy)
    elif args.cmd == "export":
        from .export import export
        print(export(Config().models_dir, Path(args.out_dir)))
    elif args.cmd == "evaluate":
        from .evaluate import evaluate
        evaluate(Path(args.artifact), Path(args.manifest), Path(args.cache), args.split_name)
    return 0


def _ingest(args) -> int:
    from .manifest import ADAPTERS, summary, write
    rows, skipped = ADAPTERS[args.dataset](Path(args.root))
    write(Path(args.out), rows)
    print(summary(rows))
    if skipped:
        print(f"\nSKIPPED {len(skipped)} files whose labels could not be parsed:", *skipped[:25], sep="\n  ")
        if not args.allow_skips:
            print("\nFix the adapter or pass --allow-skips once you've confirmed these are not training videos.")
            return 1
    return 0


def _parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="fitness-train", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    ing = sub.add_parser("ingest", help="build a manifest CSV from a dataset folder")
    ing.add_argument("dataset", choices=["multiview", "kaggle_workout", "weggry_deadlift", "csv"],
                     help="csv = your own clips (columns in manifest.Row)")
    ing.add_argument("--root", required=True, help="dataset folder (or your CSV for 'csv')")
    ing.add_argument("--out", required=True)
    ing.add_argument("--allow-skips", action="store_true")

    add = sub.add_parser("add-clip", help="register your own recordings (from `fitness-ml run --record`) for training")
    add.add_argument("videos", nargs="+")
    add.add_argument("--exercise", required=True, choices=[*EXERCISES, "other"])
    add.add_argument("--participant", required=True, help="who is in the clip, e.g. chase (keeps splits per person)")
    add.add_argument("--view", required=True, choices=["front", "side", "diagonal"])
    add.add_argument("--variation", help="e.g. backpack, broomstick, bodyweight (default: config variation)")
    add.add_argument("--form", choices=["good", "bad"], help="whole-clip form label, if you know it")
    add.add_argument("--manifest", default=str(DATA / "manifest_own.csv"))

    mrg = sub.add_parser("merge", help="concatenate manifests")
    mrg.add_argument("manifests", nargs="+")
    mrg.add_argument("--out", default=str(DEFAULTS["manifest"]))

    ext = sub.add_parser("extract", help="run MediaPipe once per video into the landmark cache")
    ext.add_argument("--manifest", default=str(DEFAULTS["manifest"]))
    ext.add_argument("--cache", default=str(DEFAULTS["cache"]))
    ext.add_argument("--pose-model", default="lite")
    ext.add_argument("--every", type=int, default=1, help="keep every Nth frame")
    ext.add_argument("--limit", type=int, help="first N videos only (smoke test)")
    ext.add_argument("--force", action="store_true")
    ext.add_argument("--workers", type=int, default=max(1, (os.cpu_count() or 2) - 2),
                     help="parallel videos (default: CPU cores - 2)")

    spl = sub.add_parser("split", help="participant-disjoint train/val/test split")
    spl.add_argument("--manifest", default=str(DEFAULTS["manifest"]))
    spl.add_argument("--out", default=str(DEFAULTS["split"]))
    spl.add_argument("--seed", type=int, default=13)
    spl.add_argument("--test-frac", type=float, default=0.15, help="share of PEOPLE held out for test (70/15/15)")
    spl.add_argument("--val-frac", type=float, default=0.15, help="share of PEOPLE held out for validation")
    spl.add_argument("--test-participants", help="comma list pinned to test, e.g. mydeadlift-S04,mydeadlift-S07")

    tr = sub.add_parser("train", help="train one artifact into ml/models/<model_version>/")
    tr.add_argument("--task", choices=["recognition", "form_binary", "form_issue"], required=True)
    tr.add_argument("--exercise", choices=list(EXERCISES), help="required for form tasks")
    tr.add_argument("--exclude-labels", help="comma list kept out of training to measure rejection, e.g. push_up")
    tr.add_argument("--model", choices=["rf", "knn", "gru"], default="rf")
    tr.add_argument("--manifest", default=str(DEFAULTS["manifest"]))
    tr.add_argument("--cache", default=str(DEFAULTS["cache"]))
    tr.add_argument("--split", default=str(DEFAULTS["split"]))
    tr.add_argument("--out-dir", default=str(Config().models_dir))
    tr.add_argument("--window-ms", type=float, default=Config().recognition_window_ms)
    tr.add_argument("--stride-ms", type=float, default=Config().recognition_stride_ms)
    tr.add_argument("--seed", type=int, default=13)
    tr.add_argument("--device", choices=["auto", "cpu", "cuda", "mps"], default="auto", help="GRU only")
    tr.add_argument("--epochs", type=int, default=100, help="GRU only")
    tr.add_argument("--patience", type=int, default=10, help="GRU early stopping")

    dl = sub.add_parser("deadlift-angles", help="deadlift form model from MyDeadlift's angle CSV (train + test)")
    dl.add_argument("--csv", default=str(DATA / "raw" / "mydeadlift" / "Extracted_keypoints.csv"))
    dl.add_argument("--model", choices=["rf", "knn"], default="rf")
    dl.add_argument("--out-dir", default=str(Config().models_dir))
    dl.add_argument("--seed", type=int, default=13)
    dl.add_argument("--calibration-reps", type=int, default=3, help="clean reps judged first (0 = no calibration)")
    dl.add_argument("--max-false-correction", type=float, default=0.10,
                    help="CV budget for flagging clean reps; picks the fault threshold")

    sw = sub.add_parser("sweep", help="GRU grid search ranked on validation; keeps the winner, archives the rest")
    sw.add_argument("--task", choices=["all", "recognition", "form_binary", "form_issue"], default="all",
                    help="all = recognizer + the 8 form models")
    sw.add_argument("--exercise", choices=list(EXERCISES), help="for a single form task")
    for name, kind, default in (("window-ms", float, "2000,3000"), ("hidden", int, "64,128"), ("layers", int, "1,2"),
                                ("dropout", float, "0.2"), ("lr", float, "0.001"), ("batch", int, "128"),
                                ("steps", int, "48")):
        sw.add_argument(f"--{name}", type=lambda text, kind=kind: [kind(v) for v in text.split(",")],
                        default=[kind(v) for v in default.split(",")], help=f"comma list (default {default})")
    sw.add_argument("--manifest", default=str(DEFAULTS["manifest"]))
    sw.add_argument("--cache", default=str(DEFAULTS["cache"]))
    sw.add_argument("--split", default=str(DEFAULTS["split"]))
    sw.add_argument("--out-dir", default=str(Config().models_dir))
    sw.add_argument("--seed", type=int, default=13)
    sw.add_argument("--device", choices=["auto", "cpu", "cuda", "mps"], default="auto")
    sw.add_argument("--epochs", type=int, default=100)
    sw.add_argument("--patience", type=int, default=10)

    cr = sub.add_parser("calibrate-reject", help="set a recognizer's 'unknown' threshold from its validation sweep")
    cr.add_argument("--artifact", required=True)
    cr.add_argument("--target-accuracy", type=float, default=0.97)

    ex = sub.add_parser("export", help="zip the models `fitness-ml run` would load, for another machine (e.g. a Pi)")
    ex.add_argument("--out-dir", default=str(Config().models_dir / "exports"))

    ev = sub.add_parser("evaluate", help="metrics on the artifact's held-out participants")
    ev.add_argument("--artifact", required=True)
    ev.add_argument("--manifest", default=str(DEFAULTS["manifest"]))
    ev.add_argument("--cache", default=str(DEFAULTS["cache"]))
    ev.add_argument("--split-name", choices=["test", "val"], default="test")
    return ap


if __name__ == "__main__":
    sys.exit(main())
