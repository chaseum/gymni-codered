# gymni-codered
repo for codered orion 2026

**Gym&I**: an iPhone-first, hands-free fitness coach. The Raspberry Pi runs the camera and movement model. The SwiftUI iPhone app owns counting, workout state, and local history. Vercel hosts the ElevenLabs voice gateway, Gemini conversation API, and Backboard memory integration. No laptop is required for a workout. Plan: [`GYM_AND_AI_TEAM_BRIEF_REVISED.md`](GYM_AND_AI_TEAM_BRIEF_REVISED.md). Wire protocol: [`contracts/protocol.md`](contracts/protocol.md).

Shared planner exercise data and healthy-adult prescription notes: [`contracts/exercise_catalog.json`](contracts/exercise_catalog.json) and [`docs/exercise_catalog.md`](docs/exercise_catalog.md).

Model handoff and integration contract: [`docs/GYM_AND_I_MODEL_HANDOFF.md`](docs/GYM_AND_I_MODEL_HANDOFF.md).

## Who owns what

| Path | Owner | Status |
|---|---|---|
| `contracts/` | everyone (change only together) | v1 schema + fixtures, validated |
| `ml/` → `fitness_ml` | Chase | MediaPipe pipeline, rep counting, form checks, training CLI ([`ml/README.md`](ml/README.md)); local trained artifacts are in ignored `ml/models/`; **not yet evaluated on real video** |
| `backend/` → `gymai_backend` | Tyler | stateless hosted ElevenLabs/Gemini/Backboard API, plus legacy laptop session tools; personalized plan API not implemented |
| `ios/` | Bryan | SwiftUI iPhone app, phone-owned Pi workouts/history, cached hosted voice, `GymAndAIKit` contracts/networking → [`ios/README.md`](ios/README.md) |
| `firmware/` | Taher | serial protocol + README; **no drivers** until hardware is identified |
| `assets/audio/` | Tyler | ElevenLabs phrase generation and local MP3 cue playback; correction files can be generated with `python generate_audio.py` |
| `demo/` | everyone | clip/log rules |

## Run the main app

See [Pi + iPhone + Vercel setup](docs/PI_IPHONE_VERCEL.md). The main app opens in Camera device mode, waits for real Pi observations, and uses ElevenLabs for spoken coaching. Normal workouts make zero Gemini calls. Demo and laptop flows are retained only for explicit test launch configurations.

## Legacy development setup (laptop)

Python 3.11 or 3.12 (MediaPipe doesn't ship for 3.13+ reliably).

```bash
python3.11 -m venv .venv
```

```bash
.venv/bin/pip install -e backend -e 'ml[gru]'
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

## ElevenLabs workout voice

The Laptop workout uses the project-root `.env` for `ELEVENLABS_API_KEY`,
`ELEVENLABS_VOICE_ID`, `ELEVENLABS_MODEL_ID`, `GEMINI_API_KEY`, and
`GEMINI_MODEL_ID`. Set `GYMAI_DYNAMIC_CUES=1` to enable it. Keys stay on the
Mac backend; the iPhone only downloads generated MP3 audio.

```bash
.venv/bin/pip install -e 'backend[dynamic-cues]'
.venv/bin/python -m gymai_backend.prepare_audio --exercise curl
bash scripts/run_simulator_demo.sh curl 'iPhone 17 Pro'
```

The simulator script prepares and caches the voice automatically. Coaching is
selected locally from measured reps: approved form corrections, relative pace
feedback, and occasional actual rep counts. This uses **zero Gemini tokens** by
default. ElevenLabs voices the selected text and start/pause/tracking messages;
its character usage occurs only when a clip is missing from the cache. Set
`GYMAI_REPHRASE_CUES=1` only if you want Gemini to rephrase each approved form
correction once and cache it. No frames, metrics, or workout history are sent
to Gemini for workout cues. Generated clips are
cached under the ignored `assets/audio/dynamic/` directory, keyed by text,
voice, and model so configuration changes generate fresh clips.

The app remembers the selected workout mode and laptop connection across
normal Xcode and Simulator launches. Running the script again updates it to
the new live session. Opening the app alone does not start the laptop camera
or backend; keep the script running for live reps and ElevenLabs audio.
An unavailable laptop shows a connection error; it never switches to Demo.
The script selects an already-booted matching simulator and also accepts a
device UDID as its second argument when several devices have the same name.

Demo and Phone modes keep device speech. A provider outage falls back to
device speech without stopping the workout; muting, pausing, losing tracking,
or leaving a workout cancels pending corrections. Allow Terminal camera
access when macOS asks before using live laptop tracking.

Each session saves an ignored JSON file under `demo/workouts/` (a hash of the
session ID names the file). The script prints its path. Inspect the current or
saved record through `GET /api/sessions/{session_id}/workout`. Each set contains
`target_reps`, `actual_reps`, `active_duration_ms` (excluding pause/rest),
`rep_work_ms` (sum of available positive rep durations), and a `reps` array
with one object per committed rep: original rep index, duration, source clock,
measurements, issue evidence, model provenance, and the selected coaching cue.
History survives backend restarts; an active session must still be started again.

`contracts/coaching_policy.json` controls the short phrases and pace thresholds.
Pace compares against the median of three opening, timed reps without reported
issues. Two consecutive reps below 70% or above 140% of that duration can trigger
a cue, with a six-second speech cooldown. This is a relative pace comparison,
not a prescribed ideal tempo. Missing timing, pause, tracking loss, changed input,
or clock reset prevent use of stale timing. Slower reps prompt an optional reset,
not pressure to speed up. Counts mark the first rep, halfway (even targets), two
remaining, and the target; form corrections take priority. Reaching the target
does not automatically end the workout. A new rep invalidates pending count audio.

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
