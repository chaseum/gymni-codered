import Foundation

struct WorkoutConfiguration: Codable {
    static let preferencesKey = "gymni.workoutConfiguration.v1"

    var mode: WorkoutMode
    var exercise: Exercise
    var inputSource: InputSource
    var backendAddress: String
    var backendSessionId: String
    var previewAddress: String
    var audioEnabled: Bool
    var usesAppleWatch: Bool
}
