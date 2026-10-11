extension EventPayload {
    var eventType: String {
        switch self {
        case .snapshot: "session.snapshot"
        case .sessionState: "session.state"
        case .exerciseChanged: "exercise.changed"
        case .tracking: "tracking.status"
        case .repCompleted: "rep.completed"
        case .coach: "coach.state"
        case .coachingCue: "coach.cue"
        case .feedbackIssued: "feedback.issued"
        case .feedbackImproved: "feedback.improved"
        case .heartRate: "heart_rate.updated"
        case .userFeedbackAcknowledged: "user_feedback.acknowledged"
        case .rest: "rest.updated"
        case .setCompleted: "set.completed"
        case .prAchieved: "history.pr_achieved"
        case .deviceStatus: "device.status"
        case .unknown(let type): type
        }
    }
}
