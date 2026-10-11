import Foundation

/// Settles the coach's presentation without delaying the raw tracking used to validate reps.
public struct TrackingCoach: Sendable {
    public private(set) var isReady: Bool?
    private var candidate: Bool?
    private var candidateSince: TimeInterval = 0
    private var lastSpokenReady: Bool?
    private var lastSpokenAt = -TimeInterval.infinity

    public init() {}

    public mutating func update(_ status: TrackingStatus?, at now: TimeInterval) -> CoachVoiceCue? {
        let ready = status == .ready
        if candidate != ready {
            candidate = ready
            candidateSince = now
        }
        let settled = now - candidateSince >= (ready ? 2 : 3)
        if settled { isReady = ready }
        guard settled, isReady == ready, lastSpokenReady != ready,
              now - lastSpokenAt >= 12 else { return nil }
        // Positioning already explains an initial missing view; "interrupted" requires prior spoken readiness.
        guard ready || lastSpokenReady != nil else { return nil }
        return ready ? .trackingReady : .trackingLost
    }

    public mutating func didSpeak(_ cue: CoachVoiceCue, at now: TimeInterval) {
        guard cue == .trackingReady || cue == .trackingLost else { return }
        lastSpokenReady = cue == .trackingReady
        lastSpokenAt = now
    }
}
