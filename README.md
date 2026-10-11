# gymni-codered
repo for codered orion 2026

**Gym&AI**: an iPhone-first, hands-free fitness coach. The laptop webcam is the vision sensor (Python + MediaPipe), a FastAPI backend on the laptop owns the session, and the SwiftUI iPhone app (plus Watch HR, plus a Pico button/display) renders the backend's state. Plan: [`GYM_AND_AI_TEAM_BRIEF_REVISED.md`](GYM_AND_AI_TEAM_BRIEF_REVISED.md). Wire protocol: [`contracts/protocol.md`](contracts/protocol.md).

Shared planner exercise data and healthy-adult prescription notes: [`contracts/exercise_catalog.json`](contracts/exercise_catalog.json) and [`docs/exercise_catalog.md`](docs/exercise_catalog.md).

## Who owns what

| Path | Owner | Status |
|---|---|---|
| `contracts/` | everyone (change only together) | v1 schema + fixtures, validated |
| `ml/` → `fitness_ml` | Chase | MediaPipe pipeline, rep counting, form checks, training CLI ([`ml/README.md`](ml/README.md)); **not yet run on real video, no trained model** |
| `backend/` → `gymai_backend` | Tyler | session state machine, REST, WebSocket, fixture simulator; minimal coaching |
| `ios/` | Bryan | `GymAndAIKit` Swift package (contract + networking); **Xcode app project not created yet** → [`ios/README.md`](ios/README.md) |
| `firmware/` | Taher | serial protocol + README; **no drivers** until hardware is identified |
| `assets/audio/` | Tyler | cue naming rules; no audio yet |
| `demo/` | everyone | clip/log rules |

## Setup (laptop)

Python 3.11 or 3.12 (MediaPipe doesn't ship for 3.13+ reliably).

```bash
python3.11 -m venv .venv
```

```bash
.venv/bin/pip install -e backend -e ml
```

Vision + training extras: `.venv/bin/pip install -e 'ml[train,dev]'`, then `.venv/bin/fitness-ml download-model`. GPU training runbook: [`docs/VULTR_TRAINING.md`](docs/VULTR_TRAINING.md).

## Verify everything

```bash
.venv/bin/python contracts/validate.py
```

```bash
.venv/bin/python -m gymai_backend.simulate
```

```bash
.venv/bin/python -m fitness_ml sample | .venv/bin/python contracts/validate.py --stdin observation
```

```bash
cd ios/GymAndAIKit && swift test
```

## Run the backend + mock workout

```bash
.venv/bin/uvicorn gymai_backend.app:app --host 0.0.0.0 --port 8000
```

In a second terminal, replay a fixture slowly into session `demo` (the phone subscribes to `ws://<laptop>:8000/ws/workout?session_id=demo`):

```bash
.venv/bin/python -m gymai_backend.simulate --url http://localhost:8000 --session demo --delay 0.7 contracts/fixtures/corrected_issue.json
```

Re-running needs a new `--session` name (sessions are in memory; restart the server to clear). Interactive API docs: `http://localhost:8000/docs`.

Optional LAN secret: start uvicorn with `GYMAI_TOKEN=<something>` in the environment; the simulator and app then send it automatically / via settings.

## Connect a physical iPhone

1. Put the laptop and phone on the same network. Event Wi-Fi often isolates clients — if the phone can't reach `http://<laptop-ip>:8000/health` in Safari, use a phone hotspot (or another permitted private network) instead.
2. Find the laptop IP: `ipconfig getifaddr en0` (macOS). Enter it in the app's backend-host setting; it is never hardcoded.
3. macOS may ask to allow incoming connections for Python — allow it (System Settings → Network → Firewall).
4. First connection, iOS asks for **Local Network** permission — allow it. If you denied it: Settings → Privacy & Security → Local Network → Gym&AI.
5. The app uses `NSAllowsLocalNetworking` for `http`/`ws` to LAN hosts; we do not disable App Transport Security globally.

## Ground rules

- The backend alone commits reps; everything else displays them.
- Mock data is labelled `inference_provenance: "fixture"`; recorded clips are labelled RECORDED. Don't present either as live.
- No raw video, datasets, model weights, health data or API keys in git (see `.gitignore`).
