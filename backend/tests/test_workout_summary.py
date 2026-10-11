from uuid import uuid4

from fastapi.testclient import TestClient
from backend.gymai_backend.cloud_app import app


def workout():
    return {"schema_version": 1, "workout_id": str(uuid4()), "state": "complete", "sets": [
        {"set_id": "set-001", "exercise": "curl", "actual_reps": 2, "active_duration_ms": 6000,
         "reps": [{"rep_count": index, "observation": {
             "source": "live", "exercise": "curl", "tracking_status": "ready",
             "inference_provenance": "trained_model", "completed_rep": {"rep_index": index, "duration_ms": index * 1000},
             "issues": [{"code": "curl.partial_range"}] if index == 1 else []}}
             for index in (1, 2)]}]}


def test_summary_uses_committed_measurements_and_is_safe_to_retry(monkeypatch):
    monkeypatch.delenv("GYMAI_TOKEN", raising=False)
    body = workout()
    client = TestClient(app)
    response = client.post("/api/workouts/summary", json=body)
    assert response.status_code == 200
    assert response.json() == client.post("/api/workouts/summary", json=body).json()
    assert response.json()["total_reps"] == 2
    assert response.json()["sets"][0]["mean_rep_duration_ms"] == 1500
    assert response.json()["sets"][0]["issue_rep_counts"] == {"curl.partial_range": 1}
    assert response.json()["storage"] == "iphone"


def test_summary_rejects_incomplete_or_untrusted_workouts(monkeypatch):
    monkeypatch.delenv("GYMAI_TOKEN", raising=False)
    client = TestClient(app)
    for field, value in [("state", "active"), ("schema_version", 2)]:
        body = workout(); body[field] = value
        assert client.post("/api/workouts/summary", json=body).status_code == 422
    for field, value in [("tracking_status", "lost"), ("exercise", "squat"), ("inference_provenance", "fixture")]:
        body = workout(); body["sets"][0]["reps"][0]["observation"][field] = value
        assert client.post("/api/workouts/summary", json=body).status_code == 422
    body = workout(); body["sets"][0]["actual_reps"] = 3
    assert client.post("/api/workouts/summary", json=body).status_code == 422
    assert client.post("/api/workouts/summary", content=b" " * 2_000_001).status_code == 413
