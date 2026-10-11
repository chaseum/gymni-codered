# Claude Code Prompt 01 — Shared Boilerplate and Integration Contracts

You are the technical lead scaffolding **Gym&I**, an MLH hackathon fitness coach. Work inside the EXISTING repository. Four owners: Chase (Python CV/ML), Bryan (native SwiftUI iPhone/watchOS), Tyler (FastAPI backend/coaching), Taher (Raspberry Pi Pico hardware). Do not overwrite teammates' work or create an unrelated second application.

If `docs/GYM_AND_AI_TEAM_BRIEF_REVISED.md` exists, read it first. In case of conflict, prioritize the user instructions in this prompt and flag remaining decisions rather than silently changing requirements.

## Product

A native-feeling iPhone coach influenced by Muse/Dots' proactive assistance, Apple Fitness' readable workout UI, and Wii Fit's friendliness, without copying their graphics. The laptop webcam is the **vision sensor**. Python MediaPipe extracts 33 body landmarks; three exercise analyzers (`curl`, `squat`, `deadlift`) count reps and emit movement observations. A laptop FastAPI backend owns session and coaching state. The SwiftUI iPhone app subscribes over WebSocket, initiates/pause/resumes sessions, plays brief approved voice cues, shows Watch HR when genuinely available, and renders recap. The Watch companion sends opt-in live workout HR via iPhone; the Raspberry Pi Pico supplies a button/display over USB serial. Local inference continues if Vultr is unavailable.

## First inspect

1. Print a concise tree of the repo and identify existing tools/targets, current Git status, installed runtimes/Xcode, and ports.
2. Preserve current branches/files and ownership; do not rewrite or reformat unrelated code.
3. List conflicts/questions only when they actually prevent implementation.

## Scaffold **only missing** shared structure

```text
contracts/               # authoritative protocol.md, schema JSON, example events
ml/                      # Python installable package; Chase owns
backend/                 # FastAPI; Tyler owns
ios/                     # REAL Xcode SwiftUI iPhone+Watch targets; Bryan owns
firmware/                # Pico; Taher owns
assets/audio/             # nonsecret approved cue assets
docs/
demo/
README.md
```

**Do not generate empty placeholder files that pretend an Xcode project compiles.** If Xcode is unavailable here, produce Swift source scaffolds and exact Xcode creation instructions. If an app already exists, integrate into it.

## Freeze contracts first

Define versioned cross-platform event schemas with realistic fixtures and document exact fields/types:

- Exercise IDs: `curl`, `squat`, `deadlift`; `other`/`unknown` for recognition only.
- Session states: `ready`, `active`, `paused`, `complete`.
- Inputs: `live` webcam and `recorded` MP4, explicitly labeled.
- ML observation: `schema_version`, `observation_id`, `session_id`, `set_id`, source timestamp/time base, exercise ID, optional exercise confidence, tracking status, rep phase, **optional one-time completed rep event**, measurements, issue codes, evidence/provenance.
- Backend event envelope: monotonically increasing event ID, session ID, epoch timestamp, event type, payload. Include `session.state`, `exercise.changed`, `tracking.status`, `rep.completed`, `coach.state`, `feedback.issued`, `feedback.improved`, `heart_rate.updated`, `user_feedback.acknowledged`, `rest.updated`, `set.completed`, `history.pr_achieved`.
- Watch HR: sample ID, true sample time, BPM, source, session/participant ID; do not pass fabricated BPM as real.
- Phone commands: client command ID + session ID + intent (`start`, `pause`, `resume`, `end`, `rest`, `extend_rest`) and backend acknowledgement.
- Pico serial newline JSON: `button_pressed`, session state and committed rep count.

**Contract rules:** backend alone commits reps; repeated frames never increment the UI; deduplicate reconnect/retry; allow state snapshot sync; unknown fields and unavailable sensors handled safely; camera source timestamps are not wall-clock epoch times; classification confidence is not form safety confidence. Include fixtures for correct rep, missing tracking, explicit pause, unavailable Watch HR, recorded session, and corrected issue.

## Minimal runnable scaffolds

- Python `ml/` with `pyproject.toml`, importable package, config, structured model/observation types, stub video-source/pose/feature/rep/form/recognition interfaces, and offline model/training directories (ignored in Git). No fake trained model.
- Python `backend/` with `/health`, `POST /api/sessions`, commands route, session snapshot route, and `/ws/workout` with a small in-memory state machine and simulator fixtures. If equivalent server already exists, extend it rather than building another.
- SwiftUI app source structure documented in `ios/` for Bryan; only create a compiling app target if Xcode/project tooling is available. Define one networking protocol/typed model using the same contracts. iPhone is primary UI, not an embedded web page.
- `firmware/` contains `SERIAL_PROTOCOL.md` and a README for Taher, not fabricated board-specific drivers (sensor model is not yet verified).
- Root `.gitignore` preserves existing rules and adds environment files, private clips/health data, large datasets, model checkpoints, `.venv`, Xcode build artifacts, credentials.
- README includes exact commands for installing/launching Python components, mock event server, and steps to connect phone on a shared network or permitted hotspot. Document local-network iOS permission and configurable host, not a hardcoded laptop IP.

## Acceptance before stopping

1. Existing work remains intact (`git diff` reviewed).
2. The shared contract fixtures validate and a minimal backend exposes an actual WS event.
3. Python ML package imports and has a runnable entry point.
4. The iOS path is clear and buildable on Xcode-capable Mac; no fake `.xcodeproj`.
5. Each team's independent ownership is obvious.
6. List exactly what ran, failed, remains stubbed and the commands to verify it. Do **not** claim the ML, Apple Watch, or Pico integrations already work.

Implement the scaffolding and shared contracts only. Stop before training or extensive UI design; those are separate prompts.
