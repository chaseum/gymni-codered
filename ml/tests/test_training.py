from pathlib import Path

import numpy as np

from fitness_ml.training.dataset import make_split, window_bounds
from fitness_ml.training.deadlift_angles import load as load_angles
from fitness_ml.training.manifest import Row, multiview


def touch(root: Path, rel: str, size: int = 10) -> None:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(b"x" * size)


def test_mydeadlift_angle_csv_uses_semicolons_decimal_commas_and_filename_labels(tmp_path):
    csv = tmp_path / "Extracted_keypoints.csv"
    csv.write_text("Split;Label;Video;Frame;Sudut_Lutut;Sudut_Pinggul;Sudut_Punggung_Vertikal\n"
                   "training;gerakan_benar;GB_S01_R01.mp4;2;113,47;61,82;68,06\n"
                   "training;gerakan_benar;GB_S01_R01.mp4;1;110,34;61,39;68,72\n"
                   "testing;punggung_bungkuk;PB_S04_R02.mp4;1;100,5;55;70,25\n")
    clips = load_angles(csv)
    assert [(c.subject, c.split, c.label) for c in clips] == [("mydeadlift-S01", "training", "none"),
                                                              ("mydeadlift-S04", "testing", "rounded_back")]
    assert clips[0].angles[0].tolist() == [110.34, 61.39, 68.72]  # frames re-sorted
    assert clips[0].ts.tolist() == [0.0, 1000 / 30]


def test_multiview_uses_documented_names_and_dedupes_layouts(tmp_path):
    touch(tmp_path, "Dataset Subject-wise/subject_003/abs/good/side/subject_003_abs_good_side.mp4")
    touch(tmp_path, "Dataset Exercise-wise/abs/good/side/subject_003_abs_good_side.mp4")
    touch(tmp_path, "Dataset Subject-wise/subject_003/bicep_curl/bad/front/subject_003_bicep_curl_bad_front.mp4")
    touch(tmp_path, "Dataset Subject-wise/subject_003/misc/clip.mp4")
    rows, skipped = multiview(tmp_path)
    got = sorted((r.exercise, r.variation, r.camera_view, r.form_label, r.participant_id) for r in rows)
    assert got == [("curl", "standing_dumbbell_alternating", "front", "bad", "multiview-003"),
                   ("side_bend", "standing_dumbbell", "side", "good", "multiview-003")]
    assert len(skipped) == 1 and skipped[0].endswith("clip.mp4")


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
