import Foundation
import Observation

@MainActor @Observable
public final class WorkoutSession {
    public var display: WorkoutDisplay = .reps
    public var mode: WorkoutMode = .hub { didSet { saveConfiguration() } }
    public var exercise: Exercise = .curl { didSet { saveConfiguration() } }
    /// The hosted coach (ElevenLabs voice, Gemini, Backboard) is preset, so voice works out of the box.
    nonisolated public static let hostedAPI = "https://gymni-coach.vercel.app"
    /// `--hosted-api-url` can point a simulator build at a local server; it is never saved.
    public var hostedAPIAddress = WorkoutSession.hostedAPI
    public var voiceStatus: String? = "Connecting to ElevenLabs…"
    public private(set) var workoutHistoryURL: URL?
    public private(set) var workoutSyncStatus: String?
    @ObservationIgnored private var workoutRelay: HostedWorkoutRelay?
    @ObservationIgnored private var workoutSyncTask: Task<Void, Never>?
    @ObservationIgnored private var hostedCoach: HostedCoachClient?
    @ObservationIgnored private var voiceWarmTask: Task<Void, Never>?
    public var previewAddress = "" { didSet { saveConfiguration() } }
    public private(set) var cameraHost: String?
    public private(set) var cameraLastSeen: Date?
    public private(set) var coachingTrackingReady: Bool?
    @ObservationIgnored private var trackingCoach = TrackingCoach()
    @ObservationIgnored private var cameraRevision = 0
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
    /// Today's workout. The session walks its steps: each set ends at its target (or "next"), then rests.
    public private(set) var plan = WorkoutPlan.make(for: nil)
    public private(set) var stepIndex = 0
    /// The current set is done; resuming starts the next one.
    public private(set) var setFinished = false
    public private(set) var startedAt: Date?
    public private(set) var history: [CompletedWorkout] = []
    public var hubPort = HubServer.defaultPort
    @ObservationIgnored private var advertisesHub = true
    /// Sets and reps finished in this workout (for the recap and history).
    public private(set) var setsDone = 0
    public private(set) var totalReps = 0
    /// Per exercise in this workout: reps per set and the corrections given.
    public private(set) var results: [ExerciseResult] = []
    /// Suggested changes the person turned off for the next workout.
    public private(set) var adjustmentsOff: Set<Exercise> = []
    /// The coach's note for this workout, kept with it when it is saved.
    @ObservationIgnored private var pendingNote: String?
    @ObservationIgnored private var profile: TrainingProfile?
    /// Working weight per exercise in kg: the last one logged, or today's suggestion once a workout starts.
    public private(set) var loads: [Exercise: Double] = [:]
    /// Show and step loads in pounds.
    public var usesImperial = false
    private static let loadsKey = "gymni.loads.v1"
    private static let historyKey = "gymni.history.v1"
    private static let adjustmentsOffKey = "gymni.adjustmentsOff.v1"

    @ObservationIgnored private var phone = PhoneWorkoutSource()
    @ObservationIgnored private var lastWatchMessageAtMs: Int64 = 0
    @ObservationIgnored private var watchSampleNotBeforeMs: Int64 = 0
    @ObservationIgnored private var sessionMode: WorkoutMode = .hub
    @ObservationIgnored private var hub: HubSession?
    @ObservationIgnored private var hubServer: HubServer?
    @ObservationIgnored private let preferences: UserDefaults?
    @ObservationIgnored private var isRestoringConfiguration = true

    public init(defaultMode: WorkoutMode = .hub, preferences: UserDefaults? = nil) {
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
        if let data = preferences?.data(forKey: Self.historyKey),
           let saved = try? JSONDecoder().decode([CompletedWorkout].self, from: data) { history = saved }
        adjustmentsOff = Set((preferences?.stringArray(forKey: Self.adjustmentsOffKey) ?? []).compactMap(Exercise.init))
        if let saved = preferences?.dictionary(forKey: Self.loadsKey) as? [String: Double] {
            loads = Dictionary(uniqueKeysWithValues: saved.compactMap { key, kg in Exercise(rawValue: key).map { ($0, kg) } })
        }
        plan = WorkoutPlan.make(for: nil, history: history, adjustments: nextAdjustments.filter { !adjustmentsOff.contains($0.exercise) })
        isRestoringConfiguration = false
    }

