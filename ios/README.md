# iOS + watchOS (Bryan)

What exists: **`GymAndAIKit/`**, a Swift package with the typed contract (`Contracts.swift`) and the one networking/state object (`WorkoutStore.swift`). It builds for iOS 17+, watchOS 10+ and macOS, and its tests decode the shared fixtures in `contracts/fixtures/`.

What does not exist yet: the Xcode app project. It was not generated from the command line on purpose (no fake `.xcodeproj`). Create it once in Xcode, commit it, and it becomes the real project.

```bash
cd ios/GymAndAIKit && swift test
```

## Create the Xcode project (≈10 min, once)

1. Xcode → File → New → Project → **iOS App**. Product name `GymAndAI`, interface SwiftUI, language Swift, no Core Data. Save it **in `ios/`**, so you get `ios/GymAndAI.xcodeproj` and `ios/GymAndAI/`. Leave "Create Git repository" unchecked (we're already in one).
2. File → New → Target → **watchOS → App**, name `GymAndAIWatch`, "Watch App for Existing iOS App" → `GymAndAI`.
3. File → Add Package Dependencies → **Add Local…** → `ios/GymAndAIKit`. Link the `GymAndAIKit` library to **both** targets.
4. iPhone target → Info:
   - `NSLocalNetworkUsageDescription` = "Gym&AI connects to the coach running on your laptop."
   - `NSAppTransportSecurity` → `NSAllowsLocalNetworking` = YES (allows plain `http://`/`ws://` to LAN hosts only. Do **not** set `NSAllowsArbitraryLoads`).
   - `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` when voice commands are added.
5. Watch target → Signing & Capabilities → **HealthKit**; Info: `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`; Background Modes → Workout processing. iPhone target also gets HealthKit if it receives mirrored sessions.
6. Signing: pick your personal/team account for both targets; set a unique bundle id prefix (e.g. `com.<you>.gymandai`).
7. Build and run on the iPhone simulator, then on device. Commit `ios/GymAndAI.xcodeproj` + sources (`xcuserdata/` is git-ignored).

## Wire it up

```swift
import SwiftUI
import GymAndAIKit

@main struct GymAndAIApp: App {
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
```

Rules from `contracts/protocol.md` that are on you:
- Render `rep_count` from the store only; never increment locally.
- Show **LIVE** / **RECORDED** from `snapshot.source`.
- `heartRate.status == .unavailable` → show "HR unavailable", not 0 or a placeholder number. Age HR locally from `sampleTimestampMs`.
- Rest timer reaching `endsAtMs` shows "Ready when you are" with Resume/End; do not auto-resume.
- Play cues from `feedback.issued.cueId` → `assets/audio/<cueId>.m4a` bundled in the app; one at a time; cancel on pause.
- The phone simulator reaches the laptop backend at `http://localhost:8000`; a physical phone needs the laptop's LAN IP.

## Watch HR (not implemented — spike in hours 2–6)

`HKWorkoutSession` + `HKLiveWorkoutBuilder` on the Watch; for each heart-rate `HKQuantitySample` build `HeartRateSample(sampleId: sample.uuid.uuidString, …, sampleDate: sample.endDate)` and deliver it to the phone (`startMirroringToCompanionDevice` or WatchConnectivity), which POSTs it via `let _: IngestAck = try await store.post("heart_rate", sample)`. If signing/HealthKit blocks this, document the blocker; the UI already handles "unavailable".
