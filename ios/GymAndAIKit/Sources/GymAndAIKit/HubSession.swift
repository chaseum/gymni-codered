import Foundation

/// The backend's workout session, run on the phone. A camera device (Pi or laptop running `fitness-ml`) POSTs
/// observations to `HubServer`; this class alone commits reps and chooses cues. Port of `Session` in
/// backend/gymai_backend/app.py: keep the two in step.
@MainActor
public final class HubSession {
    /// Only these issue codes are ever voiced (the backend's CUES table).
    static let cues: [String: String] = [
        "curl.elbow_drift": "Keep your elbows pinned to your sides.",
        "curl.partial_range": "Let the weight come all the way down.",
        "squat.shallow_depth": "Sit a little deeper if it feels comfortable.",
        "deadlift.hips_rise_early": "Push the floor away; let your hips and chest rise together.",
        "shoulder_press.incomplete_lockout": "Press all the way up until your arms are straight overhead.",
        "triceps_extension.incomplete_extension": "Straighten your arms fully at the top of each rep.",
        "row.short_pull": "Pull your elbow further back, toward your hip.",
        "push_up.shallow_depth": "Lower your chest a little closer to the floor.",
        "push_up.hips_sagging": "Squeeze your glutes and keep your hips in line with your shoulders.",
        "push_up.hips_piked": "Lower your hips so your body forms a straight line.",
        "side_bend.partial_range": "Bend a little further to the side, keeping your hips still.",
    ]

    public let sessionId: String
    public var onEvent: ((WorkoutEvent) -> Void)?
    private var eventCount = 0
    private var state: SessionState = .ready
    private var source: InputSource?
    private var exercise: Exercise?
    private var setNumber = 0
    private var repCount = 0
    private var targetReps: Int?
    private var load: Load?
    private var tracking: TrackingStatus?
    private var restEndsAtMs: Int64?
    private var activeIssues: [(code: String, feedbackId: String)] = []
    // ponytail: grows by one id per camera frame (~100k/hour); bound it if sessions ever run for many hours.
    private var seenObservations: Set<String> = []
    private var maxRepIndex = 0
    private var feedbackCount = 0

    public init(sessionId: String) { self.sessionId = sessionId }

    private var setId: String? { setNumber > 0 ? String(format: "set-%03d", setNumber) : nil }
    private var restView: RestView? { restEndsAtMs.map { RestView(status: .resting, endsAtMs: $0) } }

    public func snapshot() -> WorkoutEvent {
        event(.snapshot(Snapshot(
            state: state, source: source, exercise: exercise, setId: setId, repCount: repCount, targetReps: targetReps,
            trackingStatus: tracking, heartRate: .unavailable, rest: restView, activeIssues: activeIssues.map(\.code)
        )), id: eventCount)
    }

    /// Applies a phone command. Returns the backend's error string when the transition isn't allowed.
    @discardableResult
    public func command(_ intent: Intent, args: CommandArgs? = nil) -> String? {
        let allowed: [Intent: Set<SessionState>] = [
            .start: [.ready], .pause: [.active], .rest: [.active, .paused], .extendRest: [.paused],
            .resume: [.paused], .nextExercise: [.active, .paused], .end: [.ready, .active, .paused],
        ]
        guard allowed[intent]?.contains(state) == true else { return "invalid_transition:\(state.rawValue)->\(intent.rawValue)" }
        switch intent {
        case .start:
            source = args?.source ?? .live
            setState(.active)
            newSet(args)
            emit(.coach(CoachPayload(coach: .observing)))
        case .pause, .rest:
            if state != .paused { setState(.paused) }
            if intent == .rest {
                restEndsAtMs = Self.nowMs() + Int64(1_000 * (args?.restSeconds ?? 60))
                emit(.rest(restView!))
                emit(.coach(CoachPayload(coach: .resting)))
            }
        case .extendRest:
            guard let endsAt = restEndsAtMs else { return "not_resting" }
            restEndsAtMs = endsAt + Int64(1_000 * (args?.restSeconds ?? 30))
            emit(.rest(restView!))
        case .resume:  // only an explicit resume leaves rest; the timer running out never does
            setState(.active)
            if restEndsAtMs != nil {
                restEndsAtMs = nil
                emit(.rest(RestView(status: .ended, endsAtMs: nil)))
            }
            emit(.coach(CoachPayload(coach: .observing)))
        case .nextExercise:
            finishSet()
            newSet(args)
        case .end:
            finishSet()
            restEndsAtMs = nil
            setState(.complete)
            emit(.coach(CoachPayload(coach: .idle)))
        }
        return nil
    }

