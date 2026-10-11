import Foundation
import Observation

@MainActor @Observable
public final class WorkoutSession {
    public var display: WorkoutDisplay = .reps
    public var mode: WorkoutMode = .demo
    public var exercise: Exercise = .curl
    public var inputSource: InputSource = .live
    public var backendAddress = "http://localhost:8000"
    public var backendSessionId = ""
    public var previewAddress = ""
    public var token = ""
    public var audioEnabled = true
    public var usesAppleWatch = true
    public var presentsWorkout = false
    public private(set) var store: WorkoutStore
    public private(set) var isPositioning = false
    public private(set) var isSending = false
    public private(set) var errorMessage: String?
    public private(set) var completedReps: Int?
    public private(set) var completedUnmeasuredSession = false
    public private(set) var watchHeartRate = HeartRateView.unavailable

    @ObservationIgnored private var demo = DemoWorkoutSource()
    @ObservationIgnored private var phone = PhoneWorkoutSource()
    @ObservationIgnored private var demoTask: Task<Void, Never>?
    @ObservationIgnored private var lastWatchMessageAtMs: Int64 = 0
    @ObservationIgnored private var watchSampleNotBeforeMs: Int64 = 0
    @ObservationIgnored private var sessionMode: WorkoutMode = .demo

    public init() {
        store = WorkoutStore(baseURL: URL(filePath: "/"), sessionId: "phone-demo")
    }

    public var isDemo: Bool { presentsWorkout ? sessionMode == .demo : mode == .demo }
    public var isPhone: Bool { presentsWorkout ? sessionMode == .phone : mode == .phone }
    public var heartRate: HeartRateView {
        if !isDemo, watchHeartRate.status != .unavailable { return watchHeartRate }
        return snapshot?.heartRate ?? .unavailable
    }
    public var snapshot: Snapshot? { store.snapshot }
    public var repCount: Int { snapshot?.repCount ?? 0 }
    public var targetReps: Int? { snapshot?.targetReps }
    public var hasConnection: Bool { isDemo || isPhone || store.connection == .connected }
    public var canResume: Bool { !isSending && hasConnection }
    public var previewURL: URL? { Self.networkURL(previewAddress) }

    public func start() async {
        guard !isSending else { return }
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        sessionMode = mode
        display = .reps
        completedReps = nil
        completedUnmeasuredSession = false
        watchHeartRate = .unavailable
        lastWatchMessageAtMs = 0
        watchSampleNotBeforeMs = 0
        demoTask?.cancel()
        store.disconnect()
        do {
            if sessionMode == .demo {
                demo = DemoWorkoutSource()
                store = WorkoutStore(baseURL: URL(filePath: "/"), sessionId: "phone-demo")
                store.apply(demo.initialSnapshot(exercise: exercise))
                presentsWorkout = true
                beginDemoPositioning()
            } else if sessionMode == .phone {
                phone = PhoneWorkoutSource()
                store = WorkoutStore(baseURL: URL(filePath: "/"), sessionId: phone.sessionID)
                store.apply(phone.initialSnapshot(exercise: exercise))
                isPositioning = true
                presentsWorkout = true
            } else {
                try await startBackend()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func pause() async {
        await command(.rest, args: CommandArgs(restSeconds: isDemo ? 15 : 60))
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
        demoTask?.cancel()
        store.disconnect()
        presentsWorkout = false
    }

    public func clearError() { errorMessage = nil }

    public func beginPhoneSet() {
        guard isPhone, isPositioning, snapshot?.state == .ready else { return }
        isPositioning = false
        store.apply(phone.event(.sessionState(SessionStatePayload(state: .active))))
    }

    public func receiveWatchTelemetry(_ telemetry: WatchTelemetry, at now: Date = .now) {
        guard !isDemo, usesAppleWatch, presentsWorkout, snapshot?.state != .complete,
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
              let timestamp = rate.sampleTimestampMs else { return "Heart rate unavailable" }
        let age = date.timeIntervalSince1970 - Double(timestamp) / 1_000
        guard rate.status == .live, age >= 0, age <= 10 else { return "Heart rate unavailable · Stale sample" }
        return "\(Int(bpm.rounded())) bpm · Updated \(Int(age))s ago"
    }

    private static func networkURL(_ address: String) -> URL? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme), url.host != nil else { return nil }
        return url
    }

    private func startBackend() async throws {
        guard let baseURL = Self.networkURL(backendAddress) else {
            throw URLError(.badURL, userInfo: [NSLocalizedDescriptionKey: "Enter a valid laptop URL, including http:// or https://."])
        }
        let sessionId = backendSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionId.isEmpty, !sessionId.contains("/"), !sessionId.contains("?") else {
            throw URLError(.badURL, userInfo: [NSLocalizedDescriptionKey: "Enter the session ID created on the laptop."])
        }
        store = WorkoutStore(baseURL: baseURL, sessionId: sessionId, token: token.isEmpty ? nil : token)
        // Attach to an existing laptop session; never overwrite an active set on reconnect.
        var request = URLRequest(url: baseURL.appending(path: "api/sessions/\(sessionId)"))
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Session not found or access denied. Create a session on the laptop first."])
        }
        let event = try Contracts.decoder.decode(WorkoutEvent.self, from: data)
        store.apply(event)
        if store.snapshot?.state == .ready {
            let ack = try await store.send(.start, args: CommandArgs(exercise: exercise, targetReps: 8, source: inputSource))
            guard ack.accepted else { throw URLError(.badServerResponse) }
        }
        isPositioning = false
        presentsWorkout = true
        store.connect()
    }

