"""Integration of features -> reps -> form -> contract Observation, on synthetic poses."""
import json
import sys
from pathlib import Path

import numpy as np

from fitness_ml.analyzer import Analyzer
from fitness_ml.recognition import Recognizer
from conftest import curl_frames, make_pose

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "contracts"))
from validate import errors  # noqa: E402  (contracts/validate.py)


def run(analyzer, frames, **pose_kw):
    return [analyzer.analyze_frame(make_pose(elbow_deg=v, **pose_kw) if v is not None else None, t) for t, v in frames]


def test_live_curls_emit_one_completed_rep_each_and_validate_against_contract():
    results = run(Analyzer("curl", "s-1", "live"), curl_frames(3))
    completed = [r.observation.completed_rep for r in results if r.observation.completed_rep]
    assert len(completed) == 3
    assert [c.rep_index for c in completed] == sorted({c.rep_index for c in completed})
    for r in results[::7] + [r for r in results if r.observation.completed_rep]:
        assert errors("observation", json.loads(json.dumps(r.observation.to_dict()))) == []


def test_partial_flexion_is_a_candidate_issue_but_not_sent_until_reviewed():
    results = run(Analyzer("curl", "s-1", "live"), curl_frames(1, high=68))  # passes the 75° turn, misses 60° flexion
    done = [r for r in results if r.observation.completed_rep]
    assert len(done) == 1
    assert [(a.code, a.status) for a in done[0].candidates] == [("curl.partial_range", "issue")]
    assert done[0].observation.issues == []  # criterion not in config.reviewed yet


def test_occlusion_reports_low_visibility_and_counts_nothing():
    results = run(Analyzer("curl", "s-1", "live"), curl_frames(2), visibility=0.2)
    assert {r.observation.tracking_status for r in results} == {"low_visibility"}
    assert not any(r.observation.completed_rep for r in results)


def test_no_person_is_lost_tracking():
    r = Analyzer("curl", "s-1", "live").analyze_frame(None, 0.0)
    assert r.observation.tracking_status == "lost" and r.observation.phase == "unknown"


