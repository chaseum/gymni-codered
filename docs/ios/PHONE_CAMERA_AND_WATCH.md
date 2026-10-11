# Real iPhone camera and Apple Watch setup

## What this build does

On a physical iPhone, Gym&AI starts in **iPhone** mode. Start workout, allow Camera access, position the phone, and tap **Start set**. The Reps/Camera switch changes the interface while capture continues. Camera view uses the live phone camera, fills the landscape screen, and shows heart rate at top left and rep status at top right. Flip camera changes between the front and rear cameras.

Video is previewed locally, not recorded, uploaded, or analyzed. **There is no rep or form model in this change.** The ML team’s model is still being trained. Phone reps remain unavailable, and the recap does not report zero as a measured count. Demo remains an explicitly simulated walkthrough; Laptop still receives the existing backend’s events and optional MJPEG feed.

Gym&AI now includes a `GymAndAIWatch` companion target. It runs an indoor strength-training `HKWorkoutSession` and `HKLiveWorkoutBuilder`, reads actual heart-rate samples, and sends timestamped `WatchTelemetry` over WatchConnectivity. The phone only displays valid readings from its current workout that are at most 10 seconds old. Application context carries the latest reading; old samples are not queued for later playback. No heart-rate data is sent to a server by this integration.

The camera stops on pause, end, dismissal, and backgrounding. Backgrounding a phone workout pauses it. Resume returns to positioning and requires an explicit Start set. Watch collection pauses/resumes with the phone, ends with the workout, and saves the Watch workout in Apple Health. End Watch tracking stops only Watch collection; the phone workout can continue.

## Install on actual hardware

1. Open `ios/GymAndAI.xcodeproj` in Xcode. Install watchOS platform support in **Xcode → Settings → Components** if requested.
2. In **Signing & Capabilities**, use your development team for **both GymAndAI and GymAndAIWatch**. Both have HealthKit entitlements. The Watch bundle identifier must remain the iPhone identifier plus `.watchkitapp`; `WKCompanionAppBundleIdentifier` must match the iPhone identifier. If changing the iPhone identifier, change all three together.
3. Connect and trust the iPhone, enable Developer Mode if Xcode asks, select the **GymAndAI** scheme and that iPhone, then Run. A computer-trust prompt authorizes development; it does not grant Health access.
4. On the paired iPhone’s **Watch** app, check that Gym&AI is installed. Use **Available Apps → Install** if necessary. If it is not listed or deployment fails, select the **GymAndAIWatch** scheme in Xcode and run it on the Watch paired to that exact iPhone. Follow Watch Developer Mode/trust prompts if Xcode requests them.
5. Open Gym&AI on the Watch at least once. Wear and unlock it. Do not run another workout app at the same time.
6. On iPhone, open Gym&AI Settings. Select **iPhone** mode and enable **Use Watch heart rate**. Refresh Watch connection. A paired Watch with no installed companion shows a specific installation message.
7. Start workout on iPhone. Allow Camera access on iPhone. Allow the Health permission prompts on **both devices**: heart-rate reading and workout saving. The Watch also requests permission to write the heart-rate samples collected with its workout.
8. The Watch should show “Waiting for a Watch sensor reading…” followed by real bpm. Tap **Start set** on iPhone. The phone shows bpm with sample freshness in Reps and landscape Camera views. Sensor readings may take several seconds; unavailable/stale data remains labeled as such.

The existing **Connect Apple Health** button requests read access on iPhone. It does not start a Watch sensor session. The Watch displaying bpm in Apple’s Heart Rate app also does not stream those readings into Gym&AI. The Gym&AI companion must be installed and running its own workout.

## If you still see no data

- **No Watch paired:** use the Watch paired to this specific iPhone. WatchConnectivity does not connect to a nearby friend’s Watch.
- **Install Gym&AI on Watch:** deploy the new companion target; reinstalling only an old iPhone build cannot collect live Watch heart rate.
- **Watch installed but unreachable:** open Gym&AI on the Watch and keep Bluetooth/Wi-Fi enabled. Tap **Start Watch tracking** on the iPhone positioning screen to retry launch.
- **Health permissions:** review Gym&AI in the Health app / Watch Health privacy settings, allow Heart Rate and Workouts, then use **Retry tracking** on Watch. Apple intentionally does not reveal whether read permission was granted; finishing its permission dialog is not evidence that readings are available.
- **Watch has readings but phone does not:** check matching phone/Watch installs, Watch connection status, sample freshness, and that neither app is paused. A reading older than 10 seconds is intentionally not shown as live.
- **Camera denied:** use **Open Settings** in the camera view and enable Camera. Return to the workout and resume. The simulator cannot provide this physical camera feed.

## Verification

Automated shared-library tests cover phone session lifecycle without simulated reps, Watch session identity, freshness, malformed readings, pause clearing, and out-of-order samples. UI tests cover the existing Demo journey and the simulator’s honest unavailable-camera path. Build both iOS and watchOS targets.

Physical acceptance checklist:

- Grant/deny Camera; front/rear previews; landscape rotation; Reps/Camera switch.
- Watch companion installation; each device’s permissions; actual bpm arriving on iPhone with freshness.
- Pause, Resume, End, End Watch tracking, and a second workout.
- Temporarily disconnect Watch; wait past 10 seconds; confirm no stale bpm appears live.
- Background/foreground iPhone; confirm camera stops and workout pauses.
- Confirm a completed Watch workout appears in Apple Health and no reps are fabricated.

