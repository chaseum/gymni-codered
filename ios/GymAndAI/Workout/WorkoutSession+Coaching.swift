import GymAndAIKit

extension WorkoutSession {
    var trackingMessage: String {
        if isPhone { return "Rep and form analysis unavailable" }
        if isDemo { return isPositioning ? "Simulating readiness…" : "Simulated tracking ready" }
        if !hasConnection {
            return store.connection == .connecting ? "Connecting to laptop…" : "Connection interrupted · Reconnecting"
        }
        switch snapshot?.trackingStatus {
        case .ready: return "Tracking ready"
        case .lowVisibility: return "Tracking limited · Adjust your position"
        case .unassessable: return "This view cannot be assessed"
        default: return "Waiting for camera tracking"
        }
    }

    var coachingMessage: String {
        if isPhone { return "Your camera is live. Rep counting and form feedback await the trained model." }
        guard hasConnection else { return "Connection interrupted. Check your laptop." }
        guard snapshot?.trackingStatus == .ready else { return "Step into view so I can follow your movement." }
        if let feedback = store.lastFeedback,
           feedback.setId == snapshot?.setId,
           snapshot?.activeIssues.contains(feedback.issueCode) == true { return feedback.text }
        if isDemo, repCount >= 5, exercise == .curl { return "That is steadier now. Nice work." }
        return isDemo ? "Follow the simulated set at your own pace." : "Keep moving. I’m following your reps."
    }
}