def test_source_switch_discards_half_rep_and_rep_index_keeps_rising():
    analyzer, frames = Analyzer("curl", "s-1", "live", rep_index_start=100), curl_frames(1)
    first = [r for r in run(analyzer, curl_frames(1)) if r.observation.completed_rep]
    run(analyzer, frames[: len(frames) // 2])
    analyzer.reset(source="recorded", clip_id="clip")
    after = [r for r in run(analyzer, [(t + 10_000, v) for t, v in curl_frames(1)]) if r.observation.completed_rep]
    assert first[0].observation.completed_rep.rep_index == 101
    assert after[0].observation.completed_rep.rep_index == 102
    assert after[0].observation.source == "recorded" and after[0].observation.time_base == "video_pts"


def test_squat_from_front_view_counts_but_depth_is_unassessable():
    frames = [(i * 33.0, v) for i, v in enumerate([175] * 10 + list(range(175, 90, -3)) + list(range(90, 176, 3)) + [175] * 10)]
    analyzer = Analyzer("squat", "s-1", "recorded")
    results = [analyzer.analyze_frame(make_pose(knee_deg=v), t) for t, v in frames]
    done = [r for r in results if r.observation.completed_rep]
    assert len(done) == 1
    assert done[0].candidates[0].status == "unassessable" and done[0].candidates[0].evidence["view"] == "front"


class LowConfidenceModel:
    """Stands in for a trained artifact that is unsure: the analyzer must report 'unknown', not the plan."""
    labels, version, meta = ["curl", "other", "squat"], "fake-1", {"task": "recognition"}

    def predict_proba(self, matrix, ts):
        return np.array([0.4, 0.35, 0.25])


def test_unsure_recognizer_reports_unknown_exercise_with_confidence():
    analyzer = Analyzer("curl", "s-1", "live", recognizer=Recognizer(LowConfidenceModel(), 1000, 500, 0.6))
    obs = run(analyzer, curl_frames(1))[-1].observation
    assert obs.exercise == "unknown" and obs.exercise_confidence == 0.4
    assert obs.inference_provenance == "trained_model" and obs.model_version == "fake-1"
    assert errors("observation", json.loads(json.dumps(obs.to_dict()))) == []


def test_single_arm_set_counts_even_when_the_still_arm_is_more_visible():
    from fitness_ml.pose import INDEX
    analyzer, results = Analyzer("curl", "s-1", "live"), []
    for t, v in curl_frames(3):
        pose = make_pose(elbow_deg=165)            # both arms hanging...
        moving = make_pose(elbow_deg=v)
        for j in ("shoulder", "elbow", "wrist"):   # ...except the right arm curls
            pose.image[INDEX[f"right_{j}"]] = moving.image[INDEX[f"right_{j}"]]
        pose.image[INDEX["right_wrist"], 3] = 0.7  # and is less visible than the still left arm
        results.append(analyzer.analyze_frame(pose, t))
    assert sum(1 for r in results if r.observation.completed_rep) == 3


def test_both_arms_together_count_once():
    results = run(Analyzer("curl", "s-1", "live"), curl_frames(3))  # make_pose moves both arms
    assert sum(1 for r in results if r.observation.completed_rep) == 3
    assert any("same rep as the other side" in e for r in results for e in r.events)


def test_hidden_arm_falls_back_to_the_other_arm():
    analyzer = Analyzer("curl", "s-1", "live")
    pose = make_pose(elbow_deg=160)
    analyzer.analyze_frame(pose, 0.0)
    tracked = analyzer._side
    other = "left" if tracked == "right" else "right"
    hidden = make_pose(elbow_deg=160)
    from fitness_ml.pose import INDEX
    hidden.image[INDEX[f"{tracked}_wrist"], 3] = 0.1
    result = analyzer.analyze_frame(hidden, 33.0)
    assert result.side == other and result.observation.tracking_status == "ready"


def test_wrist_just_below_frame_still_counts_when_visible():
    frames = curl_frames(2)
    analyzer = Analyzer("curl", "s-1", "live")
    results = []
    for t, v in frames:
        pose = make_pose(elbow_deg=v)
        pose.image[:, 1] += 0.35  # push everything down so lowered wrists sit past the bottom edge
        results.append(analyzer.analyze_frame(pose, t))
    assert sum(1 for r in results if r.observation.completed_rep) == 2


def test_new_exercises_travel_as_other_with_detail_and_stay_contract_valid():
    frames = [(i * 50.0, v) for i, v in enumerate([170] * 10 + list(range(170, 95, -5)) + list(range(95, 171, 5)) + [170] * 10)]
    analyzer = Analyzer("push_up", "s-1", "recorded")
    results = [analyzer.analyze_frame(make_pose(elbow_deg=v), t) for t, v in frames]
    obs = results[-1].observation
    assert obs.exercise == "other" and obs.exercise_detail == "push_up"
    assert sum(1 for r in results if r.observation.completed_rep) == 1
    assert errors("observation", json.loads(json.dumps(obs.to_dict()))) == []


class CalibratedFaultModel:
    """A form_issue model that needs 2 calibration reps and only flags at >= 0.6."""
    labels, version, calibration_reps, fault_threshold = ["knees_past_toes", "none"], "fake-cal", 2, 0.6
    meta = {"task": "form_issue"}

    def __init__(self):
        self.references = []

    def rep_vector(self, matrix, ts, side=None):
        return np.array([float(len(ts))])

    def predict_proba(self, matrix, ts, side=None, reference=None):
        self.references.append(reference)
        return np.array([0.65, 0.35])


def test_calibrated_form_model_judges_only_after_calibration_reps():
    model = CalibratedFaultModel()
    results = run(Analyzer("curl", "s-1", "live", form_model=model), curl_frames(4))
    done = [r for r in results if r.observation.completed_rep]
    assert len(done) == 4
    assert [r.observation.issues for r in done[:2]] == [[], []]
    assert any("form calibration 1/2" in e for e in done[0].events)
    assert [i.code for i in done[2].observation.issues] == ["curl.knees_past_toes"]
    assert all(ref is not None for ref in model.references) and len(model.references) == 2
