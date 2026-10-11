"""GRU hyper-parameter sweep: train every grid combination, rank by VALIDATION macro-F1, keep the winner in
ml/models (so the live app loads it), archive the rest with a leaderboard, and calibrate the winner on validation.
The test split is never looked at here; run `fitness-train evaluate --artifact <winner>` once at the end."""
import csv
import itertools
import json
import shutil
import time
from pathlib import Path

from ..artifacts import GRUParams
from .evaluate import calibrate_reject, evaluate
from .train import train

FORM_TASKS = [("form_issue", "deadlift")] + [("form_binary", ex) for ex in
                                              ("curl", "squat", "side_bend", "row", "push_up", "shoulder_press",
                                               "triceps_extension")]
ALL_TASKS = [("recognition", None)] + FORM_TASKS


def sweep(manifest: Path, cache: Path, split: Path, task: str, exercise: str | None, out_root: Path,
          grid: dict[str, list], seed: int, device: str, epochs: int, patience: int, form_segment: str = "rep") -> Path:
    """`grid` maps GRUParams fields (and "window_ms") to candidate values. Form tasks are cut per rep by default
    (what they see live); window length then only matters for fallback videos, so only its first value is tried."""
    segment = "window" if task == "recognition" else form_segment
    if segment == "rep":
        grid = {**grid, "window_ms": grid["window_ms"][:1]}
    configs = [dict(zip(grid, values)) for values in itertools.product(*grid.values())]
    print(f"### sweep {task} {exercise or ''}: {len(configs)} configs", flush=True)
    results = []
    for n, config in enumerate(configs, 1):
        params = {k: v for k, v in config.items() if k != "window_ms"}
        print(f"--- [{n}/{len(configs)}] {config}", flush=True)
        out = train(manifest, cache, split, task, exercise, "gru", out_root, config["window_ms"],
                    stride_for(config["window_ms"]), seed, device, epochs, patience, gru=GRUParams(**params),
                    segment=segment)
        meta = json.loads((out / "metadata.json").read_text())
        results.append((meta["best_val_macro_f1"], out, config))
    results.sort(key=lambda r: r[0], reverse=True)
    winner = _archive_losers(results, out_root, task, exercise)
    evaluate(winner, manifest, cache, "val")
    if task == "recognition":
        calibrate_reject(winner, target_accuracy=0.97)
    print(f"### winner {winner.name} (val macro-F1 {results[0][0]:.3f})", flush=True)
    return winner


def stride_for(window_ms: float) -> float:
    """Stride = quarter window: enough overlap for training variety without near-duplicate windows."""
    return window_ms / 4


def _archive_losers(results, out_root: Path, task: str, exercise: str | None) -> Path:
    folder = out_root / "archive" / "sweeps" / f"{task}-{exercise or 'all'}-{time.strftime('%Y%m%d-%H%M%S')}"
    folder.mkdir(parents=True, exist_ok=True)
    with open(folder / "leaderboard.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["rank", "val_macro_f1", "model", *results[0][2]])
        for rank, (score, out, config) in enumerate(results, 1):
            writer.writerow([rank, score, out.name, *config.values()])
    for _, out, _ in results[1:]:
        shutil.move(str(out), folder / out.name)
    print(f"leaderboard: {folder / 'leaderboard.csv'}", flush=True)
    return results[0][1]
