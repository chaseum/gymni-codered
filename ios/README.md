# Gym&AI iPhone app

Open **`GymAndAI.xcodeproj`**, select the **GymAndAI** scheme, choose an iPhone simulator, and run. The project links the existing local `GymAndAIKit` package. It targets iOS 17+ and uses Swift 6, tested with the installed Xcode 26.4 toolchain. No additional Swift frameworks need installing.

For a physical iPhone, select your development team in Signing & Capabilities and choose a unique bundle identifier. No team or signing secrets are committed.

## Implemented first slice

- Today, exercise selection/plan details, settings, and a lightweight last-session Progress screen.
- Demo → simulated positioning → workout → explicit pause/rest → resume → recap.
- **Reps | Camera** display switch. Both views share the same session, coach caption, and controls. Switching never changes the count or session state.
- Camera opens edge to edge in landscape. Apple Watch heart rate sits at the upper left, completed/target reps at the upper right, and coaching plus Reps/Mute/Pause/End controls overlay the bottom. Returning to Reps, rest, or recap restores portrait. The video preserves its aspect ratio so joints are not cropped to fill the screen.
- The Watch tile displays BPM only for `apple_watch` samples marked live and timestamped within ten seconds. Missing, stale, or unrelated-source samples show Unavailable. The Watch bridge still needs implementing.
- Demo mode produces explicitly simulated contract events. It never measures movement or heart rate. Its 15-second rest timer is shortened for demonstration, and expiry never resumes the workout.
- Laptop mode attaches to an existing backend session, displays its snapshots/events, and sends acknowledged start/rest/resume/extend/end commands. It never increments reps locally. Failed/rejected actions remain visible; reconnects resynchronize from a snapshot.
- Optional external webcam **MJPEG preview**. Missing or stale video has an explicit unavailable state. Preview parsing runs away from the main actor with bounded frame buffering. The preview does not perform inference.
- Spoken captions use native speech synthesis; generated dynamic corrections use ElevenLabs MP3 audio from the laptop backend when enabled. Both use temporary audio ducking. Audio can be muted; current cues stop on pause/end.
- Dynamic Type, scrolling layouts, labeled controls, and touch targets of at least 44 points.
- Native Liquid Glass on iOS 26+: Watch/rep tiles and the floating coach caption use regular glass; primary buttons use lime-tinted glass and secondary buttons use neutral glass. Camera controls sit directly over the video, with no enclosing glass panel. Reduce Transparency uses opaque tiles and standard buttons; older iOS versions use material tiles and standard buttons. The deployment baseline stays iOS 17.
- Settings → Apple Health → **Connect Apple Health** requests permission to read heart rate through the native HealthKit sheet. It requests no write permission, reads no samples, and sends no health data to the laptop. Completion is reported as “Permission request finished”; HealthKit does not reveal denial of read access. Errors and unavailable-device states remain visible.
- Pip replaces the drawn Octobuddy with a bundled 3D USDZ rendered in RealityKit's non-AR mode. It animates while coaching speaks, rests on pause, and celebrates at recap. Tap Pip on Today for a brief celebration.

## Connect the laptop

### macOS Simulator: one-command live demo

On the Mac, install the Python packages, make sure the ignored model bundle exists at `ml/models/`, and run:

```bash
python3.11 -m venv .venv
.venv/bin/pip install -e 'backend[dynamic-cues]' -e 'ml[gru]'
if [ ! -f .env ]; then cp .env.example .env; fi
# Add GEMINI_API_KEY, ELEVENLABS_API_KEY, and ELEVENLABS_VOICE_ID to .env
bash scripts/run_simulator_demo.sh curl
```

The script selects an installed iPhone Simulator (or use the optional second argument to choose a name), starts the backend, creates a session, builds and opens the iOS app, attaches it to that session, and starts live webcam inference. On first use, allow camera access for the terminal running the script. Close the model window with `q` to stop the model and backend. Examples: `bash scripts/run_simulator_demo.sh curl` or `bash scripts/run_simulator_demo.sh squat "iPhone 16"`. The dynamic cue flag is enabled for this demo; provider failures fall back to the approved fixed cue and native speech.

If you prefer manual control, start the backend:

```bash
python -m uvicorn gymai_backend.app:app --app-dir backend --host 0.0.0.0 --port 8000
```

