@preconcurrency import WatchConnectivity
import HealthKit
import Observation
import GymAndAIKit

@MainActor @Observable
final class WatchConnectionController: NSObject, WCSessionDelegate {
    private(set) var status = "Checking Apple Watch…"
    private(set) var isPaired = false
    private(set) var isInstalled = false
    private(set) var isReachable = false
    @ObservationIgnored private let connection: WCSession?
    @ObservationIgnored private let healthStore = HKHealthStore()
    @ObservationIgnored private weak var workout: WorkoutSession?
    @ObservationIgnored private var lastMessage: WatchWorkoutMessage?
    @ObservationIgnored private var launchedWorkoutID: String?

    override init() {
        connection = WCSession.isSupported() ? .default : nil
        super.init()
        connection?.delegate = self
        connection?.activate()
        if connection == nil { status = "Apple Watch is unavailable on this device." }
    }

    func refresh() {
        guard let connection, connection.activationState == .activated else { return }
        isPaired = connection.isPaired
        isInstalled = connection.isWatchAppInstalled
        isReachable = connection.isReachable
        if !isPaired { status = "No Apple Watch paired to this iPhone." }
        else if !isInstalled { status = "Install Gym&I on your Apple Watch using the Watch app." }
        else { status = isReachable ? "Watch app reachable · Waiting for a heart-rate sample" : "Watch installed · Open Gym&I on your Watch" }
    }

    func synchronize(_ workout: WorkoutSession) async {
        self.workout = workout
        guard !workout.isDemo, workout.usesAppleWatch, workout.presentsWorkout,
              let state = workout.snapshot?.state else { return }
        if state == .paused || state == .complete { workout.clearWatchHeartRate() }
        let message = WatchWorkoutMessage(workoutID: workout.store.sessionId, state: state)
        if lastMessage?.workoutID != message.workoutID || lastMessage?.state != state {
            lastMessage = message
            transmit(message)
        }
        refresh()
        guard state != .complete, state != .paused, isPaired, isInstalled,
              launchedWorkoutID != message.workoutID else { return }
        launchedWorkoutID = message.workoutID
        do {
            try await healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [HKQuantityType(.heartRate)])
            guard workout.presentsWorkout, workout.snapshot?.state != .complete,
                  workout.snapshot?.state != .paused, workout.store.sessionId == message.workoutID else {
                launchedWorkoutID = nil
                return
            }
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor
            try await healthStore.startWatchApp(toHandle: configuration)
        } catch {
            status = "Couldn’t launch Watch workout: \(error.localizedDescription). Open Gym&I on your Watch and retry."
            launchedWorkoutID = nil
        }
    }

    func retry(_ workout: WorkoutSession) async {
        launchedWorkoutID = nil
        if let lastMessage { transmit(lastMessage) }
        await synchronize(workout)
    }

    func stop() {
        if let lastMessage, lastMessage.state != .complete {
            transmit(WatchWorkoutMessage(workoutID: lastMessage.workoutID, state: .complete))
        }
        lastMessage = nil
        launchedWorkoutID = nil
        workout?.clearWatchHeartRate()
    }

    private func transmit(_ message: WatchWorkoutMessage) {
        guard let connection, connection.activationState == .activated,
              connection.isPaired, connection.isWatchAppInstalled else { return }
        do {
            let data = try JSONEncoder().encode(message)
            try connection.updateApplicationContext(["workout": data])
            if connection.isReachable {
                connection.sendMessageData(data, replyHandler: nil) { [weak self] error in
                    let description = error.localizedDescription
                    Task { @MainActor [weak self] in self?.status = "Watch message pending: \(description)" }
                }
            }
        } catch { status = "Couldn’t send Watch state: \(error.localizedDescription)" }
    }

    private func receive(_ telemetry: WatchTelemetry) {
        guard let workout, workout.presentsWorkout, telemetry.workoutID == workout.store.sessionId else { return }
        workout.receiveWatchTelemetry(telemetry)
        status = telemetry.message
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let description = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.refresh()
            if let description { self.status = "Watch connection failed: \(description)" }
            if let lastMessage = self.lastMessage { self.transmit(lastMessage) }
            if let data = session.receivedApplicationContext["telemetry"] as? Data,
               let telemetry = try? JSONDecoder().decode(WatchTelemetry.self, from: data) { self.receive(telemetry) }
            if let workout = self.workout { await self.synchronize(workout) }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.refresh()
            if let message = self?.lastMessage { self?.transmit(message) }
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.refresh()
            if let message = self?.lastMessage { self?.transmit(message) }
            if let workout = self?.workout { await self?.synchronize(workout) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        guard let telemetry = try? JSONDecoder().decode(WatchTelemetry.self, from: messageData) else { return }
        Task { @MainActor [weak self] in self?.receive(telemetry) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["telemetry"] as? Data else { return }
        self.session(session, didReceiveMessageData: data)
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.workout?.clearWatchHeartRate()
            self?.status = "Watch connection inactive"
        }
    }
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
