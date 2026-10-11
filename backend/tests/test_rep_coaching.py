import json
import threading

import pytest
from fastapi.testclient import TestClient

from backend.audio import dynamic_cue
from gymai_backend import app as backend
from gymai_backend.rep_coaching import RepCoach
from gymai_backend.workout_history import history_path


def observation(n, duration=2000, **overrides):
    return {
        "schema_version": 1, "session_id": "rep-coaching", "observation_id": f"obs-{n}",
        "source": "live", "clip_id": None, "time_base": "capture_monotonic",
        "source_timestamp_ms": n * 3000, "exercise": "curl", "tracking_status": "ready",
        "phase": "lowered", "completed_rep": {"rep_index": n, "duration_ms": duration},
        "measurements": {"min_elbow_angle_deg": 80}, "measurement_basis": "image_2d",
        "issues": [], "inference_provenance": "trained_model", "model_version": "test-gru",
        **overrides,
    }


def select(coach, n, duration=2000, **overrides):
    obs = observation(n, duration, **overrides)
    return coach.select(obs, n, 8, bool(obs["issues"]), n * 3000)


@pytest.mark.parametrize("duration,kind", [(1200, "pace_fast"), (3200, "pace_slow")])
def test_pace_requires_baseline_and_two_consistent_reps(duration, kind):
    coach = RepCoach()
    for n in range(1, 4):
        select(coach, n)
    assert coach.baseline_ms == 2000
    assert select(coach, 4, duration)["kind"] == "count"  # one outlier is not a pace diagnosis
    cue = select(coach, 5, duration)
    assert cue is None  # six-second speech cooldown
    cue = select(coach, 6, duration)
    assert cue["kind"] == kind
    assert "opening" in cue["text"].lower() if kind == "pace_fast" else "reset" in cue["text"].lower()


def test_missing_timing_form_issues_and_changed_stream_cannot_trigger_pace():
    coach = RepCoach()
    for n in range(1, 4):
        select(coach, n)
    select(coach, 4, 1000)
    select(coach, 5, None)
    assert select(coach, 6, 1000)["kind"] == "count"
    assert select(coach, 7, 1000, issues=[{"code": "curl.partial_range"}]) is None
    select(coach, 8, 1000, source="recorded", clip_id="different", time_base="video_pts")
    assert coach.baseline_ms is None
    coach.reset_timing()
    assert coach.opening == []


def start(client, target=8):
    client.post("/api/sessions", json={"session_id": "rep-coaching"})
    return command(client, "start", exercise="curl", source="live", target_reps=target)


def command(client, intent, **args):
    return client.post("/api/sessions/rep-coaching/commands", json={
        "session_id": "rep-coaching", "command_id": f"command-{intent}-{len(backend.sessions['rep-coaching'].events)}",
        "intent": intent, "args": args,
    })


def post(client, n, **kwargs):
    r = client.post("/api/sessions/rep-coaching/observations", json=observation(n, **kwargs))
    assert r.status_code == 200, r.text
    return r.json()


def test_json_journal_counts_only_accepted_reps_and_separates_clock_domains(monkeypatch):
    monkeypatch.setattr(backend, "DYNAMIC_CUES", False)
    clock = [1_800_000_000_000]
    monkeypatch.setattr(backend, "now_ms", lambda: clock[0])
    with TestClient(backend.app) as client:
        assert start(client).status_code == 200
        clock[0] += 3000
        post(client, 1)
        assert post(client, 1)["duplicate"]
        command(client, "pause")
        clock[0] += 20_000
        post(client, 2)
        command(client, "resume")
        assert not post(client, 2, observation_id="new-envelope").get("ignored")
        post(client, 3, tracking_status="lost")
        post(client, 4, source="recorded", clip_id="wrong-source", time_base="video_pts")
        post(client, 5, set_id="set-old")
        clock[0] += 4000
        post(client, 6, duration=None)
        command(client, "end")
        data = json.loads(history_path("rep-coaching").read_text())
        [s] = data["sets"]
        assert data["state"] == "complete"
        assert s["target_reps"] == 8 and s["actual_reps"] == 2
        assert s["active_duration_ms"] == 7000  # excludes twenty seconds paused
        assert s["rep_work_ms"] == 2000 and s["timed_reps"] == 1
        assert [r["rep_index"] for r in s["reps"]] == [1, 6]
        assert s["reps"][0]["source_timestamp_ms"] == 3000  # not epoch
        assert s["reps"][0]["model_version"] == "test-gru"
        assert client.get("/api/sessions/rep-coaching/workout").json() == data
        backend.sessions.clear()  # history survives server restart; live state does not
        assert client.get("/api/sessions/rep-coaching/workout").json() == data


