import GymAndAIKit

extension Exercise {
    var title: String {
        switch self {
        case .curl: "Biceps Curl"
        case .squat: "Squat"
        case .deadlift: "Deadlift"
        }
    }

    var symbol: String {
        switch self {
        case .curl: "dumbbell.fill"
        case .squat: "figure.strengthtraining.functional"
        case .deadlift: "figure.strengthtraining.traditional"
        }
    }
}

extension WorkoutPlan.Item {
    /// "3 × 8"
    var prescription: String { "\(sets) × \(reps)" }
}

extension WorkoutPlan.Step {
    var label: String { "\(exercise.title) · Set \(set) of \(sets)" }
}
