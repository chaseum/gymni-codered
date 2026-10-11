"""Dynamic cues (GYMAI_DYNAMIC_CUES=1) with Gemini/ElevenLabs stubbed. From the repo root:
`python -m pytest backend/tests`."""
import threading
import time

import pytest

from fastapi.testclient import TestClient

from gymai_backend import app as backend
from backend.audio import dynamic_cue

CALLS, RELEASE = [], threading.Event()


def fake_save(request, path):
    CALLS.append(request)
    if request.issue_code == "row.short_pull":
        raise RuntimeError("Gemini down")
    if request.issue_code == "push_up.hips_piked":
        RELEASE.wait(5)  # still generating while the next rep arrives
    return f"rephrased: {request.recommended_action}"


@pytest.fixture(autouse=True)
def isolated_audio(monkeypatch, tmp_path):
    CALLS.clear()
    RELEASE.clear()
    backend.DYNAMIC_CUE_LOCKS.clear()
    backend.DYNAMIC_CUE_TASKS.clear()
    monkeypatch.setattr(backend, "AUDIO_DIR", tmp_path)
    monkeypatch.setattr(dynamic_cue, "save_spoken_cue", fake_save)
    yield
    RELEASE.set()


def run_set(client, sid, exercise, reps):
    """Start a set, post one completed rep per entry of `reps` (its issue codes); return the feedback events."""
    client.post("/api/sessions", json={"session_id": sid})
    client.post(f"/api/sessions/{sid}/commands", json={"command_id": f"{sid}-c", "session_id": sid, "intent": "start",
                                                       "args": {"exercise": exercise, "source": "live"}})
    for n, codes in enumerate(reps, 1):
        r = client.post(f"/api/sessions/{sid}/observations", json={
            "schema_version": 1, "observation_id": f"{sid}-{n}", "session_id": sid, "set_id": None, "source": "live",
            "clip_id": None, "time_base": "capture_monotonic", "source_timestamp_ms": 1000 * n, "exercise": exercise,
            "exercise_confidence": None, "tracking_status": "ready", "phase": "lowered",
            "completed_rep": {"rep_index": n, "duration_ms": 1500}, "measurement_basis": "image_2d", "measurements": {},
            "issues": [{"code": c, "evidence": {"min_elbow_angle_deg": 95.0, "threshold": 90, "provenance": "reviewed_rules"}}
                       for c in codes], "inference_provenance": "reviewed_rules", "model_version": None})
        assert r.status_code == 200, r.text
    time.sleep(0.3)  # let the cue tasks finish
    return [e for e in client.get(f"/api/sessions/{sid}/events").json() if e["type"].startswith("feedback")]


def test_dynamic_cues_use_gemini_text_fall_back_and_skip_cues_fixed_before_ready(monkeypatch):
    monkeypatch.setattr(backend, "DYNAMIC_CUES", True)
    with TestClient(backend.app) as client:
        [issued] = run_set(client, "ok", "push_up", [["push_up.shallow_depth"]])
        p = issued["payload"]
        assert p["text"] == f"rephrased: {backend.CUES['push_up.shallow_depth']}"
        assert p["cue_id"] == f"dynamic/{dynamic_cue.cached_cue_id(CALLS[-1])}"
        assert CALLS[-1].evidence == "approved action only" and CALLS[-1].exercise == "push_up"

        [issued] = run_set(client, "down", "row", [["row.short_pull"]])  # Gemini fails: fixed text, static cue id
        assert issued["payload"]["text"] == backend.CUES["row.short_pull"] and issued["payload"]["cue_id"] == "row.short_pull"

        assert run_set(client, "fixed", "push_up", [["push_up.hips_piked"], []]) == []  # fixed before the cue was ready
        RELEASE.set()
        time.sleep(0.3)
        assert [e for e in client.get("/api/sessions/fixed/events").json() if e["type"].startswith("feedback")] == []


def test_pending_correction_is_dropped_on_pause(monkeypatch):
    monkeypatch.setattr(backend, "DYNAMIC_CUES", True)
    with TestClient(backend.app) as client:
        assert run_set(client, "voice-pause", "push_up", [["push_up.hips_piked"]]) == []
        client.post("/api/sessions/voice-pause/commands", json={"command_id": "pause", "session_id": "voice-pause", "intent": "pause"})
        RELEASE.set()
        time.sleep(0.3)
        events = client.get("/api/sessions/voice-pause/events").json()
        assert not any(e["type"] == "feedback.issued" for e in events)


def test_workout_voice_endpoint_only_voices_approved_prompts(monkeypatch):
    monkeypatch.setattr(backend, "DYNAMIC_CUES", True)
    calls = []

    def fake_voice(text, output):
        calls.append(text)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(b"ID3test-audio")
        return text

    monkeypatch.setattr(dynamic_cue, "save_voice_clip", fake_voice)
    with TestClient(backend.app) as client:
        response = client.get("/api/coach/audio/paused")
        assert response.status_code == 200
        assert response.headers["content-type"] == "audio/mpeg"
        assert response.content == b"ID3test-audio"
        assert calls == [backend.COACH_PROMPTS["paused"]]
        assert client.get("/api/coach/audio/untrusted_text").status_code == 404
        monkeypatch.setattr(backend, "DYNAMIC_CUES", False)
        assert client.get("/api/coach/audio/paused").status_code == 503


def test_voice_failure_keeps_provider_details_out_of_client(monkeypatch):
    monkeypatch.setattr(backend, "DYNAMIC_CUES", True)

    def fail(*args):
        raise RuntimeError("secret-provider-key")

    monkeypatch.setattr(dynamic_cue, "save_voice_clip", fail)
    with TestClient(backend.app) as client:
        response = client.get("/api/coach/audio/paused")
        assert response.status_code == 502
        assert "secret-provider-key" not in response.text
