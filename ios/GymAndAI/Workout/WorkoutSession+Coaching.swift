import GymAndAIKit

extension WorkoutSession {
    var coachingMessage: String {
        guard hasConnection else { return "Connection interrupted. Check your laptop." }
        guard snapshot?.trackingStatus == .ready else { return "Step into view so I can follow your movement." }
        if let feedback = store.lastFeedback,
           snapshot?.activeIssues.contains(feedback.issueCode) == true { return feedback.text }
        if isDemo, repCount >= 5, exercise == .curl { return "That is steadier now. Nice work." }
        return "Keep moving. I’m following your reps."
    }
}
