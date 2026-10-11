import GymAndAIKit

extension Exercise {
    var title: String {
        switch self {
        case .curl: "Biceps curl"
        case .squat: "Squat"
        case .deadlift: "Deadlift"
        }
    }

    var positioning: String {
        switch self {
        case .curl: "Keep your working shoulder, elbow, and wrist in view."
        case .squat: "Use the tested side view with your shoulders, hips, knees, and feet visible."
        case .deadlift: "Use the tested side view with your shoulders, hips, knees, and feet visible."
        }
    }
}