def test_new_sets_reset_counts_and_timing(monkeypatch):
    monkeypatch.setattr(backend, "DYNAMIC_CUES", False)
    with TestClient(backend.app) as client:
        start(client)
        for n in range(1, 4):
            post(client, n)
        command(client, "next_exercise", exercise="squat", target_reps=5)
        post(client, 4, exercise="squat", duration=4000)
        command(client, "end")
        a, b = client.get("/api/sessions/rep-coaching/workout").json()["sets"]
        assert (a["actual_reps"], b["actual_reps"]) == (3, 1)
        assert a["opening_rep_duration_ms"] == 2000 and b["opening_rep_duration_ms"] is None
        assert a["ended_at_ms"] <= b["started_at_ms"]


def test_counts_are_factual_corrections_take_priority_and_audio_reuses_cache(monkeypatch, tmp_path):
    monkeypatch.setattr(backend, "DYNAMIC_CUES", True)
    monkeypatch.setattr(backend, "AUDIO_DIR", tmp_path)
    monkeypatch.setattr(dynamic_cue.genai, "Client", lambda **kw: pytest.fail("Rep coaching must not use Gemini"))
    calls = []
    monkeypatch.setattr(dynamic_cue, "generate_voice_audio", lambda text: calls.append(text) or b"ID3test")
    with TestClient(backend.app) as client:
        start(client)
        post(client, 1)
        cue = [e for e in backend.sessions["rep-coaching"].events if e["type"] == "coach.cue"][0]
        backend.check("event", cue)
        path = f"/api/sessions/rep-coaching/coaching/{cue['payload']['cue_id']}/audio"
        assert client.get(path).content == b"ID3test"
        assert client.get(path).content == b"ID3test"
        assert len(calls) == 1
        post(client, 2, issues=[{"code": "curl.partial_range"}])
        assert client.get(path).status_code == 409
        assert client.get("/api/sessions/rep-coaching/coaching/say-anything/audio").status_code == 404
        assert [e["payload"]["rep_count"] for e in backend.sessions["rep-coaching"].events if e["type"] == "coach.cue"] == [1]
        command(client, "pause")
        assert client.get(path).status_code == 409


def test_one_form_instruction_and_spaced_persistent_reminders(monkeypatch):
    monkeypatch.setattr(backend, "DYNAMIC_CUES", False)
    clock = [0]
    monkeypatch.setattr(backend, "coaching_clock_ms", lambda: clock[0])
    with TestClient(backend.app) as client:
        start(client)
        issues = [{"code": "curl.partial_range"}, {"code": "curl.elbow_drift"}]
        for n in range(1, 8):
            clock[0] = n * 3000
            post(client, n, issues=issues)
        events = [e["payload"] for e in backend.sessions["rep-coaching"].events if e["type"] == "feedback.issued"]
        assert [p["rep_count"] for p in events] == [1, 4, 7]
        assert [p["issue_code"] for p in events] == ["curl.partial_range", "curl.elbow_drift", "curl.partial_range"]
        assert events[0]["feedback_id"] == events[2]["feedback_id"]
        assert events[0]["utterance_id"] != events[2]["utterance_id"]


def test_pause_during_voice_generation_drops_audio(monkeypatch, tmp_path):
    monkeypatch.setattr(backend, "DYNAMIC_CUES", True)
    monkeypatch.setattr(backend, "AUDIO_DIR", tmp_path)
    started, release = threading.Event(), threading.Event()
    backend.DYNAMIC_CUE_TASKS.clear()
    backend.DYNAMIC_CUE_LOCKS.clear()

    def delayed(text):
        started.set()
        assert release.wait(3)
        return b"ID3test"

    monkeypatch.setattr(dynamic_cue, "generate_voice_audio", delayed)
    with TestClient(backend.app) as client:
        start(client)
        post(client, 1)
        response = []
        thread = threading.Thread(target=lambda: response.append(client.get("/api/sessions/rep-coaching/coaching/coach-set-001-1/audio")))
        thread.start()
        try:
            assert started.wait(2)
            command(client, "pause")
        finally:
            release.set()
            thread.join(3)
        assert response[0].status_code == 409
