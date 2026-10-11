import pytest

from gymai_backend import app as backend
from gymai_backend import workout_history


@pytest.fixture(autouse=True)
def isolated_history(monkeypatch, tmp_path):
    monkeypatch.setattr(workout_history, "HISTORY_DIR", tmp_path / "workouts")
    backend.sessions.clear()
