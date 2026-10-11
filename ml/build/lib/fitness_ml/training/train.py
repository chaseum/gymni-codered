"""Train one artifact: recognition (curl/squat/deadlift/other) or per-exercise form (binary or labelled issue).

Baselines: RandomForest / k-NN on aggregated window features (sklearn pipeline with imputation + scaling).
Comparator: small GRU on resampled window sequences. Both read the same windows of the same split.
"""
import json
import platform
import subprocess
import time
from collections import Counter
from importlib import metadata
from pathlib import Path

import numpy as np

from ..config import REPO
from ..features import AGG_NAMES, FEATURE_NAMES, aggregate, resample
from .dataset import Window, load_split, sha256, windows_for
from .manifest import read

GRU_STEPS, GRU_HIDDEN = 48, 64


def train(manifest: Path, cache: Path, split_path: Path, task: str, exercise: str | None, model: str,
          out_root: Path, window_ms: float, stride_ms: float, seed: int, device: str = "auto",
          epochs: int = 100, patience: int = 10, exclude_labels: tuple[str, ...] = ()) -> Path:
    """`exclude_labels` keeps those classes out of training only; evaluate still sees them in test, which
    measures whether the model rejects movement it never learned instead of forcing a known label."""
    if task != "recognition" and not exercise:
        raise ValueError("form tasks need --exercise")
    rows, split = read(manifest), load_split(split_path)
    if split["manifest_sha256"] != sha256(manifest):
        raise ValueError("manifest changed since the split was made; re-run `fitness-train split`")
    train_w = [w for w in windows_for(rows, set(split["train"]), cache, task, exercise, window_ms, stride_ms)
               if w.label not in exclude_labels]
    val_w = [w for w in windows_for(rows, set(split["val"]), cache, task, exercise, window_ms, stride_ms)
             if w.label not in exclude_labels]
    if not train_w:
        raise ValueError("no training windows: check task/exercise labels in the manifest")
    labels = sorted({w.label for w in train_w})
    if task == "recognition" and not exclude_labels:
        print("note: no class held out, so `evaluate` can't measure rejection of unseen movement "
              "(train a second model with --exclude-labels push_up to measure it)")

    meta = _metadata(manifest, split_path, split, task, exercise, model, labels, window_ms, stride_ms, seed, train_w, val_w)
    out = Path(out_root) / meta["model_version"]
    out.mkdir(parents=True, exist_ok=True)
    if model == "gru":
        meta |= _train_gru(train_w, val_w, labels, out, seed, device, epochs, patience)
    else:
        _train_sklearn(train_w, model, seed, out)
    meta["excluded_labels"] = list(exclude_labels)
    (out / "metadata.json").write_text(json.dumps(meta, indent=2))
    print(f"saved {out}")
    return out


def _train_sklearn(train_w: list[Window], model: str, seed: int, out: Path) -> None:
    import joblib
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.impute import SimpleImputer
    from sklearn.neighbors import KNeighborsClassifier
    from sklearn.pipeline import make_pipeline
    from sklearn.preprocessing import StandardScaler

    x = np.array([aggregate(w.matrix, w.ts) for w in train_w])
    y = np.array([w.label for w in train_w])
    estimator = (RandomForestClassifier(n_estimators=300, class_weight="balanced", random_state=seed, n_jobs=-1)
                 if model == "rf" else KNeighborsClassifier(n_neighbors=7, weights="distance"))
    pipe = make_pipeline(SimpleImputer(strategy="median", keep_empty_features=True), StandardScaler(), estimator)
    pipe.fit(x, y)
    joblib.dump(pipe, out / "model.joblib")


