@preconcurrency import WatchConnectivity
import HealthKit
import Network
import Observation
import GymAndAIKit

/// Heart rate comes from the Apple Watch's own Workout app via Apple Health; Gym&I has no Watch app.
@MainActor @Observable
final class HeartRateMonitor: NSObject, WCSessionDelegate {
    private(set) var hasPairedWatch = false
    @ObservationIgnored private let healthStore = HKHealthStore()
    @ObservationIgnored private var query: HKAnchoredObjectQuery?
    @ObservationIgnored private weak var workout: WorkoutSession?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Reads heart-rate samples as the Watch saves them, for this workout only.
    func start(for workout: WorkoutSession) {
        self.workout = workout
        guard query == nil, HKHealthStore.isHealthDataAvailable() else { return }
        let handler: @Sendable (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { _, samples, _, _, _ in
            guard let sample = (samples as? [HKQuantitySample])?.max(by: { $0.endDate < $1.endDate }) else { return }
            let bpm = sample.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
            let date = sample.endDate
            Task { @MainActor [weak self] in
                guard let workout = self?.workout, workout.presentsWorkout else { return }
                workout.receiveWatchTelemetry(WatchTelemetry(workoutID: workout.store.sessionId, bpm: bpm, sampleDate: date,
                                                             isRunning: true, message: ""))
            }
        }
        let recent = HKQuery.predicateForSamples(withStart: .now.addingTimeInterval(-HeartRateView.maxSampleAge), end: nil)
        let query = HKAnchoredObjectQuery(type: HKQuantityType(.heartRate), predicate: recent, anchor: nil,
                                          limit: HKObjectQueryNoLimit, resultsHandler: handler)
        query.updateHandler = handler
        self.query = query
        healthStore.execute(query)
    }

    func stop() {
        if let query { healthStore.stop(query) }
        query = nil
        workout?.clearWatchHeartRate()
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let paired = activationState == .activated && session.isPaired
        Task { @MainActor [weak self] in self?.hasPairedWatch = paired }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}

/// System permission prompts, asked during onboarding when the person taps Continue.
enum Permissions {
    static func requestHeartRate() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await HKHealthStore().requestAuthorization(toShare: [], read: [HKQuantityType(.heartRate)])
    }

    /// iOS asks for Local Network access the first time the app looks for devices; browsing for the camera's
    /// Bonjour service triggers that prompt now instead of mid-workout.
    @MainActor static func requestLocalNetwork() {
        let browser = NWBrowser(for: .bonjour(type: "_gymni._tcp", domain: nil), using: .tcp)
        browser.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { browser.cancel() }
    }
}
