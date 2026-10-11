"""Local session JSON: accepted reps and measured timing, never raw video or keys."""

import asyncio
import copy
import hashlib
import json
import os
from pathlib import Path

HISTORY_DIR = Path(os.getenv("GYMAI_WORKOUT_DIR", str(Path(__file__).resolve().parents[2] / "demo/workouts")))


def history_path(session_id: str) -> Path:
    # IDs arrive from clients; never interpret them as file paths.
    return HISTORY_DIR / f"{hashlib.sha256(session_id.encode()).hexdigest()[:24]}.json"


class WorkoutHistory:
    def __init__(self, session_id: str):
        self.data = {"version": 1, "session_id": session_id, "state": "ready", "sets": []}
        self.active_since = None
        self.lock = asyncio.Lock()
        self.revision, self.saved_revision = 0, -1

    @property
    def current(self):
        return self.data["sets"][-1] if self.data["sets"] else None

    def state_changed(self, state: str, now: int):
        if self.current and self.active_since is not None:
            self.current["active_duration_ms"] += max(0, now - self.active_since)
        self.active_since = now if state == "active" and self.current else None
        self.data["state"] = state
        self.revision += 1

    def new_set(self, set_id, exercise, source, target, load, now):
        self.data["sets"].append({
            "set_id": set_id, "exercise": exercise, "source": source, "target_reps": target,
            "actual_reps": 0, "load": load, "started_at_ms": now, "ended_at_ms": None,
            "active_duration_ms": 0, "rep_work_ms": 0, "timed_reps": 0,
            "opening_rep_duration_ms": None, "reps": [],
        })
        self.active_since = now if self.data["state"] == "active" else None
        self.revision += 1

    def finish_set(self, now):
        if not self.current or self.current["ended_at_ms"] is not None:
            return
        if self.active_since is not None:
            self.current["active_duration_ms"] += max(0, now - self.active_since)
        self.active_since = None
        self.current["ended_at_ms"] = now
        self.revision += 1

    def append_rep(self, obs, count, baseline, coaching):
        duration = obs["completed_rep"].get("duration_ms")
        rep = {"rep_count": count, **copy.deepcopy(obs["completed_rep"])}
        for key in ("observation_id", "source_timestamp_ms", "time_base", "source", "clip_id",
                    "measurement_basis", "measurements", "issues", "inference_provenance", "model_version"):
            rep[key] = copy.deepcopy(obs.get(key))
        rep["coaching"] = coaching
        self.current["reps"].append(rep)
        self.current["actual_reps"] = count
        if duration is not None and duration > 0:
            self.current["rep_work_ms"] += duration
            self.current["timed_reps"] += 1
        self.current["opening_rep_duration_ms"] = baseline
        self.revision += 1

    def snapshot(self, now):
        data = copy.deepcopy(self.data)
        if self.active_since is not None and data["sets"]:
            data["sets"][-1]["active_duration_ms"] += max(0, now - self.active_since)
        return data

    async def save(self, now):
        async with self.lock:
            if self.revision == self.saved_revision:
                return
            revision = self.revision
            data = self.snapshot(now)
            await asyncio.to_thread(self._write, data)
            self.saved_revision = revision

    @staticmethod
    def _write(data):
        path = history_path(data["session_id"])
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(".json.tmp")
        temporary.write_text(json.dumps(data, indent=2, allow_nan=False) + "\n")
        temporary.replace(path)
