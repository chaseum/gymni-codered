import WatchKit
import HealthKit

final class WatchApplicationDelegate: NSObject, WKApplicationDelegate {
    let manager = WatchWorkoutManager()

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        manager.activateConnection()
    }
}
