# Gym&I wire protocol — v1 (frozen)

Machine-checkable source of truth: [`gymai.schema.json`](gymai.schema.json). Fixtures: [`fixtures/`](fixtures/).
Python validates with `python contracts/validate.py`; the backend validates every request body against the same schema; Swift decodes the fixtures in `ios/GymAndAIKit` tests.

Changing a field = bump `schema_version`, update schema + fixtures + Swift mirror in one PR, tell all four owners.

## Core rules

1. **The backend alone commits reps.** ML reports `completed_rep`; UI, Pico and Watch display `rep_count` from `rep.completed` / snapshot and never add 1 themselves.
2. **Repeated frames never increment.** ML sets `completed_rep` only on the frame that completes a new cycle. `rep_index` is monotonic for the whole analyzer run (never reset, never reused); backend commits only `rep_index > max seen`, and dedupes `observation_id`.
3. **Retries are idempotent.** Commands dedupe on `command_id` (retry with the same id → same ack with `duplicate: true`, no new events). Heart-rate samples dedupe on `sample_id`. Clients dedupe events on `event_id`.
4. **Snapshot sync.** Every WebSocket connection starts with `session.snapshot`; its `event_id` is the last event id included in it. Apply it unconditionally, then apply only events with a larger `event_id`. Reconnect = reconnect and take the new snapshot; no replay protocol.
5. **Unknown is safe.** Receivers ignore unknown fields and unknown event `type`s. Missing sensors are explicit (`heart_rate.status: "unavailable"`, `bpm: null`), never zero or invented.
6. **Two clocks.** `source_timestamp_ms` (ML) is the capture/video clock (`time_base`: `capture_monotonic` for webcam, `video_pts` for MP4) — **not** epoch, restarts per clip. `timestamp_ms`, `sample_timestamp_ms`, `ends_at_ms` are Unix epoch milliseconds.
7. **Confidence ≠ safety.** `exercise_confidence` is recognition confidence only. Nothing in this protocol certifies form safety, safe load, fatigue or dehydration.
8. **Labels are honest.** `source: "recorded"` is shown as RECORDED in UI. `inference_provenance` is `reviewed_rules`, `trained_model` (with `model_version`) or `fixture` (mock data — never presented as real).
9. Rest timer expiry **never** resumes a session; only an explicit `resume` command does.

## IDs and enums

| Name | Values |
|---|---|
| exercise (analyzers) | `curl`, `squat`, `deadlift` |
| recognized exercise (ML only) | above + `other`, `unknown` |
| session state | `ready` → `active` ⇄ `paused` → `complete` |
| input source | `live` (webcam), `recorded` (MP4) |
| tracking status | `ready`, `low_visibility`, `lost`, `unassessable` |
| rep phase | `unknown`, `lowered`, `raising`, `raised`, `lowering` — position of the *moving load/body*: curl dumbbell down = `lowered`; squat bottom = `lowered`, standing = `raised`; deadlift bar on floor = `lowered`, lockout = `raised` |
| issue code | `<exercise>.<snake_case>`; backend only voices codes in its approved cue table (currently `curl.elbow_drift`, `curl.partial_range`, `squat.shallow_depth`, `deadlift.hips_rise_early` — Chase to confirm against measurable criteria) |
| coach state | `idle`, `observing`, `correcting`, `encouraging`, `resting` |

## 1. ML → backend: observation

`POST /api/sessions/{session_id}/observations` — body `$defs/observation`; response `{accepted, duplicate, ignored?}`.

| Field | Type | Notes |
|---|---|---|
| `schema_version` | `1` | |
| `observation_id` | string | unique per observation; dedupe key |
| `session_id` | string | must match URL |
| `set_id` | string \| null | informational; backend owns set ids |
| `source` | `live`\|`recorded` | |
| `clip_id` | string \| null | recorded clip name |
| `time_base` | `capture_monotonic`\|`video_pts` | |
| `source_timestamp_ms` | number ≥ 0 | see rule 6 |
| `exercise` | recognized exercise | analyzer/recognizer's view; backend commits reps only when it equals the session's planned exercise |
| `exercise_confidence` | 0–1 \| null | null when not from a classifier |
| `tracking_status` | tracking status | reps reported while not `ready` are not committed |
| `phase` | rep phase | |
| `completed_rep` | `{rep_index ≥1, duration_ms?}` \| null | one-time event, rule 2 |
| `measurement_basis` | `image_2d`\|`world_3d` | what the angles are; never clinical |
| `measurements` | `{name: number\|null}` | e.g. `elbow_angle_deg`, `knee_angle_deg`, `hip_angle_deg` |
| `issues` | `[{code, evidence?}]` | evidence = the measured values that triggered it |
| `inference_provenance` | `reviewed_rules`\|`trained_model`\|`fixture` | |
| `model_version` | string \| null | |

