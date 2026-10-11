import Foundation

struct WorkoutConfiguration: Codable {
    static let preferencesKey = "gymni.workoutConfiguration.v2"  // v1 saved the removed Demo/Laptop modes

    var mode: WorkoutMode
    var exercise: Exercise
    var hostedAPIAddress: String? = nil
    var previewAddress: String
    var audioEnabled: Bool
    var usesAppleWatch: Bool
}
