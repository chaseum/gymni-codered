"""GRU pipeline: temperature scaling, artifact round-trip, and a tiny end-to-end sweep on synthetic poses."""
import csv
import json

import numpy as np
import pytest

torch = pytest.importorskip("torch")

from conftest import make_pose  # noqa: E402
from fitness_ml.artifacts import Artifact, GRUParams, build_gru, fit_temperature  # noqa: E402
from fitness_ml.features import FEATURE_NAMES, frame_features, to_matrix  # noqa: E402
from fitness_ml.training.dataset import make_split, sha256  # noqa: E402
from fitness_ml.training.extract import cache_file  # noqa: E402
from fitness_ml.training.manifest import Row, write  # noqa: E402
from fitness_ml.training.sweep import sweep  # noqa: E402


def test_temperature_undoes_overconfidence():
    rng = np.random.default_rng(0)
    labels = rng.integers(0, 3, 4000)
    calibrated = rng.normal(size=(4000, 3)) + 2.0 * np.eye(3)[labels]   # sampled so T=1 is right
    noisy = np.array([rng.choice(3, p=np.exp(z) / np.exp(z).sum()) for z in calibrated])
    assert fit_temperature(5 * calibrated, noisy) == pytest.approx(5, rel=0.2)


def save_gru(tmp_path, meta_extra, params=None):
    params = params or GRUParams(hidden=8, layers=2, dropout=0.1, steps=12)
    torch.save(build_gru(3, params).state_dict(), tmp_path / "model.pt")
    meta = {"model": "gru", "model_version": "t", "labels": ["a", "b", "c"], "feature_names": FEATURE_NAMES,
            "norm_mean": [0.0] * len(FEATURE_NAMES), "norm_std": [1.0] * len(FEATURE_NAMES), **meta_extra}
    (tmp_path / "metadata.json").write_text(json.dumps(meta))
    return Artifact(tmp_path)


def test_gru_artifact_rebuilds_from_metadata_and_applies_temperature(tmp_path):
    params = GRUParams(hidden=8, layers=2, dropout=0.1, steps=12, mask=True, velocity=True, bidirectional=True,
                       attention=True)
    matrix = to_matrix([frame_features(make_pose(elbow_deg=a)) for a in range(170, 50, -10)])
    ts = np.arange(len(matrix)) * 100.0
    cold = save_gru(tmp_path, {"gru": params.as_meta(), "temperature": 1.0}, params).predict_proba(matrix, ts)
    hot = save_gru(tmp_path, {"gru": params.as_meta(), "temperature": 50.0}, params).predict_proba(matrix, ts)
    assert cold.sum() == pytest.approx(1) and hot.max() <= cold.max() + 1e-6


def test_old_gru_metadata_without_params_still_loads(tmp_path):
    artifact = save_gru(tmp_path, {"hidden": 8, "steps": 12}, GRUParams(hidden=8, steps=12))
    assert artifact.predict_proba(np.zeros((5, len(FEATURE_NAMES))), np.arange(5) * 100.0).shape == (3,)


def synthetic_dataset(root):
    """6 people x 2 exercises x 2 clips: curl = elbow cycles, squat = knee cycles."""
    rows, cache = [], root / "cache"
    cache.mkdir()
    for person in range(6):
        for exercise, joint in (("curl", "elbow_deg"), ("squat", "knee_deg")):
            for clip in range(2):
                angles = 110 + 55 * np.cos(np.linspace(0, 6 * np.pi, 90) + person + clip)
                poses = [make_pose(**{joint: a}) for a in angles]
                row = Row(f"syn:{person}:{exercise}:{clip}", "x.mp4", "syn", f"p{person}", "front", exercise, "v")
                np.savez(cache_file(cache, row.video_id), video_id=row.video_id, ts=np.arange(90) * 50.0,
                         image=np.array([p.image for p in poses]), world=np.array([p.world for p in poses]),
                         width=640, height=480, every=1)
                rows.append(row)
    manifest, split = root / "manifest.csv", root / "splits.json"
    write(manifest, rows)
    split.write_text(json.dumps(make_split(rows, manifest, 1, 0.2, 0.2)))
    return manifest, cache, split


def test_sweep_keeps_the_validation_winner_archives_the_rest_and_calibrates(tmp_path):
    manifest, cache, split = synthetic_dataset(tmp_path)
    models = tmp_path / "models"
    grid = {"window_ms": [2000], "hidden": [4, 8], "layers": [1], "dropout": [0.0], "lr": [0.01], "batch": [32],
            "steps": [12], "augment": [True], "mask": [True], "velocity": [True], "bidirectional": [True],
            "attention": [True]}
    winner = sweep(manifest, cache, split, "recognition", None, models, grid, 1, "cpu", epochs=3, patience=2)
    kept = [d for d in models.iterdir() if (d / "metadata.json").exists()]
    assert kept == [winner]
    board = list(csv.reader(open(next((models / "archive" / "sweeps").glob("*/leaderboard.csv")))))
    assert len(board) == 3 and board[1][2] == winner.name
    meta = json.loads((winner / "metadata.json").read_text())
    assert "reject_below" in meta and meta["temperature"] > 0 and (winner / "metrics_val.json").exists()


def test_form_sweep_trains_on_single_reps_found_by_the_live_rep_counter(tmp_path, capsys):
    manifest, cache, split = synthetic_dataset(tmp_path)
    rows = json.loads(split.read_text())
    grid = {"window_ms": [2000, 3000], "hidden": [4], "layers": [1], "dropout": [0.0], "lr": [0.01], "batch": [16],
            "steps": [12], "augment": [False], "mask": [True], "velocity": [False], "bidirectional": [False],
            "attention": [False]}
    # synthetic curls are labelled good/bad by participant parity so the form task has two classes
    from fitness_ml.training.manifest import read
    labelled = [r for r in read(manifest)]
    for r in labelled:
        r.form_label = "good" if int(r.participant_id[1:]) % 2 else "bad"
    write(manifest, labelled)
    rows["manifest_sha256"] = sha256(manifest)
    split.write_text(json.dumps(rows))
    winner = sweep(manifest, cache, split, "form_binary", "curl", tmp_path / "models", grid, 1, "cpu", 2, 1)
    meta = json.loads((winner / "metadata.json").read_text())
    assert meta["segment"] == "rep" and meta["window_ms"] == 2000  # rep cut: window grid collapses to one value
    out = capsys.readouterr().out
    assert "videos cut into reps" in out and "rep segmentation: 0/" not in out
