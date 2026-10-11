"""Authoritative workout session server. Contracts: ../../contracts/protocol.md

Run: uvicorn gymai_backend.app:app --host 0.0.0.0 --port 8000
All handlers are `async def`, so they run on one event loop thread and need no locks.
"""
import asyncio
import itertools
import json
import os
import time
from pathlib import Path

from fastapi import Body, Depends, FastAPI, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from jsonschema import Draft202012Validator

from .backboard_memory import add_profile_memory, delete_profile_memory, list_profile_memories
from .gemini import send_coach_message

SCHEMA = json.loads((Path(__file__).resolve().parents[2] / "contracts" / "gymai.schema.json").read_text())
VALIDATORS = {k: Draft202012Validator({**SCHEMA, "$ref": f"#/$defs/{k}"})
              for k in ("observation", "command", "heart_rate_sample", "event")}
TOKEN = os.environ.get("GYMAI_TOKEN")  # optional shared LAN secret; unset = open (trusted hotspot only)
HR_STALE_MS = 10_000

# Only issue codes listed here may be spoken. cue_id == audio file stem in assets/audio/.
# ponytail: one cue per issue per set, no priority queue yet; Tyler replaces with the coaching policy.
# With GYMAI_DYNAMIC_CUES=1 the text is the approved action that Gemini rephrases (backend/audio/dynamic_cue.py)
# and ElevenLabs voices; the mp3 is served at /audio/dynamic/<feedback_id>.mp3 (cue_id "dynamic/<feedback_id>").
CUES = {
    "curl.elbow_drift": "Keep your elbows pinned to your sides.",
    "curl.partial_range": "Let the weight come all the way down.",
    "squat.shallow_depth": "Sit a little deeper if it feels comfortable.",
    "deadlift.hips_rise_early": "Push the floor away; let your hips and chest rise together.",
    "shoulder_press.incomplete_lockout": "Press all the way up until your arms are straight overhead.",
    "triceps_extension.incomplete_extension": "Straighten your arms fully at the top of each rep.",
    "row.short_pull": "Pull your elbow further back, toward your hip.",
    "push_up.shallow_depth": "Lower your chest a little closer to the floor.",
    "push_up.hips_sagging": "Squeeze your glutes and keep your hips in line with your shoulders.",
    "push_up.hips_piked": "Lower your hips so your body forms a straight line.",
    "side_bend.partial_range": "Bend a little further to the side, keeping your hips still.",
}
DYNAMIC_CUES = os.environ.get("GYMAI_DYNAMIC_CUES") == "1"
AUDIO_DIR = Path(__file__).resolve().parents[2] / "assets" / "audio"
DYNAMIC_CUE_TIMEOUT_S = 8.0  # slower than this and the fixed text is used instead


def now_ms() -> int:
    return int(time.time() * 1000)


def check(kind: str, data: dict) -> dict:
    errs = [f"{'/'.join(map(str, e.path)) or '<root>'}: {e.message}" for e in VALIDATORS[kind].iter_errors(data)]
    if errs:
        raise HTTPException(422, {"contract": kind, "errors": errs})
    return data


