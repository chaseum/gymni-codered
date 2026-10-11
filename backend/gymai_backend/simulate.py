"""Replay contract fixtures through the backend.

    python -m gymai_backend.simulate                     # in-process check of every fixture (exit 1 on mismatch)
    python -m gymai_backend.simulate --url http://localhost:8000 --session demo --delay 0.7 \
        contracts/fixtures/corrected_issue.json         # drive a running server so the phone sees events
"""
import argparse
import json
import os
import sys
import time
from pathlib import Path

import httpx

from .app import VALIDATORS

FIXTURES = Path(__file__).resolve().parents[2] / "contracts" / "fixtures"
ROUTES = {"command": "commands", "observation": "observations", "heart_rate": "heart_rate"}


def run(client, fixture: dict, session_id: str, delay: float = 0) -> list[str]:
    """Replays input steps; returns a list of problems (empty = pass)."""
    r = client.post("/api/sessions", json={"session_id": session_id})
    if r.status_code != 201:
        return [f"create session: {r.status_code} {r.text}"]
    for step in fixture["steps"]:
        if step["kind"] not in ROUTES:
            continue  # example events / pico lines are documentation, not inputs
        data = {**step["data"], "session_id": session_id}
        r = client.post(f"/api/sessions/{session_id}/{ROUTES[step['kind']]}", json=data)
        if r.status_code != 200:
            return [f"{step['kind']} {data.get('command_id') or data.get('observation_id')}: {r.status_code} {r.text}"]
        time.sleep(delay)

    problems = []
    events = client.get(f"/api/sessions/{session_id}/events").json()
    snap = client.get(f"/api/sessions/{session_id}").json()
    for ev in events + [snap]:
        problems += [f"event {ev['event_id']} {ev['type']}: {e.message}" for e in VALIDATORS["event"].iter_errors(ev)]
    got = [e["type"] for e in events]
    if "expect_events" in fixture and got != fixture["expect_events"]:
        problems.append(f"events\n  expected {fixture['expect_events']}\n  got      {got}")
    for key, want in fixture.get("expect_snapshot", {}).items():
        have = snap["payload"][key]
        if isinstance(want, dict):
            have = {k: have.get(k) for k in want}
        if have != want:
            problems.append(f"snapshot.{key}: expected {want!r}, got {have!r}")
    return problems


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("fixtures", nargs="*", type=Path)
    ap.add_argument("--url", help="running server; default runs in-process")
    ap.add_argument("--session", help="override session_id (needed when re-running against a live server)")
    ap.add_argument("--delay", type=float, default=0)
    args = ap.parse_args()
    paths = args.fixtures or sorted(p for p in FIXTURES.glob("*.json") if "expect_events" in p.read_text())
    if args.url:
        token = os.environ.get("GYMAI_TOKEN")
        client = httpx.Client(base_url=args.url, headers={"Authorization": f"Bearer {token}"} if token else {})
    else:
        from fastapi.testclient import TestClient
        from . import app as backend
        backend.DYNAMIC_CUES = False  # fixtures expect the fixed cue text; never call Gemini/ElevenLabs here
        client = TestClient(backend.app)
    failed = 0
    for path in paths:
        fixture = json.loads(path.read_text())
        problems = run(client, fixture, args.session or fixture["session_id"], args.delay)
        failed += bool(problems)
        print(f"{'FAIL' if problems else 'ok  '} {path.name}")
        for p in problems:
            print(f"     {p}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
