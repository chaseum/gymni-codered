@preconcurrency import HealthKit
@preconcurrency import WatchConnectivity
import Observation
import GymAndAIKit

@MainActor @Observable
final class WatchWorkoutManager: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate, WCSessionDelegate {
    private(set) var status = "Start an iPhone workout to connect."
    private(set) var bpm: Double?
    private(set) var sampleDate: Date?
    private(set) var hasWorkout = false
    private(set) var canRetry = false
    @ObservationIgnored private let healthStore = HKHealthStore()
    @ObservationIgnored private let connection = WCSession.default
    @ObservationIgnored private var workoutSession: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var latestCommand: WatchWorkoutMessage?
    @ObservationIgnored private var activeWorkoutID: String?
    @ObservationIgnored private var stoppedWorkoutID: String?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var finishing = false

    override init() {
        super.init()
        activateConnection()
    }

    func activateConnection() {
        connection.delegate = self
        connection.activate()
    }

    func heartRateText(at date: Date) -> String {
        guard workoutSession?.state == .running, let bpm, let sampleDate,
              (0...10).contains(date.timeIntervalSince(sampleDate)) else { return "— bpm" }
        return "\(Int(bpm.rounded())) bpm"
    }

    func retry() {
        guard let latestCommand, latestCommand.state != .complete else { return }
        stoppedWorkoutID = nil
        apply(latestCommand)
    }

    func stopFromWatch() {
        stoppedWorkoutID = activeWorkoutID ?? latestCommand?.workoutID
        startTask?.cancel()
        endWorkout()
        canRetry = true
        status = "Watch tracking ended. You can continue on iPhone."
        publish(running: false)
    }

    private func receive(_ message: WatchWorkoutMessage) {
        if let latestCommand {
            guard message.createdAtMs >= latestCommand.createdAtMs,
                  message.commandID != latestCommand.commandID else { return }
        }
        latestCommand = message
        apply(message)
    }