class Session:
    def __init__(self, session_id: str, participant_id: str | None):
        self.id, self.participant_id = session_id, participant_id
        self.state, self.source, self.exercise = "ready", None, None
        self.set_n, self.rep_count, self.target_reps, self.load = 0, 0, None, None
        self.tracking = None
        self.hr = None  # last real sample dict, never synthesized
        self.rest_ends_at = None
        self.active_issues: dict[str, str] = {}  # issue_code -> feedback_id
        self.pending_cues: set[str] = set()  # feedback_ids whose dynamic cue is still being generated
        self.events: list[dict] = []
        self.subscribers: set[asyncio.Queue] = set()
        self.acks: dict[str, dict] = {}
        self.seen_obs: set[str] = set()
        self.seen_hr: set[str] = set()
        self.max_rep_index = 0
        self.feedback_ids = itertools.count(1)

    @property
    def set_id(self):
        return f"set-{self.set_n:03d}" if self.set_n else None

    def emit(self, type_: str, payload: dict) -> dict:
        ev = {"schema_version": 1, "event_id": len(self.events) + 1, "session_id": self.id,
              "timestamp_ms": now_ms(), "type": type_, "payload": payload}
        self.events.append(ev)
        for q in self.subscribers:
            q.put_nowait(ev)
        return ev

    def hr_view(self) -> dict:
        if not self.hr:
            return {"status": "unavailable", "bpm": None, "sample_id": None, "sample_timestamp_ms": None, "source": None}
        stale = self.hr["received_ms"] - self.hr["sample_timestamp_ms"] > HR_STALE_MS \
            or now_ms() - self.hr["received_ms"] > HR_STALE_MS
        return {"status": "stale" if stale else "live", "bpm": self.hr["bpm"], "sample_id": self.hr["sample_id"],
                "sample_timestamp_ms": self.hr["sample_timestamp_ms"], "source": self.hr["source"]}

    def rest_view(self):
        return {"status": "resting", "ends_at_ms": self.rest_ends_at} if self.rest_ends_at else None

    def snapshot(self) -> dict:
        return {"schema_version": 1, "event_id": len(self.events), "session_id": self.id, "timestamp_ms": now_ms(),
                "type": "session.snapshot", "payload": {
                    "state": self.state, "source": self.source, "exercise": self.exercise, "set_id": self.set_id,
                    "rep_count": self.rep_count, "target_reps": self.target_reps, "tracking_status": self.tracking,
                    "heart_rate": self.hr_view(), "rest": self.rest_view(), "active_issues": list(self.active_issues)}}

    # --- commands -------------------------------------------------------------------------------
    def command(self, cmd: dict) -> dict:
        if cmd["command_id"] in self.acks:
            return {**self.acks[cmd["command_id"]], "duplicate": True}
        error = self._apply(cmd["intent"], cmd.get("args", {}), cmd["command_id"])
        ack = {"command_id": cmd["command_id"], "accepted": error is None, "duplicate": False,
               "state": self.state, "error": error}
        self.acks[cmd["command_id"]] = ack
        return ack

    def _apply(self, intent: str, args: dict, cid: str):
        allowed = {"start": {"ready"}, "pause": {"active"}, "rest": {"active", "paused"},
                   "extend_rest": {"paused"}, "resume": {"paused"}, "next_exercise": {"active", "paused"},
                   "end": {"ready", "active", "paused"}}
        if self.state not in allowed[intent]:
            return f"invalid_transition:{self.state}->{intent}"
        if intent == "extend_rest" and not self.rest_ends_at:
            return "not_resting"
        if intent == "start":
            self.source = args.get("source", "live")
            self._set_state("active", cid)
            self._new_set(args)
            self.emit("coach.state", {"coach": "observing"})
        elif intent in ("pause", "rest"):
            if self.state != "paused":
                self._set_state("paused", cid)
            if intent == "rest":
                self.rest_ends_at = now_ms() + 1000 * args.get("rest_seconds", 60)
                self.emit("rest.updated", self.rest_view())
                self.emit("coach.state", {"coach": "resting"})
        elif intent == "extend_rest":
            self.rest_ends_at += 1000 * args.get("rest_seconds", 30)
            self.emit("rest.updated", self.rest_view())
        elif intent == "resume":  # only explicit resume leaves rest; timer expiry never does
            self._set_state("active", cid)
            if self.rest_ends_at:
                self.rest_ends_at = None
                self.emit("rest.updated", {"status": "ended", "ends_at_ms": None})
            self.emit("coach.state", {"coach": "observing"})
        elif intent == "next_exercise":
            self._finish_set()
            self._new_set(args)
        elif intent == "end":
            self._finish_set()
            self.rest_ends_at = None
            self._set_state("complete", cid)
            self.emit("coach.state", {"coach": "idle"})

    def _set_state(self, state: str, cid: str):
        self.state = state
        self.emit("session.state", {"state": state, "command_id": cid})

    def _new_set(self, args: dict):
        self.set_n += 1
        self.exercise = args.get("exercise", self.exercise or "curl")
        self.target_reps, self.load = args.get("target_reps"), args.get("load")
        self.rep_count, self.active_issues = 0, {}
        self.pending_cues.clear()  # a cue still generating for the old set is dropped
        self.emit("exercise.changed", {"exercise": self.exercise, "set_id": self.set_id, "target_reps": self.target_reps})

    def _finish_set(self):
        if self.set_n and self.rep_count:
            self.emit("set.completed", {"set_id": self.set_id, "exercise": self.exercise,
                                        "rep_count": self.rep_count, "load": self.load})

    # --- ML observations ------------------------------------------------------------------------
    def observe(self, obs: dict) -> dict:
        if obs["observation_id"] in self.seen_obs:
            return {"accepted": True, "duplicate": True}
        self.seen_obs.add(obs["observation_id"])
        if self.state != "active":
            # Still consume rep indices so reps done while paused never count after resume.
            if obs["completed_rep"]:
                self.max_rep_index = max(self.max_rep_index, obs["completed_rep"]["rep_index"])
            return {"accepted": True, "duplicate": False, "ignored": "not_active"}
        if obs["tracking_status"] != self.tracking:
            self.tracking = obs["tracking_status"]
            self.emit("tracking.status", {"status": self.tracking, "source": obs["source"]})
        rep = obs["completed_rep"]
        if not rep or rep["rep_index"] <= self.max_rep_index:
            return {"accepted": True, "duplicate": False}
        self.max_rep_index = rep["rep_index"]
        if self.tracking != "ready" or obs["exercise"] != self.exercise:
            return {"accepted": True, "duplicate": False, "ignored": "rep_not_trusted"}
        # Backend is the only place a rep is committed.
        self.rep_count += 1
        self.emit("rep.completed", {"exercise": self.exercise, "set_id": self.set_id, "rep_count": self.rep_count,
                                    "target_reps": self.target_reps, "duration_ms": rep.get("duration_ms")})
        issues = {i["code"]: i.get("evidence", {}) for i in obs["issues"] if i["code"] in CUES}
        for code, evidence in issues.items():
            if code not in self.active_issues:
                fid = f"fb-{next(self.feedback_ids)}"
                self.active_issues[code] = fid
                if DYNAMIC_CUES:
                    self.pending_cues.add(fid)
                    asyncio.get_running_loop().create_task(self._dynamic_cue(code, evidence, fid, self.set_id, self.rep_count))
                else:
                    self._issue(code, fid, CUES[code], code, self.set_id, self.rep_count)
        for code in [c for c in self.active_issues if c not in issues]:
            fid = self.active_issues.pop(code)
            if fid in self.pending_cues:  # fixed before its cue was ready: never voice it
                self.pending_cues.discard(fid)
                continue
            self.emit("feedback.improved", {"feedback_id": fid, "issue_code": code,
                                            "set_id": self.set_id, "rep_count": self.rep_count})
        return {"accepted": True, "duplicate": False}

    def _issue(self, code: str, fid: str, text: str, cue_id: str, set_id: str, rep_count: int):
        self.emit("feedback.issued", {"feedback_id": fid, "issue_code": code, "cue_id": cue_id, "text": text,
                                      "set_id": set_id, "rep_count": rep_count})

    async def _dynamic_cue(self, code: str, evidence: dict, fid: str, set_id: str, rep_count: int):
        """Gemini rephrases the approved action using the rep's measured evidence; ElevenLabs voices it.
        Any failure or timeout falls back to the fixed approved text (cue_id = issue code)."""
        text, cue_id = CUES[code], code
        try:
            from backend.audio.dynamic_cue import CueRequest, save_spoken_cue  # needs uvicorn started at the repo root
            facts = ", ".join(f"{k}={v}" for k, v in evidence.items() if k not in ("provenance", "model_version"))
            request = CueRequest(exercise=code.split(".")[0], issue_code=code, evidence=facts[:300] or "none",
                                 recommended_action=CUES[code], tracking_status="ready", coach_approved=True,
                                 confidence=evidence.get("probability", 1.0))  # rules are deterministic: 1.0
            text = await asyncio.wait_for(asyncio.to_thread(save_spoken_cue, request, AUDIO_DIR / "dynamic" / f"{fid}.mp3"),
                                          DYNAMIC_CUE_TIMEOUT_S)
            cue_id = f"dynamic/{fid}"
        except Exception as exc:  # noqa: BLE001 - a cue outage must never stop the workout
            print(f"dynamic cue for {code} failed ({type(exc).__name__}: {exc}); using the fixed text", flush=True)
        if fid in self.pending_cues:  # still active (not already improved)
            self.pending_cues.discard(fid)
            self._issue(code, fid, text, cue_id, set_id, rep_count)

    def heart_rate(self, sample: dict) -> dict:
        if sample["sample_id"] in self.seen_hr:
            return {"accepted": True, "duplicate": True}
        received = now_ms()
        if sample["sample_timestamp_ms"] > received + 5_000:
            raise HTTPException(422, "sample_timestamp_ms is in the future; check the Watch clock")
        self.seen_hr.add(sample["sample_id"])
        if self.hr and sample["sample_timestamp_ms"] <= self.hr["sample_timestamp_ms"]:
            return {"accepted": True, "duplicate": False, "ignored": "older_than_current"}
        self.hr = {**sample, "received_ms": received}
        self.emit("heart_rate.updated", self.hr_view())
        return {"accepted": True, "duplicate": False}