Then in a second terminal create a session and start model inference:

```bash
python -c "import httpx; print(httpx.post('http://localhost:8000/api/sessions', json={'session_id':'phone-demo'}).json())"
python -m fitness_ml run --source live --exercise curl --post http://localhost:8000 --session phone-demo
```

For a physical iPhone, select **Laptop** in Settings and enter the laptop's LAN URL and session ID. The phone and laptop must be on the same trusted network. If using `GYMAI_TOKEN`, configure it in the app as well. Local Network permission and `NSAllowsLocalNetworking` are configured; arbitrary network loads are not globally enabled.

Choose the exercise and Live webcam/Recorded input in View plan, then Start workout. When attaching to an already active/paused/completed session, its state is preserved. The phone does not create or start a second set automatically.

Drive observations using the ML CLI documented in `../ml/README.md`. For a fixture replay, clearly describe that the connected backend input is simulated: `source=live` alone does not establish that an observation came from real inference.

## Camera integration contract

Settings accepts an optional HTTP(S) MJPEG URL. The publisher must return status 200 and `Content-Type: multipart/x-mixed-replace; boundary=...`, followed by JPEG parts. Use the same participant, source, and webcam frames as the active analyzer; retain the Recorded label for prerecorded footage.

**The current FastAPI backend does not publish this feed.** Tyler/Chase should add publishing to the existing capture pipeline rather than opening the camera from a second process. Until then Laptop Camera view honestly shows unavailable. The app does not access the phone camera. Preview authorization is not implemented; use only a permitted trusted local feed for this prototype. Backend tokens are never forwarded to a separately configured preview host.

The preview connection starts when Camera view is visible, stops when it leaves, and reconnects on returning. This affects video display only. Analysis, rep counting, and coaching continue on the laptop.

## Validation

```bash
cd ios/GymAndAIKit
swift test
```

From the repo root:

```bash
xcodebuild -project ios/GymAndAI.xcodeproj -scheme GymAndAI \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -derivedDataPath ios/DerivedData CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
```

Tests cover contract decoding/deduplication, display switching preserving session state, cancellation of delayed demo starts, rest expiry requiring explicit resume, stale/missing heart rate, bounded multipart parsing, the native workout journey, landscape/portrait transitions, corner overlay placement, and large-text control access.

Simulator tests use local ad-hoc signing so HealthKit receives its entitlement. `HealthAccessTests` verifies the Settings permission flow and neutral completion after declining access. Apple may omit the sheet on later runs when the choice is already recorded.

`LaptopConnectionTests` runs against a local backend on port 8000 and skips when it is unavailable. It creates an isolated test session, sends a recorded fixture observation, checks the displayed rep event, and exercises actual REST/WebSocket pause/resume/end. It does not measure ML accuracy or capture a camera.

Simulator screenshots are saved under `../docs/design/native/` and the updated mockup views under `../docs/design/`.

## Apple Health permission setup

The iPhone target uses `GymAndAI/GymAndAI.entitlements` with HealthKit enabled. The read/write purpose descriptions are in `GymAndAI-Info.plist`; the write description is reserved for later workout saving.

Run the app, open Settings, and tap **Connect Apple Health**. On the native sheet, choose Heart Rate access and finish. If you previously answered, Apple may complete without showing another sheet; review Gym&AI’s permissions in the Health app to change your choice. A completed request does not prove read access was granted and does not start live Watch delivery.

One HealthKit store is owned by the app's root state and retained across Settings presentations. The permission flow uses `HKHealthStore.requestAuthorization(toShare: [], read: [HKQuantityType(.heartRate)])` after checking availability. It never automatically asks at launch.

## Music during coaching

Native speech announcements use the system-managed speech audio session. ElevenLabs MP3 cues use a temporary playback session with ducking; both stop on pause, mute, or end. No long-lived ducking session is activated for the workout.

To check on a physical iPhone:

1. Start music in Apple Music or Spotify on that iPhone, using the phone speaker or connected AirPods.
2. Open Gym&AI, leave Spoken coaching enabled, and start a Demo workout to hear a native speech announcement. For ElevenLabs, connect Laptop mode and use a session that produces a supported correction with its generated cue MP3 available.
3. Check that music becomes quieter while the cue is audible, then returns afterward.
4. Mute the coach while a cue is playing and verify speech stops and music returns. Pause/end should cancel the current cue; their short transition announcement may then duck music again.
5. Switch Reps/Camera and confirm no extra announcement or music interruption occurs just from switching views.

