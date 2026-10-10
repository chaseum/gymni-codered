# Gym&AI — Revised 24-Hour Hackathon Team Brief

**Revision:** 2026-10-10. Supersedes the attached `GYM_AND_AI_TEAM_BRIEF.md` for architecture, ownership, ML training, and the iPhone experience. Preserves the original's validated safeguards and three-exercise demo plan.

**Team:** Chase, Bryan, Tyler, Taher (four people; check event team-size rules independently).

## 1. Product and design direction

**Product:** An iPhone-first, hands-free fitness coach that observes exercises via an external webcam, counts repetitions, identifies supported movement issues, and intervenes with brief spoken guidance. It logs exercise/load/reps, celebrates actual personal bests, and accepts explicit effort, pause, and rest requests. The Apple Watch supplies opt-in live heart-rate data. A Raspberry Pi Pico is a physical control/display accessory, not a vision processor.

**Design references, not assets to copy:** Muse/Dots for a proactive, compact AI companion and contextual activity feed; Apple Fitness for large readable workout metrics, familiar native controls, and useful recap; Wii Fit for friendly nonjudgmental feedback. Build an original visual language, not an Apple Fitness clone, and do not repurpose Apple's Activity rings as a form score.

**Primary iPhone UI:** Native SwiftUI iPhone app. No React dashboard as a required second client. A simple desktop debug window may be used for computer-vision troubleshooting. SwiftUI watchOS companion is a separate target in the same Xcode project where practical.

### UX specification

- **Today:** contextual coach greeting, today's goal-based routine, last workout/PR context, device connection indicators, prominent Start Workout action. Avoid persistent chat feed as the primary UI.
- **Onboarding:** short AI goal interview or structured form: goal (strength, muscle gain, consistency), experience, equipment, exercise variations, available days/time, preferences and movements to avoid. Show an editable interpreted profile and ask focused follow-ups for missing constraints.
- **Plan review:** assemble an individualized draft from reviewed catalog blocks and bounded parameter presets; show exercise order, sets/rep targets/rest, estimated duration, rationale, analysis-support labels, and Edit/Accept actions before starting.
- **Positioning:** selected exercise and exact view guidance; tracking ready/lost; explain whether input is LIVE or RECORDED; no high-frequency raw pose graph in normal UI.
- **Workout:** full-screen, glanceable active state. Most prominent: exercise name, completed reps, target, latest actionable coaching cue, pause/end. Secondary: set/load, tempo, heart rate with freshness, coach state. A tiny illustrated character/orb can change state (observing, correcting, encouraging, resting). Do not let decoration compete with metrics.
- **Rest:** explicit pause/rest state, timer (if configured), optional water reminder, and visible Resume/End actions. Timer expiry must never silently resume the session.
- **Recap/Progress:** real completed reps/sets/weight, one specific observation, recent comparable performance, and PRs only when recorded data supports them; optional next-session suggestion with user confirmation.
- **Visual system:** strong type hierarchy, generous whitespace, smooth restrained animations, original graphite/cream + mint/violet accent palette (or another internally consistent original palette), accessible contrast, Dynamic Type, reduced motion, light and dark appearance. Use SF Symbols and native controls. Avoid gratuitous glass, charts, flashing gradients, and copied Apple rings.
- **Input:** after Start, reps, cues, and recap operate automatically. Manual pause, stop, effort entry, and microphone access remain discoverable; narrow spoken intents are acceptable without an always-listening LLM.

### Personalized workout planning

**Confirmed addition:** Gym&AI gathers goals and creates a personalized workout. This is a separate component from MediaPipe and the live coaching policy. Use a hosted language model for goal extraction/follow-up questions and grounded explanations; a Python planner/validator controls the actual plan. No custom training is needed for this planning component.

Example: "I want to build muscle, I'm new, I have dumbbells, and I have twenty minutes three days a week." Extract those fields, ask about missing restrictions/preferences, and let the user correct the profile. Do not invent equipment, training loads, or missing answers. Voice can reuse the phone transcript path; form entry remains available.

**Flow:** confirmed profile -> filter reviewed catalog by equipment/experience/restrictions -> assemble goal-specific blocks -> validate parameters and total time including rest/transitions -> explain the final draft -> user accepts a plan version -> backend executes it. Equipment, goal, experience, time and preferences must change eligible selections or reviewed parameters where relevant; personalization must affect the workout, not just its title.

