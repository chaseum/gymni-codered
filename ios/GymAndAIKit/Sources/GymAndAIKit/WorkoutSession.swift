import Foundation
import Observation

@MainActor @Observable
public final class WorkoutSession {
    public var display: WorkoutDisplay = .reps
    public var mode: WorkoutMode = .phone { didSet { saveConfiguration() } }
    public var exercise: Exercise = .curl { didSet { saveConfiguration() } }
    public var previewAddress = "" { didSet { saveConfiguration() } }
    public var audioEnabled = true { didSet { saveConfiguration() } }
    public var usesAppleWatch = true { didSet { saveConfiguration() } }
    public var presentsWorkout = false
    public private(set) var shouldAutoStartSimulatorSession = false
    public private(set) var store: WorkoutStore
    public private(set) var isPositioning = false
    public private(set) var isSending = false
    public private(set) var errorMessage: String?
    public private(set) var completedReps: Int?
    public private(set) var completedUnmeasuredSession = false
    public private(set) var completedMode: WorkoutMode?
    public private(set) var completedExercise: Exercise?
    public private(set) var watchHeartRate = HeartRateView.unavailable
    /// Where the camera device posts (`--post http://<this>`) while a camera-device session runs.
    public private(set) var hubAddress: String?

    @ObservationIgnored private var phone = PhoneWorkoutSource()
    @ObservationIgnored private var lastWatchMessageAtMs: Int64 = 0
    @ObservationIgnored private var watchSampleNotBeforeMs: Int64 = 0
    @ObservationIgnored private var sessionMode: WorkoutMode = .phone
    @ObservationIgnored private var hub: HubSession?
    @ObservationIgnored private var hubServer: HubServer?
    @ObservationIgnored private let preferences: UserDefaults?
    @ObservationIgnored private var isRestoringConfiguration = true

    public init(defaultMode: WorkoutMode = .phone, preferences: UserDefaults? = nil) {
        self.preferences = preferences
        store = WorkoutStore(sessionId: "phone")
        mode = defaultMode
        if let data = preferences?.data(forKey: WorkoutConfiguration.preferencesKey),
           let saved = try? JSONDecoder().decode(WorkoutConfiguration.self, from: data) {
            mode = saved.mode
            exercise = saved.exercise
            previewAddress = saved.previewAddress
            audioEnabled = saved.audioEnabled
            usesAppleWatch = saved.usesAppleWatch
        }
        isRestoringConfiguration = false
    }

    /// `--gymni-hub [--exercise curl]`: start a camera-device session that a local fitness-ml can post to.
    public func configureSimulatorLaunch(arguments: [String]) {
        guard arguments.contains("--gymni-hub") else { return }
        mode = .hub
        if let exerciseID = Self.argument(after: "--exercise", in: arguments),
           let exercise = Exercise(rawValue: exerciseID) {
            self.exercise = exercise
        }
        shouldAutoStartSimulatorSession = true
    }

    @discardableResult
    public func consumeSimulatorAutoStartRequest() -> Bool {
        defer { shouldAutoStartSimulatorSession = false }
        return shouldAutoStartSimulatorSession
    }

    public var isPhone: Bool { presentsWorkout ? sessionMode == .phone : mode == .phone }
    public var isHub: Bool { presentsWorkout ? sessionMode == .hub : mode == .hub }
    public var heartRate: HeartRateView {
        if watchHeartRate.status != .unavailable { return watchHeartRate }
        return snapshot?.heartRate ?? .unavailable
    }
    public var snapshot: Snapshot? { store.snapshot }
    public var repCount: Int { snapshot?.repCount ?? 0 }
    public var targetReps: Int? { snapshot?.targetReps }
    public var canResume: Bool { !isSending }
    public var previewURL: URL? { Self.networkURL(previewAddress) }

    private func saveConfiguration() {
        guard !isRestoringConfiguration, let preferences else { return }
        let settings = WorkoutConfiguration(mode: mode, exercise: exercise, previewAddress: previewAddress,
                                            audioEnabled: audioEnabled, usesAppleWatch: usesAppleWatch)
        if let data = try? JSONEncoder().encode(settings) {
            preferences.set(data, forKey: WorkoutConfiguration.preferencesKey)
        }
    }

