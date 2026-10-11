import Foundation

/// An explicitly simulated source. The UI still renders the shared event contract.
@MainActor
final class DemoWorkoutSource {
    private var eventId = 0
    private let sessionId = "phone-demo"

    func initialSnapshot(exercise: Exercise) -> WorkoutEvent {
        let snapshot = Snapshot(
            state: .ready, source: nil, exercise: exercise, setId: "demo-set-1",
            repCount: 0, targetReps: 8, trackingStatus: .lost,
            heartRate: .unavailable, rest: nil, activeIssues: []
        )
        return event(.snapshot(snapshot))
    }

    func event(_ payload: EventPayload) -> WorkoutEvent {
        eventId += 1
        return WorkoutEvent(
            schemaVersion: Contracts.schemaVersion, eventId: eventId,
            sessionId: sessionId, timestampMs: Int64(Date().timeIntervalSince1970 * 1_000),
            type: payload.eventType, payload: payload
        )
    }
}