The model returns structured data. Backend validation rejects unknown exercise IDs, unavailable equipment, excluded movements, invalid parameters, and infeasible durations. If no feasible plan exists, explain the constraint and offer edits. On model timeout/invalid output, preserve the profile and use the deterministic form/planner path. Keep API credentials on the backend. Generate explanations from the validated result, and keep onboarding separate from workout command execution.

**24-hour deliverable:** a personalized, editable demo session. A full weekly program needs a broader reviewed catalog; squat/curl/deadlift alone do not establish balanced whole-body coverage. Catalog entries declare `analysis_supported`; manual/untracked movements cannot claim live form analysis. Bench press remains deferred. Report the plan's scope explicitly. Goal/experience influence training design, and general guidance includes strengthening all major muscle groups. [ACSM position stand](https://pmc.ncbi.nlm.nih.gov/articles/PMC12965823/), [HHS guidelines](https://health.gov/paguidelines/second-edition/pdf/Physical_Activity_Guidelines_2nd_edition.pdf).

The prototype does not generate rehabilitation or condition-specific plans. If restrictions cannot be met by the reviewed catalog, leave incompatible movements out and explain the limitation. Initial loads are user-confirmed. Later adaptation can propose changes from comparable workout history and reported effort, with explanation and acceptance; low HR or tracking confidence must not automatically raise intensity.

**Demo:** show two profiles with different equipment/time constraints, their different feasible drafts and reasons, accept one, then launch a clearly labeled shortened live curl set. See the original brief's personalized-planning section for the detailed pipeline; this revised brief remains authoritative for architecture and ownership.

## 2. Confirmed scope & hardware

- **Required exercise analyzers:** `curl` (standing dumbbell curl), `squat` (define bodyweight vs loaded variation explicitly), `deadlift` (conventional). Squat/deadlift recorded footage; curls live for judges and recorded for repeatability. Optional pushup only after all three work. Bench press deferred.
- **Vision input:** webcam connected to a laptop running Python + MediaPipe Tasks Pose Landmarker. Prerecorded clips enter the same inference pipeline with video timestamps. Camera feeds do not need to be streamed to the phone; show tracking status and optional lightweight preview only if useful.
- **Pico hardware:** Raspberry Pi Pico/RP2040, Grove button, accelerometer, ultrasonic sensor, Grove display. Identify exact models before wiring. Button and display first; optional range/mount-motion sensors only after integration. Pico exchanges USB serial JSON with laptop and does not run MediaPipe.
- **Audio:** ElevenLabs pre-generated approved cues stored locally; iPhone playback using AVAudioSession for headphones/AirPods when paired. Laptop speaker fallback. Voice recognition on iPhone for a small explicit vocabulary; avoid false triggers from coach audio.
- **Apple Watch:** actual HealthKit workout session and live builder; mirror/forward samples through paired iPhone to backend. Samples carry timestamp, source, session, and stale/missing state; do not imply the app can read arbitrary Watch HR in real time without running and permissioning a workout session.
- **Networking:** iPhone uses local-network REST + WebSocket to the laptop FastAPI backend. Verify event Wi-Fi device isolation; prepare trusted phone hotspot or permitted local-network fallback. Provide configurable laptop IP/host, device pairing, reconnect snapshots, and scope-appropriate LAN authorization. Configure iOS Local Network permission; do not globally disable App Transport Security in release configs.

## 3. Team ownership (one integration surface per owner)

| Owner | Primary responsibility | Acceptance |
|---|---|---|
| **Chase** | Python vision, MediaPipe, per-exercise features/rep counting, form-quality research, datasets and ML models | Webcam curl and 3 clips produce repeatable structured observations; trained predictions explicitly separate from rules |
| **Bryan** | **SwiftUI iPhone UI + lightweight watchOS target / HealthKit bridge**, goal interview/profile editing/plan review, app networking and mobile speech-command UI | iPhone simulator flows; edited profile produces accepted plan; physical iPhone connects to laptop; real Watch sample delivered or blocker documented |
| **Tyler** | FastAPI session/backend, personalized planner/validator and language-model boundary, WebSocket contracts, coaching policy, cached cue events, history/PR logic, integration | Feasible explained plans; one session authority; cue sent once; watch/voice normalized; coherent client state |
| **Taher** | Pico firmware, button/display, mount/enclosure, serial bridge validation; assists Bryan with Watch/iPhone device testing | A physical button changes session; display mirrors committed reps; physical hardware does not destabilize system |