    @discardableResult
    public func observe(_ observation: CameraObservation) -> IngestAck {
        guard seenObservations.insert(observation.observationId).inserted else {
            return IngestAck(accepted: true, duplicate: true, ignored: nil)
        }
        guard state == .active else {
            // Still consume rep indices so reps done while paused never count after resume.
            if let rep = observation.completedRep { maxRepIndex = max(maxRepIndex, rep.repIndex) }
            return IngestAck(accepted: true, duplicate: false, ignored: "not_active")
        }
        if observation.trackingStatus != tracking {
            tracking = observation.trackingStatus
            emit(.tracking(TrackingPayload(status: observation.trackingStatus, source: observation.source)))
        }
        guard let rep = observation.completedRep, rep.repIndex > maxRepIndex else {
            return IngestAck(accepted: true, duplicate: false, ignored: nil)
        }
        maxRepIndex = rep.repIndex
        guard tracking == .ready, let exercise, let setId, observation.exercise == exercise.rawValue else {
            return IngestAck(accepted: true, duplicate: false, ignored: "rep_not_trusted")
        }
        repCount += 1
        emit(.repCompleted(RepCompleted(exercise: exercise, setId: setId, repCount: repCount,
                                        targetReps: targetReps, durationMs: rep.durationMs)))
        var issues: [String] = []
        for code in observation.issues.map(\.code) where Self.cues[code] != nil && !issues.contains(code) {
            issues.append(code)
        }
        for code in issues where !activeIssues.contains(where: { $0.code == code }) {
            feedbackCount += 1
            let feedbackId = "fb-\(feedbackCount)"
            activeIssues.append((code, feedbackId))
            // No cue id: the phone speaks the approved text (no bundled audio yet).
            emit(.feedbackIssued(FeedbackIssued(feedbackId: feedbackId, issueCode: code, cueId: nil,
                                                text: Self.cues[code]!, setId: setId, repCount: repCount)))
        }
        for issue in activeIssues where !issues.contains(issue.code) {
            emit(.feedbackImproved(FeedbackImproved(feedbackId: issue.feedbackId, issueCode: issue.code,
                                                    setId: setId, repCount: repCount)))
        }
        activeIssues.removeAll { !issues.contains($0.code) }
        return IngestAck(accepted: true, duplicate: false, ignored: nil)
    }

    private func setState(_ newState: SessionState) {
        state = newState
        emit(.sessionState(SessionStatePayload(state: newState)))
    }

    private func newSet(_ args: CommandArgs?) {
        setNumber += 1
        exercise = args?.exercise ?? exercise ?? .curl
        targetReps = args?.targetReps
        load = args?.load
        repCount = 0
        activeIssues = []
        emit(.exerciseChanged(ExerciseChanged(exercise: exercise!, setId: setId!, targetReps: targetReps)))
    }

    private func finishSet() {
        guard let setId, let exercise, repCount > 0 else { return }
        emit(.setCompleted(SetCompleted(setId: setId, exercise: exercise, repCount: repCount, load: load)))
    }

    private func emit(_ payload: EventPayload) {
        eventCount += 1
        onEvent?(event(payload, id: eventCount))
    }

    private func event(_ payload: EventPayload, id: Int) -> WorkoutEvent {
        WorkoutEvent(schemaVersion: Contracts.schemaVersion, eventId: id, sessionId: sessionId,
                     timestampMs: Self.nowMs(), type: payload.eventType, payload: payload)
    }

    private static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }
}