    private func command(_ intent: Intent, args: CommandArgs? = nil) async {
        guard !isSending else { return }
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        if sessionMode == .demo {
            applyDemoCommand(intent, args: args)
            return
        }
        if sessionMode == .phone {
            applyPhoneCommand(intent, args: args)
            return
        }
        do {
            let ack = try await store.send(intent, args: args)
            if !ack.accepted { errorMessage = ack.error ?? "The coach could not accept that action." }
        } catch {
            errorMessage = "The action was not confirmed. Check the laptop connection."
        }
    }

    private func applyDemoCommand(_ intent: Intent, args: CommandArgs?) {
        switch intent {
        case .rest, .pause:
            demoTask?.cancel()
            isPositioning = false
            emit(.sessionState(SessionStatePayload(state: .paused)))
            let end = Date().addingTimeInterval(Double(args?.restSeconds ?? 15))
            emit(.rest(RestView(status: .resting, endsAtMs: Int64(end.timeIntervalSince1970 * 1_000))))
        case .resume:
            guard snapshot?.state == .paused else { return }
            emit(.rest(RestView(status: .ended)))
            beginDemoPositioning()
        case .extendRest:
            guard snapshot?.state == .paused else { return }
            let remaining = restRemaining(at: Date()) + (args?.restSeconds ?? 30)
            let end = Date().addingTimeInterval(Double(remaining))
            emit(.rest(RestView(status: .resting, endsAtMs: Int64(end.timeIntervalSince1970 * 1_000))))
        case .end:
            demoTask?.cancel()
            isPositioning = false
            emit(.sessionState(SessionStatePayload(state: .complete)))
        default: break
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

    private func beginDemoPositioning() {
        demoTask?.cancel()
        isPositioning = true
        demoTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.isPositioning = false
            self.emit(.tracking(TrackingPayload(status: .ready, source: .live)))
            self.emit(.sessionState(SessionStatePayload(state: .active)))
            await self.runDemoReps()
        }
    }

    private func runDemoReps() async {
        while !Task.isCancelled, snapshot?.state == .active, repCount < (targetReps ?? 8) {
            do { try await Task.sleep(for: .seconds(2.3)) } catch { return }
            guard !Task.isCancelled, snapshot?.state == .active else { return }
            emit(.repCompleted(RepCompleted(exercise: exercise, setId: "demo-set-1", repCount: repCount + 1, targetReps: 8)))
            if repCount == 2, exercise == .curl {
                emit(.feedbackIssued(FeedbackIssued(feedbackId: "demo-cue", issueCode: "curl.elbow_drift", text: "Keep your upper arm steady.", setId: "demo-set-1", repCount: 2)))
            }
            if repCount == 5, exercise == .curl {
                emit(.feedbackImproved(FeedbackImproved(feedbackId: "demo-cue", issueCode: "curl.elbow_drift", setId: "demo-set-1", repCount: 5)))
            }
        }
        if !Task.isCancelled, repCount >= (targetReps ?? 8) {
            emit(.sessionState(SessionStatePayload(state: .complete)))
        }
    }

    private func emit(_ payload: EventPayload) { store.apply(demo.event(payload)) }
}
