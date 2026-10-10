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
    results = run(Analyzer("curl", "s-1", "live"), curl_frames(1, high=75))
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