app = FastAPI(title="Gym&I backend")
app.mount("/audio", StaticFiles(directory=AUDIO_DIR, check_dir=False), name="audio")  # cue mp3s for the phone
sessions: dict[str, Session] = {}  # ponytail: in-memory, lost on restart; add SQLite when history/PRs land


def auth(request: Request):
    if TOKEN and request.headers.get("authorization") != f"Bearer {TOKEN}":
        raise HTTPException(401, "missing or wrong bearer token")


class CoachMessage(BaseModel):
    message: str = Field(min_length=1, max_length=2000)
    thread_id: str | None = Field(default=None, min_length=1, max_length=100)
    profile_id: str | None = Field(default=None, min_length=1, max_length=128)


class CoachMemory(BaseModel):
    content: str = Field(min_length=1, max_length=1000)


@app.post("/api/coach/messages", dependencies=[Depends(auth)])
async def coach_message(body: CoachMessage):
    """Send an onboarding/planning conversation turn to Gemini."""
    try:
        return await send_coach_message(body.message, body.thread_id, body.profile_id)
    except RuntimeError as exc:
        raise HTTPException(503, str(exc)) from exc
    except Exception as exc:
        # Keep provider details and credentials out of the client response.
        raise HTTPException(502, "Coach request failed; try again shortly.") from exc


