import math

from fitness_ml.config import EXERCISES, RepConfig
from fitness_ml.reps import RepCounter
from conftest import curl_frames

CURL = EXERCISES["curl"].rep


def count(samples, cfg=CURL):
    counter = RepCounter(cfg)
    return [c for t, v in samples if (c := counter.update(v, t))]


def test_each_full_curl_counts_once():
    assert len(count(curl_frames(3))) == 3


def test_jitter_around_both_thresholds_does_not_add_reps():
    samples = [(i * 100.0, v) for i, v in enumerate(
        [165] * 5 + [146, 144, 146, 144] * 3 + [100, 84, 86, 84, 86, 84, 120, 144, 146, 144, 146, 165] + [165] * 5)]
    assert len(count(samples, RepConfig("elbow", "lowered", 145, 85, smoothing=1.0))) == 1


def test_partial_rep_that_never_reaches_turn_is_not_counted():
    assert count(curl_frames(1, high=100)) == []


def test_too_fast_cycle_is_not_counted():
    assert count(curl_frames(1, rep_s=0.3)) == []


def test_odd_frame_rates_count_the_same():
    for fps in (12, 24, 29.97, 59.94):
        assert len(count(curl_frames(2, fps=fps))) == 2, fps


def test_long_tracking_gap_mid_rep_voids_the_rep_short_gap_does_not():
    frames = curl_frames(1)
    mid = len(frames) // 2
    short = [(t, None if mid <= i < mid + 3 else v) for i, (t, v) in enumerate(frames)]   # ~100 ms
    long = [(t, None if mid - 10 <= i < mid + 10 else v) for i, (t, v) in enumerate(frames)]  # ~660 ms
    assert len(count(short)) == 1
    assert count(long) == []


def test_clip_starting_mid_rep_waits_for_start_position():
    frames = curl_frames(2)
    assert len(count(frames[len(frames) // 3:])) == 1


def test_reset_discards_rep_in_progress():
    counter, frames = RepCounter(CURL), curl_frames(1)
    for t, v in frames[: len(frames) // 2]:
        counter.update(v, t)
    counter.reset()
    assert [c for t, v in frames[len(frames) // 2:] if (c := counter.update(v, t))] == []


def test_squat_and_deadlift_directions():
    squat = [(i * 33.0, v) for i, v in enumerate([175] * 10 + list(range(175, 90, -3)) + list(range(90, 176, 3)) + [175] * 10)]
    dead = [(i * 33.0, v) for i, v in enumerate([80] * 10 + list(range(80, 172, 3)) + list(range(172, 79, -3)) + [80] * 10)]
    assert len(count(squat, EXERCISES["squat"].rep)) == 1
    assert len(count(dead, EXERCISES["deadlift"].rep)) == 1
    assert math.isclose(count(squat, RepConfig("knee", "raised", 160, 120, smoothing=1.0))[0].extreme_deg, 91, abs_tol=1)
