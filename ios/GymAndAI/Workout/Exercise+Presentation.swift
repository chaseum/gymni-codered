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
    /// "8–12", or "5" for a fixed count.
    var rangeText: String { range.count > 1 ? "\(range.lowerBound)–\(range.upperBound)" : "\(reps)" }
}

extension WorkoutPlan.Step {
    var label: String { "\(exercise.title) · Set \(set) of \(sets)" }
}
