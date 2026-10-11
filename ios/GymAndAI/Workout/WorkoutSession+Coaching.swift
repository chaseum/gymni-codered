import GymAndAIKit

extension WorkoutSession {
    var trackingMessage: String {
        if isPhone { return "Rep and form analysis unavailable" }
        switch snapshot?.trackingStatus {
        case .ready: return "Tracking ready"
        case .lowVisibility: return "Tracking limited · Adjust your position"
        case .unassessable: return "This view cannot be assessed"
        default: return isHub ? "Waiting for camera · send to \(hubAddress ?? "this iPhone, port 8000")" : "Waiting for camera tracking"
        }
    }

    var coachingMessage: String {
        if isPhone { return "Your camera is live. Rep counting and form feedback await the trained model." }
        guard snapshot?.trackingStatus == .ready else { return "Step into view so I can follow your movement." }
        if let feedback = store.lastFeedback,
           feedback.setId == snapshot?.setId,
           snapshot?.activeIssues.contains(feedback.issueCode) == true { return feedback.text }
        if let cue = store.lastCoachingCue, cue.isCurrent(in: snapshot) { return cue.text }
        return "Keep moving. I’m following your reps."
    }
}
