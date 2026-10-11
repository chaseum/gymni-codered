"""Dynamic cues (GYMAI_DYNAMIC_CUES=1) with Gemini/ElevenLabs stubbed. From the repo root:
`python -m pytest backend/tests`."""
import sys
import threading
import time
import types

from fastapi.testclient import TestClient

from gymai_backend import app as backend

CALLS, RELEASE = [], threading.Event()


def fake_save(request, path):
    CALLS.append(request)
    if request.issue_code == "row.short_pull":
        raise RuntimeError("Gemini down")
    if request.issue_code == "push_up.hips_piked":
        RELEASE.wait(5)  # still generating while the next rep arrives
    return f"rephrased: {request.recommended_action}"


sys.modules["backend.audio.dynamic_cue"] = types.SimpleNamespace(CueRequest=lambda **kw: types.SimpleNamespace(**kw),
                                                                  save_spoken_cue=fake_save)


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
        assert p["text"] == f"rephrased: {backend.CUES['push_up.shallow_depth']}" and p["cue_id"] == f"dynamic/{p['feedback_id']}"
        assert CALLS[-1].evidence == "min_elbow_angle_deg=95.0, threshold=90" and CALLS[-1].exercise == "push_up"

        [issued] = run_set(client, "down", "row", [["row.short_pull"]])  # Gemini fails: fixed text, static cue id
        assert issued["payload"]["text"] == backend.CUES["row.short_pull"] and issued["payload"]["cue_id"] == "row.short_pull"

        assert run_set(client, "fixed", "push_up", [["push_up.hips_piked"], []]) == []  # fixed before the cue was ready
        RELEASE.set()
        time.sleep(0.3)
        assert [e for e in client.get("/api/sessions/fixed/events").json() if e["type"].startswith("feedback")] == []