**Do not give Bryan the React app plus native iOS/watchOS apps.** Bryan and Tyler should agree on schemas immediately; Taher helps test device deployment. If watchOS signing or HealthKit support blocks progress, record that as an integration result; do not pass mocked BPM off as live data.

## 4. Architecture and boundaries

```text
Webcam / MP4
    -> Python MediaPipe Tasks Pose Landmarker (laptop)
    -> temporal normalized features, rep state machines, exercise/form classifiers
    -> typed ML observations
    -> FastAPI authoritative session + coaching policy
         <-> iPhone SwiftUI (REST, WebSocket, speech intent, cue playback)
                <-> Apple Watch watchOS (HKWorkoutSession / mirroring)
         <-> Pico via USB serial (physical button / reps display)
         -> short-term history / user-entered load / PR events

iPhone goal interview / form -> structured profile
    -> backend reviewed catalog + personalized planner / validator
    -> explained draft on iPhone -> accepted plan version -> workout session

Offline training: videos -> same landmark/feature extractor -> CPU baseline
                  -> optional Vultr GPU temporal model -> portable model artifact
                  -> laptop inference (never dependent on live Vultr connection)
```

**Core rule:** ML emits observations and evidence; backend chooses whether/when to speak; SwiftUI renders backend state and plays approved cues. UI, Pico, and Watch do not independently increment reps or decide form quality.

## 5. Machine learning scope — not the same as pose estimation

1. **Pose:** current MediaPipe Tasks Pose Landmarker, camera source abstractions, preserved capture timestamps. Test `VIDEO` mode first; implement async live mode only if needed and measure dropped frames/latency. Estimate visibility per required joint; return `unassessable` if needed.
2. **Features:** subject-centered and scale-normalized landmarks, confidence masks, knee/hip/elbow angles, joint trajectory/velocity, rep phase and timing. State exactly whether angles are 2D image-plane or derived from estimated world landmarks; never confuse those with clinical measurements.
3. **Rep state machines:** separate configurations for `curl`, `squat`, `deadlift`; use entry/exit hysteresis and an explicit complete-cycle definition. Count one committed rep once. Handle tracking loss, pause, seek/replay and exercise switches.
4. **Exercise recognition:** train supervised classification on short temporal pose windows; classes are `curl/squat/deadlift/other`, with rejection/unknown state. Session plan is a prior/context, not proof of observed exercise. **Keep unsupported-class samples available** without implementing a form analyzer for them.
5. **Form classification:** per-exercise labels, participant-disjoint splits, and evaluation; distinguish binary good/bad quality from specific issue labels. Only issue a correction if a supported, measured criterion is met and independently reviewed on demonstration examples. Deadlift video landmarks do **not** prove spinal curvature, bracing, bar load, or injury risk.
6. **Rep tempo / difficulty:** changes in speed or range may warrant a supportive check-in, not automatic fatigue diagnosis. Heart rate likewise cannot certify technique or safe weight increases.
7. **Evaluation:** ground-truth count per clip, held-out people, confusion matrix, macro-F1/class support, false-cue rate, tracking-loss cases, latency and FPS on final laptop. Record model/dataset/feature versions. Never report invented metrics.

**Initial datasets to inspect, license-check, and map carefully:** MyDeadlift (side-view deadlift labeled form errors) and the Multi-View Fitness Exercise Dataset (squats, curls, among other exercises). Keep subject, video, camera view and variation metadata before windowing. A pretrained MediaPipe pose estimator is not the newly trained form classifier.

**Training strategy:** Start with CPU-friendly Random Forest/k-NN on temporal features and documented rule-based feedback. Optionally train a lightweight PyTorch temporal CNN/GRU on **the same subject-disjoint splits** using Vultr GPU. Export CPU-loadable artifacts. Provision cloud resources only after credits/pricing/availability are verified; stop/destroy GPU instances after retrieving artifacts. Raw video/model weights and credentials stay out of Git. External GPU training is not the live app backend.

## 6. Shared interfaces — freeze in first two hours

Use JSON schemas and fixtures checked into `contracts/`; Python and Swift implement these contracts consistently. Suggested IDs: `curl`, `squat`, `deadlift`; `live`, `recorded`; `ready`, `active`, `paused`, `complete`.

### Profile and plan contracts