    public func start() async {
        guard !isSending else { return }
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        sessionMode = mode
        display = .reps
        completedReps = nil
        completedUnmeasuredSession = false
        completedMode = nil
        completedExercise = nil
        watchHeartRate = .unavailable
        lastWatchMessageAtMs = 0
        watchSampleNotBeforeMs = 0
        stopHub()
        do {
            if sessionMode == .phone {
                phone = PhoneWorkoutSource()
                store = WorkoutStore(sessionId: phone.sessionID)
                store.apply(phone.initialSnapshot(exercise: exercise))
                isPositioning = true
                presentsWorkout = true
            } else {
                try startHub()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func pause() async {
        await command(.rest, args: CommandArgs(restSeconds: 60))
    }

    public func resume() async { await command(.resume) }

    public func extendRest() async {
        await command(.extendRest, args: CommandArgs(restSeconds: 30))
    }

    public func end() async { await command(.end) }

    public func returnToday() {
        guard snapshot?.state == .complete else { return }
        completedReps = isPhone ? nil : repCount
        completedUnmeasuredSession = isPhone
        completedMode = sessionMode
        completedExercise = snapshot?.exercise ?? exercise
        stopHub()
        presentsWorkout = false
    }

    public func clearError() { errorMessage = nil }

    public func beginPhoneSet() {
        guard isPhone, isPositioning, snapshot?.state == .ready else { return }
        isPositioning = false
        store.apply(phone.event(.sessionState(SessionStatePayload(state: .active))))
    }

    public func receiveWatchTelemetry(_ telemetry: WatchTelemetry, at now: Date = .now) {
        guard usesAppleWatch, presentsWorkout, snapshot?.state != .complete,
              telemetry.workoutID == store.sessionId,
              telemetry.emittedAtMs >= lastWatchMessageAtMs else { return }
        lastWatchMessageAtMs = telemetry.emittedAtMs
        if !telemetry.isRunning { watchHeartRate = .unavailable; return }
        guard snapshot?.state != .paused else { return }
        let rate = telemetry.heartRate(for: store.sessionId, at: now)
        guard rate.status == .live,
              (rate.sampleTimestampMs ?? 0) >= watchSampleNotBeforeMs,
              (rate.sampleTimestampMs ?? 0) > (watchHeartRate.sampleTimestampMs ?? 0) else { return }
        watchHeartRate = rate
    }

    public func clearWatchHeartRate() { watchHeartRate = .unavailable }

    public func restRemaining(at date: Date) -> Int {
        guard let endsAt = snapshot?.rest?.endsAtMs else { return 0 }
        return max(0, Int(ceil(Double(endsAt) / 1_000 - date.timeIntervalSince1970)))
    }

    public func heartRateText(at date: Date) -> String {
        let rate = heartRate
        guard rate.source == "apple_watch", rate.status != .unavailable,
              let bpm = rate.bpm,
              bpm.isFinite, (20...250).contains(bpm),
              let timestamp = rate.sampleTimestampMs else { return "Heart rate unavailable" }
        let age = date.timeIntervalSince1970 - Double(timestamp) / 1_000
        guard rate.status == .live, age >= 0, age <= HeartRateView.maxSampleAge else { return "Heart rate unavailable · Stale sample" }
        return "\(Int(bpm.rounded())) bpm"
    }

    private static func networkURL(_ address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed.contains("://") ? trimmed : "http://\(trimmed)"),
              ["http", "https"].contains(url.scheme), url.host != nil else { return nil }
        return url
    }

    private static func argument(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// The phone runs the session; the camera device (Pi or laptop) only POSTs observations to it.
    private func startHub() throws {
        let hub = HubSession(sessionId: "phone")
        store = WorkoutStore(sessionId: hub.sessionId)
        hub.onEvent = { [weak self] event in self?.store.apply(event) }
        store.apply(hub.snapshot())
        hubServer = try HubServer { [weak hub] observation in
            await MainActor.run { hub?.observe(observation) } ?? IngestAck(accepted: false, duplicate: false, ignored: "no_session")
        }
        self.hub = hub
        hubAddress = HubServer.wifiAddress().map { "\($0):\(HubServer.defaultPort)" }
        hub.command(.start, args: CommandArgs(exercise: exercise, targetReps: 8, source: .live))
        isPositioning = false
        presentsWorkout = true
    }

    private func stopHub() {
        hubServer?.stop()
        hubServer = nil
        hub = nil
        hubAddress = nil
    }

    private func command(_ intent: Intent, args: CommandArgs? = nil) async {
        guard !isSending else { return }
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        if sessionMode == .phone {
            applyPhoneCommand(intent, args: args)
        } else if let error = hub?.command(intent, args: args) {
            errorMessage = "The coach could not accept that action (\(error))."
        }
    }

    private func applyPhoneCommand(_ intent: Intent, args: CommandArgs?) {
        switch intent {
        case .pause, .rest:
            guard snapshot?.state == .active || snapshot?.state == .ready else { return }
            isPositioning = false
            watchHeartRate = .unavailable
            watchSampleNotBeforeMs = Int64(Date.now.timeIntervalSince1970 * 1_000)
            store.apply(phone.event(.sessionState(SessionStatePayload(state: .paused))))
            let end = Date().addingTimeInterval(Double(args?.restSeconds ?? 60))
            store.apply(phone.event(.rest(RestView(status: .resting, endsAtMs: Int64(end.timeIntervalSince1970 * 1_000)))))
        case .resume:
            guard snapshot?.state == .paused else { return }
            watchSampleNotBeforeMs = Int64(Date.now.timeIntervalSince1970 * 1_000)
            store.apply(phone.event(.rest(RestView(status: .ended))))
            store.apply(phone.event(.sessionState(SessionStatePayload(state: .ready))))
            isPositioning = true
        case .extendRest:
            guard snapshot?.state == .paused else { return }
            let end = Date().addingTimeInterval(Double(restRemaining(at: .now) + (args?.restSeconds ?? 30)))
            store.apply(phone.event(.rest(RestView(status: .resting, endsAtMs: Int64(end.timeIntervalSince1970 * 1_000)))))
        case .end:
            isPositioning = false
            watchHeartRate = .unavailable
            store.apply(phone.event(.sessionState(SessionStatePayload(state: .complete))))
        default: break
        }
    }
}
