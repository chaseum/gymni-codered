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
- Spoken captions use native speech synthesis for this initial build. The synthesizer uses a separate system-managed audio session to mix/duck other iPhone audio during cues. Audio can be muted; current cues stop on pause/end. ElevenLabs cue assets are not bundled yet.
- Dynamic Type, scrolling layouts, labeled controls, and touch targets of at least 44 points.
- Native Liquid Glass on iOS 26+: Watch/rep tiles and the floating coach caption use regular glass; primary buttons use lime-tinted glass and secondary buttons use neutral glass. Camera controls sit directly over the video, with no enclosing glass panel. Reduce Transparency uses opaque tiles and standard buttons; older iOS versions use material tiles and standard buttons. The deployment baseline stays iOS 17.
- Settings → Apple Health → **Connect Apple Health** requests permission to read heart rate through the native HealthKit sheet. It requests no write permission, reads no samples, and sends no health data to the laptop. Completion is reported as “Permission request finished”; HealthKit does not reveal denial of read access. Errors and unavailable-device states remain visible.
- Pip replaces the drawn Octobuddy with a bundled 3D USDZ rendered in RealityKit's non-AR mode. It animates while coaching speaks, rests on pause, and celebrates at recap. Tap Pip on Today for a brief celebration.

## Connect the laptop

Start the backend from the repository root (after installing the existing Python dependencies):

```bash
python -m uvicorn gymai_backend.app:app --app-dir backend --host 0.0.0.0 --port 8000
curl -X POST http://localhost:8000/api/sessions \
  -H 'Content-Type: application/json' \
  -d '{"session_id":"phone-demo"}'
```

In app Settings, select **Laptop**, enter the backend URL and existing session ID, and supply the token if the server uses `GYMAI_TOKEN`. Simulator uses `http://localhost:8000`; a physical iPhone needs the laptop's address on the same trusted LAN. Local Network permission and `NSAllowsLocalNetworking` are configured; arbitrary network loads are not globally enabled.

