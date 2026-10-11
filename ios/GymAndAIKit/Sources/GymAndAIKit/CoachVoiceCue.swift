public enum CoachVoiceCue: String, Sendable {
    case paused, ended, begin, positioning, waiting
    case trackingReady = "tracking_ready"
    case trackingLost = "tracking_lost"

    public var text: String {
        switch self {
        case .paused: "Paused. Take the time you need."
        case .ended: "Workout ended. Here is your recap."
        case .begin: "Let’s begin. I’ll count your reps."
        case .positioning: "Step into view so I can follow your movement."
        case .waiting: "Waiting for camera tracking."
        case .trackingReady: "Tracking ready. I’m following your reps."
        case .trackingLost: "Tracking interrupted. Adjust your position."
        }
    }
}