Simulator or compile success does not verify camera hardware, real heart-rate delivery, provisioning, or Health permissions. If the iPhone app terminates unexpectedly, use **End Watch tracking** on the Watch to stop the workout; automatic crash recovery is not implemented yet.

## Integration points for the trained model

`PhoneCameraCapture` owns the serial capture queue and currently configures video input only. The ML team can add a video-data output and its approved inference adapter here later. `PhoneWorkoutSource` emits only lifecycle events; it never emits rep or form results. Connect actual results to the existing `WorkoutStore` event schema when the trained model is ready. Do not enable the Demo generator in iPhone mode.

Official references: [Apple workout sessions](https://developer.apple.com/documentation/healthkit/running-workout-sessions), [launch the paired Watch app](https://developer.apple.com/documentation/healthkit/hkhealthstore/startwatchapp(with:completion:)), [camera preview layer](https://developer.apple.com/documentation/avfoundation/avcapturevideopreviewlayer).

## Latest validation (2026-10-10)

- Shared package: 15 tests passed.
- Combined iOS + embedded watchOS physical-device build: passed.
- Signed build: passed; installed and launched on Chase’s connected iPhone.
- Watch simulator: companion installed, launched, and displays the waiting-for-iPhone screen.
- Existing Health authorization, four mascot checks, and two Demo workout journey checks passed. Laptop integration was skipped because the local backend was not running.
- The real Watch companion is visible under Available Apps in Chase’s Watch app. Installation and real heart-rate delivery require the wearer to install it and allow Health access. Hardware camera/heart-rate acceptance is still pending confirmation. The unavailable-camera UI test passed after preventing a preview layer from attaching to an unconfigured simulator camera.

### Watch development installation loop

The current signed Watch development profile includes only Chase’s iPhone, not the physical Watch. Installing from Available Apps returns to Install. Xcode lists the phone but no physical Watch. Make the Watch available to Xcode, enable Developer Mode on the Watch, accept its Trust prompt, then select the GymAndAIWatch scheme and physical Watch destination. Rebuild with automatic signing and device registration so its provisioning profile includes the Watch ID. This requires the Watch owner’s physical-device steps; a successful generic Watch build alone does not register the Watch.

[Apple Developer Mode instructions](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) and [automatic device registration](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices).

### Recheck on 2026-10-11

The owner confirmed the iPhone app works, but Watch installation still spins and returns to Install. Xcode's Devices window and the `GymAndAIWatch` scheme's destinations show Chase's connected iPhone but no physical Watch. Both matching local development profiles still list only the iPhone. This is evidence of an incomplete physical-Watch development setup; the exact installation rejection has not been captured.

1. Keep Chase's paired iPhone connected to the Mac and unlocked. Keep the Watch nearby, unlocked, with Bluetooth and Wi-Fi enabled.
2. Open **Xcode → Window → Devices and Simulators** and look for the paired Watch. Accept a computer-trust prompt on the Watch if it appears. Developer Mode may only become visible after development pairing is initiated.
3. On the Watch, open **Settings → Privacy & Security → Developer Mode**, enable it, restart, and confirm **Turn On**. Accept **Trust** if prompted.
4. Select the **GymAndAIWatch** scheme and the actual Watch destination in Xcode. Use the same team and automatic signing, then Run. Register the device if Xcode requests it. Selecting **Any watchOS Device** only builds the app; it does not install or register a Watch.
5. If the Watch remains absent or unavailable, capture the device-window status and the Watch's watchOS version before changing signing or bundle identifiers. Check that the installed Xcode supports development on that OS.

The phone now skips WatchConnectivity sends while no Watch is paired or its companion is uninstalled. The latest active workout state is retained and replayed when Watch installation/connection state changes. This avoids repeated `updateApplicationContext` failures; it does not fix provisioning or install the companion. The audio warnings in the supplied console are separate from Watch provisioning, and do not establish an iPhone crash.

The owner subsequently reported **“integrity could not be verified”** on the Watch while the iPhone app works. The locally signed iPhone app and its embedded Watch app both pass `codesign --verify --deep --strict`. Their signed bundle identifiers, companion identifier, team, and HealthKit entitlements match the project. The embedded Watch profile has not expired, but authorizes only the paired iPhone ID and no Watch ID. A valid signature on disk does not mean the profile authorizes installation on the Watch. Missing Watch registration remains the leading cause; capture the on-device installation error if it persists after a profile containing the Watch is installed.

The Watch owner reports **watchOS 10.6.2**, with Developer Mode absent from Settings. This meets the app's watchOS 10 minimum, and Xcode 26.4 supports on-device debugging for watchOS 8 and later. Apple documents that the Developer Mode setting may remain hidden until development pairing begins. In the installed Xcode 26.4 Devices setup assistant, only Chase's already-set-up iPhone is discovered; no Watch is offered. Keep the paired iPhone connected by cable and check Watch network discovery next. Apple specifically requires Series 5 and older Watches to share a Bonjour-compatible Wi-Fi network with the Mac. Confirm the Watch model and its actual Wi-Fi connection; ordinary phone/Watch Bluetooth pairing alone is not evidence of Xcode discovery. Do not erase or unpair the Watch as an initial troubleshooting step.

[Apple Watch development pairing](https://developer.apple.com/documentation/xcode/pairing-your-devices-with-your-mac), [Apple staff guidance for a missing Developer Mode switch](https://developer.apple.com/forums/thread/751553), and [Xcode 26.4 device support](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_4-release-notes).
