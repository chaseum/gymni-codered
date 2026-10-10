from pathlib import Path

import numpy as np

from fitness_ml.training.dataset import make_split, window_bounds
from fitness_ml.training.manifest import Row, multiview, mydeadlift


def touch(root: Path, rel: str, size: int = 10) -> None:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(b"x" * size)


def test_mydeadlift_filenames_map_to_participant_and_labels(tmp_path):
    for name in ("GB_S01_R01.mp4", "PB_S04_R02.mp4", "LLK_S07_R03.MP4", "notes.mp4"):
        touch(tmp_path, f"videos/{name}")
    rows, skipped = mydeadlift(tmp_path)
    got = {(r.participant_id, r.form_label, r.issue_label) for r in rows}
    assert got == {("mydeadlift-S01", "good", "none"), ("mydeadlift-S04", "bad", "rounded_back"),
                   ("mydeadlift-S07", "bad", "knees_past_toes")}
    assert len(skipped) == 1 and skipped[0].endswith("notes.mp4")


def test_multiview_parses_folders_dedupes_layouts_and_side_bend_is_not_side_view(tmp_path):
    touch(tmp_path, "Dataset Subject-wise/Subject 03/Standing Dumbbell Side Bend/Good/Front/a.mp4", 11)
    touch(tmp_path, "Dataset Exercise-wise/Standing Dumbbell Side Bend/Good/Front/Subject 03/a.mp4", 11)
    touch(tmp_path, "Dataset Subject-wise/Subject 03/Alternating Dumbbell Bicep Curl/Bad/Side/b.mp4", 12)
    touch(tmp_path, "Dataset Subject-wise/Subject 03/Mystery/Good/Front/c.mp4", 13)
    rows, skipped = multiview(tmp_path)
    got = sorted((r.exercise, r.variation, r.camera_view, r.form_label, r.participant_id) for r in rows)
    assert got == [("curl", "standing_dumbbell_alternating", "side", "bad", "multiview-03"),
                   ("other", "standing_dumbbell_side_bend", "front", "good", "multiview-03")]
    assert len(skipped) == 1 and "c.mp4" in skipped[0]


def row(dataset, person):
    return Row(f"{dataset}:{person}", "x.mp4", dataset, person, "side", "deadlift", "v")


def test_split_is_participant_disjoint_per_dataset_and_honours_pinned_test(tmp_path):
    manifest = tmp_path / "m.csv"
    manifest.write_text("x")
    rows = [row("mydeadlift", f"mydeadlift-S0{i}") for i in range(1, 8)] + [row("multiview", f"mv-{i}") for i in range(26)]
    split = make_split(rows, manifest, 13, 0.2, 0.15, ["mydeadlift-S04", "mydeadlift-S07"])
    sets = [set(split[k]) for k in ("train", "val", "test")]
    assert not (sets[0] & sets[1] or sets[0] & sets[2] or sets[1] & sets[2])
    assert {"mydeadlift-S04", "mydeadlift-S07"} <= sets[2]
    assert sum(len(s) for s in sets) == 33
    assert any(p.startswith("mv-") for p in sets[2])


def test_window_bounds_short_clip_is_one_window_long_clip_strides():
    assert window_bounds(np.arange(0, 1500, 33.0), 2000, 500) == [(0, 46)]
    bounds = window_bounds(np.arange(0, 5000, 50.0), 2000, 500)
    assert len(bounds) == 6 and bounds[0] == (0, 41)