<<<<<<< Updated upstream
Choose the exercise and Live webcam/Recorded input in View plan, then Start workout. When attaching to an already active/paused/completed session, its state is preserved. The phone does not create or start a second set automatically.
=======
1. Xcode → File → New → Project → **iOS App**. Set the displayed product name to `Gym&I` and the Swift target name to `GymAndI`; choose SwiftUI, Swift, and no Core Data. Save it **in `ios/`**, so you get `ios/GymAndI.xcodeproj` and `ios/GymAndI/`. Leave "Create Git repository" unchecked (we're already in one).
2. File → New → Target → **watchOS → App**, name `GymAndIWatch`, "Watch App for Existing iOS App" → `GymAndI`.
3. File → Add Package Dependencies → **Add Local…** → `ios/GymAndAIKit`. Link the `GymAndAIKit` library to **both** targets.
4. iPhone target → Info:
   - `NSLocalNetworkUsageDescription` = "Gym&I connects to the coach running on your laptop."
   - `NSAppTransportSecurity` → `NSAllowsLocalNetworking` = YES (allows plain `http://`/`ws://` to LAN hosts only. Do **not** set `NSAllowsArbitraryLoads`).
   - `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` when voice commands are added.
5. Watch target → Signing & Capabilities → **HealthKit**; Info: `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`; Background Modes → Workout processing. iPhone target also gets HealthKit if it receives mirrored sessions.
6. Signing: pick your personal/team account for both targets; set a unique bundle id prefix (e.g. `com.<you>.gymandi`).
7. Build and run on the iPhone simulator, then on device. Commit `ios/GymAndI.xcodeproj` + sources (`xcuserdata/` is git-ignored).
>>>>>>> Stashed changes

Drive observations using the ML CLI documented in `../ml/README.md`. For a fixture replay, clearly describe that the connected backend input is simulated: `source=live` alone does not establish that an observation came from real inference.

## Camera integration contract

<<<<<<< Updated upstream
Settings accepts an optional HTTP(S) MJPEG URL. The publisher must return status 200 and `Content-Type: multipart/x-mixed-replace; boundary=...`, followed by JPEG parts. Use the same participant, source, and webcam frames as the active analyzer; retain the Recorded label for prerecorded footage.

**The current FastAPI backend does not publish this feed.** Tyler/Chase should add publishing to the existing capture pipeline rather than opening the camera from a second process. Until then Laptop Camera view honestly shows unavailable. The app does not access the phone camera. Preview authorization is not implemented; use only a permitted trusted local feed for this prototype. Backend tokens are never forwarded to a separately configured preview host.

The preview connection starts when Camera view is visible, stops when it leaves, and reconnects on returning. This affects video display only. Analysis, rep counting, and coaching continue on the laptop.

## Validation

```bash
cd ios/GymAndAIKit
swift test
=======
@main struct GymAndIApp: App {
    // Host comes from user settings (e.g. @AppStorage "backendHost"), never hardcoded.
    @State var store = WorkoutStore(baseURL: URL(string: "http://192.168.1.20:8000")!, sessionId: "demo")
    var body: some Scene {
        WindowGroup {
            VStack {
                Text(store.snapshot?.exercise?.rawValue.capitalized ?? "—").font(.largeTitle.bold())
                Text("\(store.snapshot?.repCount ?? 0)").font(.system(size: 96, weight: .bold, design: .rounded))
                Text(store.lastFeedback?.text ?? "")
                Button("Pause") { Task { try await store.send(.pause) } }
            }
            .task { store.connect() }
        }
    }
}
>>>>>>> Stashed changes
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

`CoachAudioPlayer` sets `AVSpeechSynthesizer.usesApplicationAudioSession = false` before speaking. Apple then owns a separate session that manages speech, interruptions, mixing, and ducking with other audio sources. The app does not activate a long-lived ducking session for the workout. This applies to native synthesized cues; future ElevenLabs audio-file playback needs its own temporary audio-session lifecycle.

To check on a physical iPhone:

1. Start music in Apple Music or Spotify on that iPhone, using the phone speaker or connected AirPods.
2. Open Gym&AI, leave Spoken coaching enabled, and start a Demo workout.
3. During the positioning/start cue, check that music becomes quieter while speech is audible, then returns afterward.
4. Mute the coach while a cue is playing and verify speech stops and music returns. Pause/end should cancel the current cue; their short transition announcement may then duck music again.
5. Switch Reps/Camera and confirm no extra announcement or music interruption occurs just from switching views.

iOS determines the ducking amount. Music playing on a separate device is outside this mechanism. Real music playback and AirPods routing require physical-device verification; a Simulator journey test does not verify audible ducking.

Reference: [Apple's speech audio-session documentation](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/usesapplicationaudiosession).

## Next integration work

- Publish and validate real webcam preview alongside the analyzer.
- Add ElevenLabs cue assets and narrow phone speech commands.
- Add the watchOS target and timestamped Watch workout samples. iPhone heart-rate permission is implemented; HR is currently unavailable unless the backend supplies an actual sample. The phone ages it locally and hides stale BPM.
- Connect the personalized planner and persist real workout history. The current plan is one chosen exercise/set, and Progress retains only the last session in memory.
- Test physical iPhone/AirPods, event-network behavior, and preview latency using the real hardware.

Skills used: `code-tips-skill` and `swiftui-pro`. Deployment/toolchain settings follow the existing package and installed SDK rather than unsupported newer APIs.

## Animated Pip

Pip is the first of three planned companions. Its editable source is `../docs/design/models/pip/pip.blend`; run `blender --background --python scripts/build_pip.py` from the repository root to rebuild the model, reflection environment, and transparent preview.

`PipView(state:)` accepts Ready, Coaching, Celebrating, or Resting. Its RealityKit scene uses no AR session or camera permissions. Parts move independently without a skeletal rig. Speech activity comes from the native synthesizer's start/finish/cancel/pause/continue delegate callbacks; obsolete callbacks cannot override a newer utterance. Muting, leaving the workout, and backgrounding stop current speech.

USDZ and reflection resources load asynchronously and are shared as immutable source assets; each visible mascot gets its own entity clone. Hidden/backgrounded views dismantle the scene and cancel its update subscription. Failed model loading uses the bundled transparent preview. Reduce Motion retains a neutral 3D pose and cancels movement updates.

`PipMascotTests` checks model loading, tapping and returning to idle, static fallback, Reduce Motion, background/tab restoration, and rest/recap navigation. Debug-only `-PipForceFallback` and `-PipReduceMotion` arguments exercise those branches. Existing workout journey checks still cover camera/reps switching, orientation, and large-text control access.

Before judging, run on a physical iPhone and check: glossy appearance, idle/ring movement, speech-linked gestures ending on mute, rest/resume/recap, Reduce Motion, background/foreground restoration, and performance alongside the real video feed. Music/AirPods ducking needs the existing manual audio check. No physical device was connected during this implementation.