    private func apply(_ message: WatchWorkoutMessage) {
        guard !finishing else { return }
        if message.state == .complete {
            startTask?.cancel()
            endWorkout()
            return
        }
        guard stoppedWorkoutID != message.workoutID else { return }
        if let activeWorkoutID, activeWorkoutID != message.workoutID {
            endWorkout()
            return
        }
        if message.state == .paused {
            workoutSession?.pause()
            bpm = nil
            sampleDate = nil
            status = "Paused on iPhone"
            publish(running: false)
            return
        }
        if let workoutSession {
            if workoutSession.state == .paused { workoutSession.resume() }
            return
        }
        guard startTask == nil else { return }
        status = "Allow Health access on your Watch."
        canRetry = false
        startTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.startTask = nil
                if let latest = self.latestCommand, latest.workoutID != message.workoutID {
                    self.apply(latest)
                }
            }
            do {
                try await self.healthStore.requestAuthorization(
                    toShare: [HKObjectType.workoutType(), HKQuantityType(.heartRate)],
                    read: [HKQuantityType(.heartRate)]
                )
                guard !Task.isCancelled, self.latestCommand?.workoutID == message.workoutID,
                      self.latestCommand?.state != .complete, self.latestCommand?.state != .paused else { return }
                guard self.healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
                    self.status = "Allow workout saving in Watch Settings → Health. Then retry."
                    self.canRetry = true
                    self.publish(running: false)
                    return
                }
                try await self.startWorkout(id: message.workoutID)
            } catch {
                self.status = "Couldn’t start tracking: \(error.localizedDescription)"
                self.canRetry = true
                self.endWorkout()
                self.publish(running: false)
            }
        }
    }

    private func startWorkout(id: String) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self
        self.workoutSession = session
        self.builder = builder
        activeWorkoutID = id
        hasWorkout = true
        let start = Date()
        session.startActivity(with: start)
        try await builder.beginCollection(at: start)
        guard self.workoutSession === session, latestCommand?.state != .complete else { return }
        if latestCommand?.state == .paused { session.pause() }
        status = "Waiting for a Watch sensor reading…"
        publish(running: session.state == .running)
    }

    private func endWorkout() {
        if hasWorkout { status = "Ending Watch workout…" }
        bpm = nil
        sampleDate = nil
        hasWorkout = false
        publish(running: false)
        guard let workoutSession else { return }
        finishing = true
        workoutSession.end()
    }

    private func finishWorkout(at date: Date) async {
        guard let builder else { return }
        if !finishing {
            stoppedWorkoutID = activeWorkoutID
            canRetry = true
        }
        hasWorkout = false
        bpm = nil
        sampleDate = nil
        status = "Saving Watch workout…"
        publish(running: false)
        do {
            try await builder.endCollection(at: date)
            _ = try await builder.finishWorkout()
            status = "Workout saved to Apple Health."
        } catch { status = "Workout ended. Couldn’t save: \(error.localizedDescription)" }
        builder.delegate = nil
        workoutSession?.delegate = nil
        self.builder = nil
        workoutSession = nil
        activeWorkoutID = nil
        finishing = false
        if let latestCommand, latestCommand.state != .complete { apply(latestCommand) }
    }

    private func publish(running: Bool) {
        guard let id = activeWorkoutID ?? latestCommand?.workoutID else { return }
        let telemetry = WatchTelemetry(workoutID: id, bpm: running ? bpm : nil,
                                       sampleDate: running ? sampleDate : nil, isRunning: running, message: status)
        guard connection.activationState == .activated,
              let data = try? JSONEncoder().encode(telemetry) else { return }
        // Only the latest reading is useful; never enqueue a backlog of old heart rates.
        do { try connection.updateApplicationContext(["telemetry": data]) }
        catch { status = "Heart rate available on Watch. Phone connection needs retry." }
        if connection.isReachable { connection.sendMessageData(data, replyHandler: nil, errorHandler: nil) }
    }

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let type = HKQuantityType(.heartRate)
        guard collectedTypes.contains(type), let statistics = workoutBuilder.statistics(for: type),
              let quantity = statistics.mostRecentQuantity(), let interval = statistics.mostRecentQuantityDateInterval() else { return }
        let value = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        let date = interval.end
        let builderID = ObjectIdentifier(workoutBuilder)
        Task { @MainActor [weak self] in
            guard let self, let currentBuilder = self.builder, ObjectIdentifier(currentBuilder) == builderID,
                  self.workoutSession?.state == .running, value.isFinite, (20...250).contains(value),
                  date > (self.sampleDate ?? .distantPast) else { return }
            self.bpm = value
            self.sampleDate = date
            self.status = "Live heart rate · Sending to iPhone"
            self.publish(running: true)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        let sessionID = ObjectIdentifier(workoutSession)
        Task { @MainActor [weak self] in
            guard let self, let current = self.workoutSession, ObjectIdentifier(current) == sessionID else { return }
            if toState == .ended { await self.finishWorkout(at: date) }
            else if toState == .paused {
                self.bpm = nil
                self.sampleDate = nil
                self.status = "Paused on iPhone"
                self.publish(running: false)
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let description = error.localizedDescription
        let sessionID = ObjectIdentifier(workoutSession)
        Task { @MainActor [weak self] in
            guard let self, let current = self.workoutSession, ObjectIdentifier(current) == sessionID else { return }
            self.status = "Watch workout failed: \(description)"
            self.stoppedWorkoutID = self.activeWorkoutID
            self.canRetry = true
            self.endWorkout()
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let data = session.receivedApplicationContext["workout"] as? Data { self.session(session, didReceiveMessageData: data) }
        Task { @MainActor [weak self] in self?.publish(running: self?.workoutSession?.state == .running) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        guard let message = try? JSONDecoder().decode(WatchWorkoutMessage.self, from: messageData) else { return }
        Task { @MainActor [weak self] in self?.receive(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext["workout"] as? Data { self.session(session, didReceiveMessageData: data) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.publish(running: self?.workoutSession?.state == .running) }
    }
}