- Profile: ID/version, goal, experience, equipment, days/week, minutes/session, preferences and avoided movements; unanswered fields explicit.
- Catalog: stable exercise/variation IDs, equipment, eligibility, movement groups, reviewed parameter bounds/presets, `analysis_supported`, instructions.
- Plan: ID/version, profile version, scope (`demo_session` or reviewed `weekly_plan`), ordered blocks, sets/targets/rest, estimated duration, rationale and validation status.
- Endpoints: `POST /api/onboarding/messages`, `PUT /api/profiles/{id}`, `POST /api/plans`, `POST /api/plans/{id}/accept`. Sessions reference the accepted plan version; profile edits create a new draft rather than silently changing an active session. Return `needs_input` or `no_feasible_plan` where appropriate.

### Analyzer -> backend (ML observation)

```json
{
  "schema_version": 1,
  "observation_id": "ml-00042",
  "session_id": "session-001",
  "set_id": "set-001",
  "source": "live",
  "source_timestamp_ms": 2400,
  "exercise": "curl",
  "exercise_confidence": null,
  "tracking_status": "ready",
  "phase": "lowered",
  "completed_rep": {"rep_index": 3, "duration_ms": 1850},
  "measurements": {"elbow_angle_deg": 157.0},
  "issues": [],
  "inference_provenance": "reviewed_rules"
}
```

`source_timestamp_ms` is relative to a capture/video time base and is **not** wall-clock epoch time. Backend events may additionally include epoch timestamps. Only send `completed_rep` upon transition into a newly completed valid cycle, not on every frame. Mark uncertain/unsupported values null or explicit unknown; confidence of pose detection is not form-quality confidence.

### Backend -> iPhone (authoritative event)

```json
{
  "schema_version": 1,
  "event_id": 42,
  "session_id": "session-001",
  "type": "rep.completed",
  "timestamp_ms": 1790000000000,
  "payload": {
    "exercise": "curl",
    "set_id": "set-001",
    "rep_count": 3,
    "target_reps": 8,
    "duration_ms": 1850
  }
}
```

Event types include `session.state`, `exercise.changed`, `tracking.status`, `rep.completed`, `feedback.issued`, `feedback.improved`, `coach.state`, `heart_rate.updated`, `user_feedback.acknowledged`, `rest.updated`, `set.completed`, `device.status`, and `history.pr_achieved`. Send state snapshot after reconnect and deduplicate by event ID. `rep.completed` is commit-once. Keep video out of events.

### iPhone/Watch -> backend

- Commands: `start`, `pause`, `resume`, `end`, `next_exercise`, `extend_rest` via one commands endpoint. Commands include ID/session/token and backend ack.
- Effort: `easy/moderate/hard`, explicit rest/water report, and recognized command with stable input ID; act only on final recognition result.
- Watch sample: unique sample ID, participant/session, `bpm`, original sample timestamp, receipt timestamp recorded by backend, `source=apple_watch`. Stale, missing, or unpaired HR is shown as unavailable. HR from a live presenter is never attached to another person in recorded footage.
- Load: weight and unit entered by user with associated exercise variation, set and rep range. PR comparisons use like-for-like units and definitions. No prediction of how much someone can **safely** lift.

### Laptop -> Pico

Newline JSON over USB serial: button intent -> backend, and backend state/count -> Pico. Bound sensor polling and tolerate reconnect. E.g. `{"event":"button_pressed"}` and `{"state":"active","exercise":"curl","reps":3}`. The Pico never adjudicates reps.

## 7. Coaching priority and safety

**Priority:** explicit stop/rest/pause > tracking not ready > persistent validated correction > meaningful effort check-in > observed PR/encouragement > optional water reminder. One audio scheduler; no overlapping cues; cancel stale cues on pause, correction resolution or set completion. Do not speak every rep. Ready-to-resume must be user-approved.

The coaching policy can say "You're one rep from matching your previous best at this weight" when the logged history proves it. It must not say "you can safely add 10 lb" solely from pose/HR. No universal heart-rate cutoff or dehydration detection. If user reports pain or dizziness, stop the session and encourage appropriate assistance instead of motivational pressure. Expose an opt-out for voice and HR.

## 8. Repository structure