Observations while the session is not `active` are accepted and ignored (their `rep_index` is still consumed, so a rep done during pause never counts later).

## 2. Backend → phone: event envelope

`WS /ws/workout?session_id=…[&token=…]`; also `GET /api/sessions/{id}/events?after=N` (debug/catch-up) and `GET /api/sessions/{id}` (snapshot).

```json
{"schema_version": 1, "event_id": 42, "session_id": "session-001", "timestamp_ms": 1791640800000, "type": "rep.completed", "payload": {}}
```

`event_id` is a per-session integer starting at 1, strictly increasing. Payloads (full examples in `fixtures/catalog.json`):

| type | payload | emitted by scaffold backend? |
|---|---|---|
| `session.snapshot` | `state, source, exercise, set_id, rep_count, target_reps, tracking_status, heart_rate, rest, active_issues` | yes (first WS message) |
| `session.state` | `state, command_id?` | yes |
| `exercise.changed` | `exercise, set_id, target_reps` | yes (start, next_exercise) |
| `tracking.status` | `status, source` | yes (on change) |
| `rep.completed` | `exercise, set_id, rep_count, target_reps, duration_ms` — commit-once | yes |
| `coach.state` | `coach` | yes (minimal) |
| `feedback.issued` | `feedback_id, issue_code, cue_id, text, set_id, rep_count` — `cue_id` = audio file stem | yes (once per issue per set) |
| `feedback.improved` | `feedback_id, issue_code, set_id, rep_count` | yes |
| `heart_rate.updated` | `status (live\|stale\|unavailable), bpm, sample_id, sample_timestamp_ms, source` | yes |
| `rest.updated` | `status (resting\|ended), ends_at_ms` | yes |
| `set.completed` | `set_id, exercise, rep_count, load` | yes (end, next_exercise) |
| `user_feedback.acknowledged` | `input_id, kind (effort\|rest_request\|water\|pain), value` | schema only — Tyler |
| `history.pr_achieved` | `exercise, metric (reps_at_load\|max_load), value, previous_best, load` | schema only — needs real history |
| `device.status` | `device (camera\|watch\|pico\|phone), status` | schema only |

HR is `stale` when the sample was >10 s old on receipt or no sample arrived in the last 10 s. Clients should also age HR locally from `sample_timestamp_ms`.

## 3. Phone/Watch/Pico → backend: commands

`POST /api/sessions/{id}/commands`

```json
{"command_id": "uuid", "session_id": "session-001", "intent": "start", "origin": "phone",
 "args": {"exercise": "curl", "target_reps": 8, "source": "live", "load": {"value": 25, "unit": "lb"}}}
```

Intents: `start` (ready→active; args exercise/target_reps/source/load), `pause` (active→paused), `rest` (→paused + timer, `rest_seconds` default 60), `extend_rest` (+`rest_seconds`, default 30), `resume` (paused→active), `next_exercise` (closes set, new set with args), `end` (→complete).
Ack: `{"command_id", "accepted", "duplicate", "state", "error"}`; invalid transitions return `accepted: false, error: "invalid_transition:<state>-><intent>"` (HTTP 200).

## 4. Watch → (iPhone) → backend: heart rate

`POST /api/sessions/{id}/heart_rate`

```json
{"sample_id": "hr-0042", "session_id": "session-001", "participant_id": "p-chase", "bpm": 121, "sample_timestamp_ms": 1791640798500, "source": "apple_watch"}
```

`sample_timestamp_ms` is the HealthKit sample's own end date. Backend records receipt time itself. Never send a sample that did not come from HealthKit; when no Watch is running a workout session, send nothing and the UI shows unavailable. Live presenter HR is never attached to a recorded clip of someone else.

## 5. Pico ⇄ laptop: serial

Newline-delimited JSON over USB CDC, one object per line, UTF-8. See [`../firmware/SERIAL_PROTOCOL.md`](../firmware/SERIAL_PROTOCOL.md).

## Auth / network

Optional shared secret: start the backend with `GYMAI_TOKEN=…`; clients send `Authorization: Bearer …` (REST) or `?token=…` (WS). Unset = open; only acceptable on a trusted hotspot.

## Open decisions (flagged, not decided here)

- Final issue-code list and the measurable criterion for each (Chase, reviewed on demo clips).
- Squat variation (bodyweight vs goblet/loaded) — needed before squat thresholds mean anything.
- Who emits `device.status` for camera/Pico (the serial bridge owner, Tyler or Taher).
- Effort/voice input endpoint shape (`user_feedback.acknowledged` exists; request body not yet defined).
- Coaching priority queue (Tyler) replaces the scaffold's "one cue per issue per set" rule.
