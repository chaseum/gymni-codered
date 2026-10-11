// Single source of UI state: mirrors the session's events. Never increments reps locally.
import Foundation
import Observation

@MainActor @Observable
public final class WorkoutStore {
    public private(set) var snapshot: Snapshot?
    public private(set) var coach: CoachState = .idle
    public private(set) var lastFeedback: FeedbackIssued?
    public private(set) var lastCoachingCue: CoachingCue?
    public private(set) var lastEventId = -1
    /// Hook for coach playback and haptics.
    public var onEvent: ((WorkoutEvent) -> Void)?

    public let sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
    }

    /// Public so previews/tests can feed fixture events.
    public func apply(_ event: WorkoutEvent) {
        if case .snapshot(let snap) = event.payload {   // snapshot always wins, then resets the dedupe cursor
            snapshot = snap; lastEventId = event.eventId; lastCoachingCue = nil
            onEvent?(event); return
        }
        guard event.eventId > lastEventId else { return }  // duplicate/replayed
        lastEventId = event.eventId
        guard var s = snapshot else { return }
        switch event.payload {
        case .sessionState(let p): s.state = p.state; if p.state != .active { lastCoachingCue = nil }
        case .exerciseChanged(let p): s.exercise = p.exercise; s.setId = p.setId; s.targetReps = p.targetReps; s.repCount = 0; s.activeIssues = []; lastFeedback = nil; lastCoachingCue = nil
        case .tracking(let p): s.trackingStatus = p.status; s.source = p.source; if p.status != .ready { lastCoachingCue = nil }
        case .repCompleted(let p): s.repCount = p.repCount; lastCoachingCue = nil
        case .coach(let p): coach = p.coach
        case .coachingCue(let p): if p.isCurrent(in: s) { lastCoachingCue = p }
        case .feedbackIssued(let p):
            lastFeedback = p; lastCoachingCue = nil
            if !s.activeIssues.contains(p.issueCode) { s.activeIssues.append(p.issueCode) }
        case .feedbackImproved(let p): s.activeIssues.removeAll { $0 == p.issueCode }
        case .heartRate(let hr): s.heartRate = hr
        case .rest(let r): s.rest = r.status == .resting ? r : nil
        default: break
        }
        snapshot = s
        onEvent?(event)
    }
}
