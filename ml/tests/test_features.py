import math

import numpy as np

from fitness_ml.features import FEATURE_NAMES, aggregate, angle, frame_features, view_of
from fitness_ml.sources import recorded_timestamp
from conftest import make_pose


def test_angle_of_right_angle_is_90():
    assert math.isclose(angle(np.array([1.0, 0]), np.array([0.0, 0]), np.array([0, 1.0])), 90)


def test_degenerate_angle_is_nan_not_crash():
    assert math.isnan(angle(np.zeros(2), np.zeros(2), np.ones(2)))


def test_elbow_angle_matches_constructed_pose_in_2d_and_3d_despite_non_square_frame():
    f = frame_features(make_pose(elbow_deg=90, width=1280, height=720))
    assert abs(f["right_elbow_angle_deg"] - 90) < 0.5
    assert abs(f["right_elbow_angle_3d_deg"] - 90) < 0.5


def test_missing_pose_gives_all_nan_with_full_schema():
    f = frame_features(None)
    assert list(f) == FEATURE_NAMES and all(math.isnan(v) for v in f.values())


def test_front_facing_synthetic_pose_reads_as_front_view():
    assert view_of(frame_features(make_pose()), 0.30, 0.55) == "front"


def test_aggregate_shape_and_nan_for_untracked_columns():
    m = np.full((5, len(FEATURE_NAMES)), np.nan)
    m[:, 0] = [10, 20, 30, 40, 50]
    v = aggregate(m, np.arange(5) * 100.0)
    assert v.shape == (6 * len(FEATURE_NAMES),)
    assert v[0] == 30 and math.isnan(v[1])
    assert math.isclose(v[5 * len(FEATURE_NAMES)], 100.0)  # speed: 10 deg per 100 ms


def test_recorded_timestamp_prefers_pts_and_never_goes_backwards():
    assert recorded_timestamp(533.3, 16, 30, 500) == 533.3
    assert recorded_timestamp(0.0, 16, 30, 500) == 533.3333333333334  # broken PTS -> nominal frame time
    assert recorded_timestamp(400.0, 3, 30, 500) == 501               # strictly increasing