def _train_gru(train_w, val_w, labels, out, seed, device, epochs, patience) -> dict:
    import torch
    from sklearn.metrics import f1_score

    from ..artifacts import build_gru

    torch.manual_seed(seed)
    np.random.seed(seed)
    if device == "auto":  # NVIDIA (e.g. Vultr) > Apple-silicon GPU > CPU
        device = "cuda" if torch.cuda.is_available() else "mps" if torch.backends.mps.is_available() else "cpu"
    dev = torch.device(device)
    index = {label: i for i, label in enumerate(labels)}

    def tensors(ws):
        seqs = np.array([resample(w.matrix, w.ts, GRU_STEPS) for w in ws])
        return seqs, np.array([index.get(w.label, -1) for w in ws])

    x_train, y_train = tensors(train_w)
    mean = x_train.reshape(-1, x_train.shape[-1]).mean(0)
    std = x_train.reshape(-1, x_train.shape[-1]).std(0)
    std[std < 1e-6] = 1.0
    x_val, y_val = tensors(val_w) if val_w else (x_train, y_train)  # no val people -> early-stop on train (logged)
    keep = y_val >= 0  # val windows of a class unseen in training can't be scored
    def normalized(a):
        return torch.tensor((a - mean) / std, dtype=torch.float32, device=dev)

    xt, yt, xv = normalized(x_train), torch.tensor(y_train, device=dev), normalized(x_val[keep])

    net = build_gru(len(FEATURE_NAMES), len(labels), GRU_HIDDEN).to(dev)
    counts = np.bincount(y_train, minlength=len(labels))
    loss_fn = torch.nn.CrossEntropyLoss(weight=torch.tensor(len(y_train) / (len(labels) * np.maximum(counts, 1)),
                                                            dtype=torch.float32, device=dev))
    opt = torch.optim.Adam(net.parameters(), lr=1e-3)
    best, best_state, stale, history = -1.0, None, 0, []
    gen = torch.Generator(device="cpu").manual_seed(seed)
    for epoch in range(epochs):
        net.train()
        for batch in torch.randperm(len(xt), generator=gen).split(64):
            opt.zero_grad()
            loss_fn(net(xt[batch]), yt[batch]).backward()
            opt.step()
        net.eval()
        with torch.no_grad():
            pred = net(xv).argmax(-1).cpu().numpy()
        f1 = float(f1_score(y_val[keep], pred, average="macro"))
        history.append(round(f1, 4))
        print(f"  epoch {epoch + 1:3d}  val macro-F1 {f1:.3f}" + ("  (best)" if f1 > best else ""), flush=True)
        if f1 > best:
            best, stale = f1, 0
            best_state = {k: v.detach().cpu().clone() for k, v in net.state_dict().items()}
        else:
            stale += 1
            if stale >= patience:
                break
    torch.save(best_state, out / "model.pt")
    return {"steps": GRU_STEPS, "hidden": GRU_HIDDEN, "norm_mean": mean.tolist(), "norm_std": std.tolist(),
            "device": str(dev), "epochs_run": len(history), "val_macro_f1_history": history,
            "early_stop_on": "val" if val_w else "train (no val participants)"}


def _metadata(manifest, split_path, split, task, exercise, model, labels, window_ms, stride_ms, seed, train_w, val_w) -> dict:
    revision = git("rev-parse", "HEAD")
    dirty = bool(git("status", "--porcelain", "--", "ml/src"))
    stamp = time.strftime("%Y%m%d-%H%M%S")
    return {
        "model_version": f"{task}-{exercise or 'all'}-{model}-{stamp}-{(revision or 'norev')[:7]}",
        "task": task, "exercise": exercise, "model": model, "labels": labels,
        "feature_names": FEATURE_NAMES, "aggregate_names": AGG_NAMES if model != "gru" else None,
        "window_ms": window_ms, "stride_ms": stride_ms, "seed": seed,
        "split": {k: split[k] for k in ("train", "val", "test", "seed", "pinned_test")}, "split_file": str(split_path),
        "manifest": str(manifest), "manifest_sha256": split["manifest_sha256"],
        "train_windows": dict(Counter(w.label for w in train_w)), "val_windows": dict(Counter(w.label for w in val_w)),
        "code_revision": revision, "code_dirty": dirty, "python": platform.python_version(),
        "packages": {p: package_version(p) for p in ("numpy", "scikit-learn", "mediapipe", "torch")},
        "trained_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    }


def git(*args) -> str | None:
    try:
        return subprocess.run(["git", *args], cwd=REPO, capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def package_version(package: str) -> str | None:
    try:
        return metadata.version(package)
    except metadata.PackageNotFoundError:
        return None