    /// `--gymni-hub [--exercise curl]`: start a camera-device session that a local fitness-ml can post to.
    public func configureSimulatorLaunch(arguments: [String]) {
        advertisesHub = !arguments.contains("--gymni-ui-testing")
        if let address = Self.argument(after: "--hosted-api-url", in: arguments) { hostedAPIAddress = address }
        if let address = Self.argument(after: "--preview-url", in: arguments) { previewAddress = address }
        if let port = Self.argument(after: "--hub-port", in: arguments).flatMap(UInt16.init), port > 0 { hubPort = port }
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
    public var currentStep: WorkoutPlan.Step? { plan.steps.indices.contains(stepIndex) ? plan.steps[stepIndex] : nil }
    public var nextStep: WorkoutPlan.Step? { plan.steps.indices.contains(stepIndex + 1) ? plan.steps[stepIndex + 1] : nil }

    /// What to change next time, from the last workout (rules in `Coach`).
    public var nextAdjustments: [PlanAdjustment] { Coach.adjustments(from: history, imperial: usesImperial) }

    /// Rebuilds today's plan from the profile, the history, and the changes the person kept.
    public func usePlan(for profile: TrainingProfile?) {
        self.profile = profile
        let kept = nextAdjustments.filter { !adjustmentsOff.contains($0.exercise) }
        usePlan(WorkoutPlan.make(for: profile, history: history, adjustments: kept, loads: loads))
    }

    /// Logs the working weight for an exercise (nil clears it); later sets and plans use it.
    public func setLoad(_ kg: Double?, for exercise: Exercise) {
        loads[exercise] = kg
        preferences?.set(Dictionary(uniqueKeysWithValues: loads.map { ($0.key.rawValue, $0.value) }), forKey: Self.loadsKey)
    }

    public func setAdjustment(_ exercise: Exercise, enabled: Bool) {
        if enabled { adjustmentsOff.remove(exercise) } else { adjustmentsOff.insert(exercise) }
        preferences?.set(adjustmentsOff.map(\.rawValue), forKey: Self.adjustmentsOffKey)
        usePlan(for: profile)
    }

    /// Keeps the coach's note with the workout that started at `date` (now, or once it is saved).
    public func setNote(_ note: String, workoutStartedAt date: Date) {
        guard let index = history.firstIndex(where: { $0.date == date }) else { pendingNote = note; return }
        history[index].note = note
        saveHistory()
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) { preferences?.set(data, forKey: Self.historyKey) }
    }

    public func usePlan(_ plan: WorkoutPlan) {
        guard !presentsWorkout, !plan.items.isEmpty else { return }
        self.plan = plan
        exercise = plan.items[0].exercise
    }

    public func workoutsThisWeek(now: Date = .now, calendar: Calendar = .current) -> Int {
        history.filter { calendar.isDate($0.date, equalTo: now, toGranularity: .weekOfYear) }.count
    }
    public var previewURL: URL? {
        if let cameraHost { return URL(string: "http://\(cameraHost):8081") }
        return Self.networkURL(previewAddress)
    }

    public func cameraStatus(at now: Date = .now) -> String {
        guard let cameraLastSeen, now.timeIntervalSince(cameraLastSeen) < 4 else {
            return "Waiting for tripod · Check Personal Hotspot and Pi power"
        }
        return "Tripod connected"
    }

    public func resetTrackingCoaching() {
        trackingCoach = TrackingCoach()
        coachingTrackingReady = nil
    }

