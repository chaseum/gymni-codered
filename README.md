# gymni-codered
repo for codered orion 2026

**Gym&I**: an iPhone-first, hands-free fitness coach. The laptop webcam is the vision sensor (Python + MediaPipe), a FastAPI backend on the laptop owns the session, and the SwiftUI iPhone app (plus Watch HR, plus a Pico button/display) renders the backend's state. Plan: [`GYM_AND_AI_TEAM_BRIEF_REVISED.md`](GYM_AND_AI_TEAM_BRIEF_REVISED.md). Wire protocol: [`contracts/protocol.md`](contracts/protocol.md).

Shared planner exercise data and healthy-adult prescription notes: [`contracts/exercise_catalog.json`](contracts/exercise_catalog.json) and [`docs/exercise_catalog.md`](docs/exercise_catalog.md).

Model handoff and integration contract: [`docs/GYM_AND_I_MODEL_HANDOFF.md`](docs/GYM_AND_I_MODEL_HANDOFF.md).

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

## Gemini coach setup

Gemini generates conversational coach replies directly. Backboard stores and
searches user-confirmed profile memories; it does not generate coach replies.
Both API keys stay on the FastAPI server; do not put them in the iOS app or
commit them.

1. Create or copy a Gemini API key from [Google AI Studio](https://aistudio.google.com/app/apikey).
2. Copy `.env.example` to `.env` if you have not already, and add the key:

   ```dotenv
   GEMINI_API_KEY=your_key_here
   GEMINI_MODEL_ID=gemini-3.5-flash-lite
   BACKBOARD_API_KEY=your_backboard_key_here
   ```

   The project-root `.env` is ignored by git. The backend reads it at startup.
3. Install the backend dependencies if needed:

   ```bash
   python -m pip install -e backend
   ```

4. Start the backend as above, then send a first message:

   ```bash
   curl -X POST http://localhost:8000/api/coach/messages \
     -H "Content-Type: application/json" \
     -d '{"message":"I want to get stronger and can train three days a week.","profile_id":"tyler-demo"}'
   ```

   PowerShell equivalent:

   ```powershell
   curl.exe -X POST http://localhost:8000/api/coach/messages -H "Content-Type: application/json" -d '{"message":"I want to get stronger and can train three days a week.","profile_id":"tyler-demo"}'
   ```

   The response contains `reply` and `thread_id`. Send that `thread_id` with
   each follow-up message to continue the same conversation:

   ```json
   {"message":"I have dumbbells and a bench.","thread_id":"THREAD_ID_FROM_RESPONSE","profile_id":"tyler-demo"}
   ```

Pass a stable, opaque `profile_id` in coach requests to enable memory. The first
request for a profile creates its Backboard assistant automatically and stores
the profile-to-assistant mapping in `~/.gymai/profile_assistants.sqlite3`.
Different profile IDs get separate assistants and memories. The current API has
no user sign-in, so treat these IDs as local-demo identifiers until the app
adds authenticated accounts.

Only save a fact after the user explicitly chooses to remember it. For example,
save one with:

```powershell
Invoke-RestMethod -Uri http://localhost:8000/api/coach/profiles/tyler-demo/memories -Method Post -ContentType "application/json" -Body '{"content":"I train three days a week and prefer dumbbell workouts."}'
```

Then include the same profile ID in a coach request. Gym&I searches that
profile's Backboard memories and passes matching facts to Gemini. Saved facts
can be reviewed with `GET /api/coach/profiles/{profile_id}/memories` and removed
with `DELETE /api/coach/profiles/{profile_id}/memories/{memory_id}`. Conversation
history is still held in backend memory and clears when the server restarts;
Backboard profile memories persist independently. The planner and workout
validation remain separate from this conversational endpoint.

## Connect a physical iPhone

1. Put the laptop and phone on the same network. Event Wi-Fi often isolates clients — if the phone can't reach `http://<laptop-ip>:8000/health` in Safari, use a phone hotspot (or another permitted private network) instead.
2. Find the laptop IP: `ipconfig getifaddr en0` (macOS). Enter it in the app's backend-host setting; it is never hardcoded.
3. macOS may ask to allow incoming connections for Python — allow it (System Settings → Network → Firewall).
4. First connection, iOS asks for **Local Network** permission — allow it. If you denied it: Settings → Privacy & Security → Local Network → Gym&I.
5. The app uses `NSAllowsLocalNetworking` for `http`/`ws` to LAN hosts; we do not disable App Transport Security globally.

## Ground rules

- The backend alone commits reps; everything else displays them.
- Mock data is labelled `inference_provenance: "fixture"`; recorded clips are labelled RECORDED. Don't present either as live.
- No raw video, datasets, model weights, health data or API keys in git (see `.gitignore`).