@app.post("/api/coach/profiles/{profile_id}/memories", dependencies=[Depends(auth)])
async def save_coach_memory(profile_id: str, body: CoachMemory):
    """Save a user-confirmed profile fact in Backboard memory."""
    try:
        memory_id = await add_profile_memory(profile_id, body.content)
        return {"saved": True, "memory_id": memory_id}
    except RuntimeError as exc:
        raise HTTPException(503, str(exc)) from exc
    except Exception as exc:
        raise HTTPException(502, "Could not save this profile memory.") from exc


@app.get("/api/coach/profiles/{profile_id}/memories", dependencies=[Depends(auth)])
async def get_coach_memories(profile_id: str):
    """List saved facts so a client can show or review them."""
    try:
        return {"memories": await list_profile_memories(profile_id)}
    except RuntimeError as exc:
        raise HTTPException(503, str(exc)) from exc
    except Exception as exc:
        raise HTTPException(502, "Could not load profile memories.") from exc


@app.delete("/api/coach/profiles/{profile_id}/memories/{memory_id}", dependencies=[Depends(auth)])
async def remove_coach_memory(profile_id: str, memory_id: str):
    """Delete one saved profile fact."""
    try:
        await delete_profile_memory(profile_id, memory_id)
        return {"deleted": True, "memory_id": memory_id}
    except RuntimeError as exc:
        raise HTTPException(503, str(exc)) from exc
    except Exception as exc:
        raise HTTPException(502, "Could not delete profile memory.") from exc


def get(session_id: str) -> Session:
    if session_id not in sessions:
        raise HTTPException(404, f"unknown session {session_id}")
    return sessions[session_id]


def same_session(s: Session, body: dict):
    if body["session_id"] != s.id:
        raise HTTPException(422, "body session_id does not match URL")


@app.get("/health")
async def health():
    return {"ok": True, "schema_version": 1, "sessions": len(sessions)}


@app.post("/api/sessions", status_code=201, dependencies=[Depends(auth)])
async def create_session(body: dict = Body(default={})):
    sid = body.get("session_id") or f"session-{len(sessions) + 1:03d}-{now_ms() % 100000}"
    if sid in sessions:
        raise HTTPException(409, f"session {sid} exists")
    sessions[sid] = Session(sid, body.get("participant_id"))
    return sessions[sid].snapshot()


@app.get("/api/sessions/{session_id}", dependencies=[Depends(auth)])
async def snapshot(session_id: str):
    return get(session_id).snapshot()


@app.get("/api/sessions/{session_id}/events", dependencies=[Depends(auth)])
async def events(session_id: str, after: int = 0):
    return get(session_id).events[after:]


@app.post("/api/sessions/{session_id}/commands", dependencies=[Depends(auth)])
async def command(session_id: str, body: dict = Body(...)):
    s = get(session_id)
    same_session(s, check("command", body))
    return s.command(body)


@app.post("/api/sessions/{session_id}/observations", dependencies=[Depends(auth)])
async def observation(session_id: str, body: dict = Body(...)):
    s = get(session_id)
    same_session(s, check("observation", body))
    return s.observe(body)


@app.post("/api/sessions/{session_id}/heart_rate", dependencies=[Depends(auth)])
async def heart_rate(session_id: str, body: dict = Body(...)):
    s = get(session_id)
    same_session(s, check("heart_rate_sample", body))
    return s.heart_rate(body)


@app.websocket("/ws/workout")
async def workout_ws(ws: WebSocket, session_id: str, token: str | None = None):
    """Sends session.snapshot first, then every later event. Reconnect = new snapshot; no replay needed."""
    if TOKEN and token != TOKEN:
        await ws.close(code=4401)
        return
    if session_id not in sessions:
        await ws.close(code=4404)
        return
    s = sessions[session_id]
    await ws.accept()
    q: asyncio.Queue = asyncio.Queue()
    s.subscribers.add(q)  # subscribe and snapshot in the same tick: no gap, no overlap
    try:
        await ws.send_json(s.snapshot())
        while True:
            await ws.send_json(await q.get())
    except WebSocketDisconnect:
        pass
    finally:
        s.subscribers.discard(q)
