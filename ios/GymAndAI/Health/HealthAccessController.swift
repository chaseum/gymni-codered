import HealthKit
import Observation

@MainActor @Observable
final class HealthAccessController {
    private(set) var state: HealthAccessState
    @ObservationIgnored private let healthStore: HKHealthStore?

    init() {
        let available = HKHealthStore.isHealthDataAvailable()
        healthStore = available ? HKHealthStore() : nil
        state = available ? .ready : .unavailable
    }

    func requestHeartRateAccess() async {
        guard state != .requesting else { return }
        guard let healthStore else { state = .unavailable; return }
        state = .requesting
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [HKQuantityType(.heartRate)])
            // Finishing authorization does not reveal whether read access was granted.
            state = .requestFinished
        } catch {
            state = .failed("Couldn’t request Apple Health access. \(error.localizedDescription)")
        }
    }
}