```text
gym-and-ai/
  contracts/                 # typed schemas, JSON fixtures, protocol.md
  ml/                        # Chase: package, pose, features, classifier, reps, form
    src/fitness_ml/
    training/                # extraction, splits, train, eval
    models/                  # local artifacts ignored in git
    data/                    # downloaded datasets ignored in git
  backend/                   # Tyler: FastAPI, authoritative sessions, coaching
  ios/                       # Bryan: shared Xcode project, iPhone + Watch targets
    GymAndAI/                # SwiftUI iOS
    GymAndAIWatch/           # watchOS HealthKit companion
  firmware/                  # Taher: Pico firmware, serial protocol
  assets/audio/              # approved local cue files, where licensing permits
  demo/                      # validation logs, consented sample clips, backup
  docs/
  README.md
```

Do not create fake `.xcodeproj`/`.xcworkspace` files. Create a valid Xcode project using Xcode or a clearly documented generator, then build on the actual Mac/iPhone/Watch. Keep debug visualizations in `ml/` rather than constructing a second full React app.

## 9. Integration gates / 24-hour execution

| Hack time | Gate | Owners |
|---|---|---|
| 0–2 h | Freeze event contract, inspect real hardware, Python skeleton visible, SwiftUI simulator screens from fixtures, FastAPI WS client connects | All |
| 2–6 h | Live curl count/feedback; iPhone/laptop connection; Pico serial; Watch live HR path tested; two profiles produce different validated plans | Chase, Bryan, Tyler, Taher |
| 6–12 h | Squat/deadlift clip analysis; iPhone workout/rest/recap; voice cues and acknowledged commands; ML dataset ingestion starts | All |
| 12–18 h | End-to-end integration, three analyzers and live curls; baseline classifier measured; actual HR path or documented blocker | All |
| 18–22 h | Freeze features, check real-device latency / network fallback, rehearse physical demo, remove unsupported claims | All |
| 22–24 h | Record truthful demo, back up model/audio, verify launch/reset, submit and present | All |

Work in parallel with mocks. If GPU training is not ready, deploy the documented rule-based method and report the trained model as experimental, not production. At every gate preserve all three exercise configurations and continue toward a full pipeline; prioritize getting the data moving over speculative UI polish.

## 10. Demo acceptance and validation

- Real iPhone shows Today -> Start -> Positioning -> Workout -> Rest -> Recap.
- Planning: goal interview/form -> editable profile -> feasible explained draft -> acceptance. Different equipment/time profiles yield appropriate changes; unavailable equipment/restricted movements are excluded. Model failure falls back to the same planner through form entry. Profile edits do not rewrite an active plan.
- Webcam live curls: tracking status, accurate count against annotated repetitions, useful supported cue, response to changed movement, speaker/phone delivery, Pico display.
- Squat and conventional deadlift: labeled prerecorded inputs run through same analyzer, with demonstrated rep phases and at least one supported criterion each; no fabricated corrections.
- Watch: real timestamped samples or conspicuous unavailable state; spoken phone command and backend ack; stale data tests.
- Exercise recognition: if a trained model exists, show held-out evaluation and an unknown prediction path; no forced classification on unsupported exercise.
- Data: start new sessions cleanly, preserve per-set counts, log user-entered weight (if provided), distinguish actual PR from fabricated demonstration data.
- Resilience: network reconnect, pause/resume, device disconnect, source switch, low visibility, offline ElevenLabs playback, camera angle changes, unknown exercises, and no duplicate reps/cues.
- Recorded backups are clearly labeled, consented and contain outputs generated by the real inference pipeline.

## 11. Verified documentation / research references

- Google MediaPipe Tasks Pose Landmarker (Python): https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker/python
- Apple SwiftUI: https://developer.apple.com/swiftui/
- Apple workout design: https://developer.apple.com/design/human-interface-guidelines/workouts
- Apple Activity ring restrictions: https://developer.apple.com/design/human-interface-guidelines/activity-rings
- Apple HealthKit workout session mirroring: https://developer.apple.com/documentation/healthkit/hkworkoutsession/startmirroringtocompaniondevice(completion:)
- Apple Speech framework: https://developer.apple.com/documentation/speech/
- Apple local-network privacy: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- Vultr Cloud GPU: https://docs.vultr.com/product-overviews/cloud-gpu
- MyDeadlift: https://data.mendeley.com/datasets/w5prmmxyt9/1
- Multi-View Fitness: https://data.mendeley.com/datasets/kgbb3yn47p/3
- [ACSM 2026 resistance-training position stand](https://pmc.ncbi.nlm.nih.gov/articles/PMC12965823/)
- [HHS physical activity guidelines](https://health.gov/paguidelines/second-edition/pdf/Physical_Activity_Guidelines_2nd_edition.pdf)
