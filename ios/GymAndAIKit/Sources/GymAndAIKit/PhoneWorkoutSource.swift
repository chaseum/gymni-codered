import Foundation

/// Local session events for camera/Watch use. No inference or simulated reps.
@MainActor
final class PhoneWorkoutSource {
    let sessionID = UUID().uuidString
    private var eventID = 0

    func initialSnapshot(exercise: Exercise) -> WorkoutEvent {
        event(.snapshot(Snapshot(
            state: .ready, source: .live, exercise: exercise, setId: "phone-set-1",
            repCount: 0, targetReps: nil, trackingStatus: .unassessable,
            heartRate: .unavailable, rest: nil, activeIssues: []
        )))
    }

    func event(_ payload: EventPayload) -> WorkoutEvent {
        eventID += 1
        return WorkoutEvent(
            schemaVersion: Contracts.schemaVersion, eventId: eventID,
            sessionId: sessionID, timestampMs: Int64(Date().timeIntervalSince1970 * 1_000),
            type: payload.eventType, payload: payload
        )
    }
}