iOS determines the ducking amount. Music playing on a separate device is outside this mechanism. Real music playback and AirPods routing require physical-device verification; a Simulator journey test does not verify audible ducking.

Reference: [Apple's speech audio-session documentation](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/usesapplicationaudiosession).

## ElevenLabs spoken correction cues

The approved correction phrases can be generated ahead of time with ElevenLabs and saved as MP3s under `assets/audio/`. The phone downloads and plays the matching file from the laptop; missing files fall back to native iPhone speech. Normal session start, pause, and status announcements continue to use native speech. Dynamic mode is optional: Gemini rephrases only the backend-approved action, ElevenLabs voices it, and the laptop serves the resulting MP3 to the phone.

Install the optional providers and configure the project-root `.env` with `ELEVENLABS_API_KEY` and `ELEVENLABS_VOICE_ID`:

```bash
python -m pip install -e 'backend[audio]'
python generate_audio.py
```

For dynamic cues, install `backend[dynamic-cues]`, configure `GEMINI_API_KEY`, set `GYMAI_DYNAMIC_CUES=1` in `.env`, and restart the backend. The first time each approved issue/action is used with a selected Gemini model, ElevenLabs model, and voice, the backend generates and caches one MP3 under `assets/audio/dynamic/`. Later occurrences reuse that clip without another Gemini or ElevenLabs call. The short Gemini request contains only the approved action (no user profile or movement measurements), caps output at 24 tokens, and falls back to the fixed approved cue if a provider is unavailable or times out. Keep provider keys on the laptop; the iPhone only downloads MP3s from the configured backend.

## Next integration work

- Build the personalized-planning path: goal interview and profile editing, deterministic filtering/validation from the reviewed exercise catalog, plan acceptance/versioning, then launch sessions from the accepted plan. Current Gemini and Backboard endpoints provide coach chat and user-confirmed memories; they do not yet create or accept plans.
- Generate ElevenLabs cue assets using the selected voice, confirm its redistribution terms, and keep the files local unless redistribution is allowed.
- Add narrow phone speech commands and publish/validate the optional live webcam preview.
- Watch heart-rate forwarding is deferred until a later integration pass. iPhone HealthKit permission is present, but live HR is unavailable without a real sample path.
- Tiger persistence is deferred until account/login work defines stable user identities; profile IDs are currently demo identifiers.
- Test physical iPhone/AirPods, event-network behavior, and preview latency using the real hardware.

Skills used: `code-tips-skill` and `swiftui-pro`. Deployment/toolchain settings follow the existing package and installed SDK rather than unsupported newer APIs.

## Animated Pip

Pip is the first of three planned companions. Its editable source is `../docs/design/models/pip/pip.blend`; run `blender --background --python scripts/build_pip.py` from the repository root to rebuild the model, reflection environment, and transparent preview.

`PipView(state:)` accepts Ready, Coaching, Celebrating, or Resting. Its RealityKit scene uses no AR session or camera permissions. Parts move independently without a skeletal rig. Speech activity comes from the native synthesizer's start/finish/cancel/pause/continue delegate callbacks; obsolete callbacks cannot override a newer utterance. Muting, leaving the workout, and backgrounding stop current speech.

USDZ and reflection resources load asynchronously and are shared as immutable source assets; each visible mascot gets its own entity clone. Hidden/backgrounded views dismantle the scene and cancel its update subscription. Failed model loading uses the bundled transparent preview. Reduce Motion retains a neutral 3D pose and cancels movement updates.

`PipMascotTests` checks model loading, tapping and returning to idle, static fallback, Reduce Motion, background/tab restoration, and rest/recap navigation. Debug-only `-PipForceFallback` and `-PipReduceMotion` arguments exercise those branches. Existing workout journey checks still cover camera/reps switching, orientation, and large-text control access.

Before judging, run on a physical iPhone and check: glossy appearance, idle/ring movement, speech-linked gestures ending on mute, rest/resume/recap, Reduce Motion, background/foreground restoration, and performance alongside the real video feed. Music/AirPods ducking needs the existing manual audio check. No physical device was connected during this implementation.