    public func updateTrackingCoaching(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> CoachVoiceCue? {
        var status = snapshot?.trackingStatus
        if let cameraLastSeen, Date.now.timeIntervalSince(cameraLastSeen) >= 4 { status = .lost }
        let cue = trackingCoach.update(status, at: now)
        if coachingTrackingReady != trackingCoach.isReady { coachingTrackingReady = trackingCoach.isReady }
        return cue
    }

    public func trackingCueIsCurrent(_ cue: CoachVoiceCue) -> Bool {
        snapshot?.state == .active && coachingTrackingReady == (cue == .trackingReady)
    }

    public func trackingCueWasSpoken(_ cue: CoachVoiceCue) {
        trackingCoach.didSpeak(cue, at: ProcessInfo.processInfo.systemUptime)
    }

    private func cameraConfiguration() -> CameraConfiguration? {
        guard let snapshot, let setId = snapshot.setId, let exercise = snapshot.exercise,
              let workoutHistoryURL else { return nil }
        return CameraConfiguration(workoutId: workoutHistoryURL.deletingPathExtension().lastPathComponent,
                                   sessionId: store.sessionId, setId: setId, exercise: exercise,
                                   state: snapshot.state, revision: cameraRevision)
    }

    private func saveConfiguration() {
        guard !isRestoringConfiguration, let preferences else { return }
        let settings = WorkoutConfiguration(mode: mode, exercise: exercise, previewAddress: previewAddress,
                                            audioEnabled: audioEnabled, usesAppleWatch: usesAppleWatch)
        if let data = try? JSONEncoder().encode(settings) {
            preferences.set(data, forKey: WorkoutConfiguration.preferencesKey)
        }
    }

    public func start() async {
        guard !isSending, !presentsWorkout else { return }  // a second tap must not restart the workout
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        sessionMode = mode
        display = .reps
        stepIndex = 0
        setFinished = false
        setsDone = 0
        totalReps = 0
        results = []
        pendingNote = nil
        for item in plan.items { if let weight = item.weight { setLoad(weight, for: item.exercise) } }  // today's suggestion
        startedAt = .now
        if let first = currentStep { exercise = first.exercise }
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

    /// Resumes a paused set, or after a finished set starts the next one in the plan.
    public func resume() async {
        if setFinished, let next = nextStep {
            stepIndex += 1
            setFinished = false
            exercise = next.exercise
            await command(.nextExercise, args: CommandArgs(exercise: next.exercise, targetReps: next.reps))
        }
        await command(.resume)
    }

    /// Ends the current set (target reached or skipped): rest before the next one, or finish the workout.
    public func finishSet() async {
        guard snapshot?.state == .active, !setFinished else { return }
        guard let step = currentStep, nextStep != nil else { return await end() }
        recordCurrentSet()
        setFinished = true
        await command(.rest, args: CommandArgs(restSeconds: step.restSeconds))
    }

    public func extendRest() async {
        await command(.extendRest, args: CommandArgs(restSeconds: 30))
    }

    public func end() async {
        if !setFinished, snapshot?.state != .complete { recordCurrentSet() }  // the last or a partly done set
        await command(.end)
    }

    /// A set's reps go into the results when it ends, so the rest screen can talk about it.
    private func recordCurrentSet() {
        let reps = repCount
        guard reps > 0, let exercise = currentStep?.exercise else { return }
        let weight = loads[exercise]
        record {
            $0.weights = ($0.weights ?? Array(repeating: nil, count: $0.reps.count)) + [weight]
            $0.reps.append(reps)
        }
    }

    public func returnToday() {
        guard snapshot?.state == .complete else { return }
        completedReps = isPhone ? nil : repCount
        completedUnmeasuredSession = isPhone
        completedMode = sessionMode
        completedExercise = snapshot?.exercise ?? exercise
        if totalReps > 0, let startedAt {
            history.insert(CompletedWorkout(date: startedAt, title: plan.title, sets: setsDone, reps: totalReps,
                                            durationSeconds: Int(Date.now.timeIntervalSince(startedAt)),
                                            results: results, note: pendingNote), at: 0)
            saveHistory()
            adjustmentsOff = []  // new suggestions come from this workout
            preferences?.removeObject(forKey: Self.adjustmentsOffKey)
        }
        stopHub()
        presentsWorkout = false
        usePlan(for: profile)
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
        let history = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "GymAndAI/Workouts/\(UUID().uuidString).json")
        workoutHistoryURL = history
        let hub = HubSession(sessionId: "phone", historyURL: history)
        hub.onHistoryFailure = { [weak self] in self?.errorMessage = "Workout history could not be saved on this iPhone." }

        store = WorkoutStore(sessionId: hub.sessionId)
        hub.onEvent = { [weak self] event in self?.received(event) }
        store.apply(hub.snapshot())
        hubServer = try HubServer(port: hubPort, advertises: advertisesHub, configuration: { [weak self] in
            await self?.cameraConfiguration()
        }, cameraConnected: { [weak self] host in
            await self?.cameraDidConnect(host)
        }) { [weak hub] observation in
            await MainActor.run { hub?.observe(observation) } ?? IngestAck(accepted: false, duplicate: false, ignored: "no_session")
        }
        self.hub = hub
        configureHostedCoach(warmWorkout: true)
        hubAddress = HubServer.wifiAddress().map { "\($0):\(HubServer.defaultPort)" }
        hub.command(.start, args: CommandArgs(exercise: exercise, targetReps: currentStep?.reps ?? 8, source: .live))
        isPositioning = false
        presentsWorkout = true
    }

    /// Normal product launch always uses Pi observations; saved camera choices are migrated.
    public func useMainAppConfiguration() {
        mode = .hub
    }

    public func configureHostedCoach(warmWorkout: Bool = false) {
        voiceWarmTask?.cancel()
        hostedCoach = nil
        guard let url = Self.networkURL(hostedAPIAddress),
              url.scheme == "https" || ["localhost", "127.0.0.1"].contains(url.host ?? "") else {
            voiceStatus = "ElevenLabs is unavailable. Saved clips and captions remain available."
            return
        }
        let client = HostedCoachClient(baseURL: url)
        hostedCoach = client
        if workoutRelay == nil { workoutRelay = HostedWorkoutRelay(baseURL: url) }
        syncWorkouts()
        voiceStatus = "Connecting to ElevenLabs…"
        voiceWarmTask = Task { [weak self] in
            do {
                try await client.prepare()
                guard !Task.isCancelled, let self else { return }
                voiceStatus = nil
                if warmWorkout { await client.warm(exercise: exercise, target: currentStep?.reps ?? 8) }
            } catch {
                guard !Task.isCancelled else { return }
                self?.voiceStatus = "ElevenLabs is unavailable. Saved clips and captions remain available."
            }
        }
    }

    public func fetchHostedAudio(_ request: HostedVoiceRequest) async throws -> Data {
        guard let hostedCoach else { throw URLError(.badURL) }
        do {
            let data = try await hostedCoach.audio(for: request)
            if !Task.isCancelled { voiceStatus = nil }
            return data
        } catch {
            if !Task.isCancelled { voiceStatus = "ElevenLabs audio is unavailable. Follow the captions." }
            throw error
        }
    }

    public func reportVoicePlaybackFailure() { voiceStatus = "Coach audio could not play. Follow the captions." }

    private func stopHub() {
        voiceWarmTask?.cancel()
        voiceWarmTask = nil
        hubServer?.stop()
        hubServer = nil
        hub = nil
        hubAddress = nil
        cameraHost = nil
        cameraLastSeen = nil
    }

    private func received(_ event: WorkoutEvent) {
        store.apply(event)
        if case .setCompleted(let set) = event.payload {
            setsDone += 1
            totalReps += set.repCount
        }
        if case .feedbackIssued(let feedback) = event.payload { record { $0.corrections[feedback.text, default: 0] += 1 } }
        // Reaching the set's target rests (or finishes the workout) on its own.
        if case .repCompleted(let rep) = event.payload, let target = rep.targetReps, rep.repCount >= target {
            Task { await finishSet() }
        }
    }

    /// Stays with one camera until it has been quiet for 4 s, so a second camera on the network can't make the
    /// preview flip between them. The camera calls ~15 times a second; "last seen" only needs 1 s resolution.
    /// Updates this workout's result for the current step's exercise.
    private func record(_ change: (inout ExerciseResult) -> Void) {
        guard let step = currentStep else { return }
        let item = plan.items.first { $0.exercise == step.exercise }
        if let index = results.firstIndex(where: { $0.exercise == step.exercise }) {
            change(&results[index])
        } else {
            var result = ExerciseResult(exercise: step.exercise, reps: [], low: item?.range.lowerBound ?? step.reps, high: step.reps)
            change(&result)
            results.append(result)
        }
    }

    func cameraDidConnect(_ host: String, now: Date = .now) {
        let quiet = cameraLastSeen.map { now.timeIntervalSince($0) > 4 } ?? true
        guard host == cameraHost || cameraHost == nil || quiet else { return }
        if host != cameraHost { cameraHost = host; cameraLastSeen = now; return }
        if cameraLastSeen.map({ now.timeIntervalSince($0) >= 1 }) ?? true { cameraLastSeen = now }
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
        if errorMessage == nil { cameraRevision += 1 }
        if intent == .end {
            await hub?.flushHistory()
            if sessionMode == .hub { syncWorkouts() }
        }
    }

    private func syncWorkouts() {
        guard let workoutRelay else { return }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "GymAndAI/Workouts")
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        workoutSyncTask?.cancel()
        workoutSyncStatus = "Sending measured workout data…"
        workoutSyncTask = Task { [weak self] in
            do {
                try await workoutRelay.sync(directory: directory)
                guard !Task.isCancelled else { return }
                self?.workoutSyncStatus = "Workout data synced"
            } catch {
                guard !Task.isCancelled else { return }
                self?.workoutSyncStatus = "Saved on iPhone · Will retry when the coach reconnects"
            }
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
