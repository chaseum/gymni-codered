import Foundation
import Testing
@testable import GymAndAIKit

@MainActor @Test func coachingCuesDecodeAndRejectStaleOrUntrustedState() throws {
    let store = WorkoutStore(sessionId: "session-001")
    let snapshotData = try steps("catalog.json", kind: "event")[0]
    let event = try Contracts.decoder.decode(WorkoutEvent.self, from: snapshotData)
    guard case .snapshot(var snap) = event.payload else { Issue.record("Expected snapshot"); return }
    snap.state = .active; snap.trackingStatus = .ready; snap.setId = "set-001"; snap.repCount = 4; snap.activeIssues = []
    store.apply(WorkoutEvent(schemaVersion: 1, eventId: 10, sessionId: "session-001", timestampMs: 1_800_000_000_000,
                             type: "session.snapshot", payload: .snapshot(snap)))
    let json = #"{"schema_version":1,"event_id":11,"session_id":"session-001","timestamp_ms":1800000000000,"type":"coach.cue","payload":{"cue_id":"coach-set-001-4","kind":"count","text":"4 reps. Halfway there.","set_id":"set-001","rep_count":4}}"#
    let cueEvent = try Contracts.decoder.decode(WorkoutEvent.self, from: Data(json.utf8))
    store.apply(cueEvent)
    let cue = try #require(store.lastCoachingCue)
    #expect(cue.isCurrent(in: snap))
    snap.repCount = 5
    #expect(!cue.isCurrent(in: snap))
    snap.repCount = 4; snap.activeIssues = ["curl.partial_range"]
    #expect(!cue.isCurrent(in: snap))
    snap.activeIssues = []; snap.state = .paused
    #expect(!cue.isCurrent(in: snap))
    snap.state = .active; snap.trackingStatus = .lost
    #expect(!cue.isCurrent(in: snap))
    snap.trackingStatus = .ready; snap.setId = "set-002"
    #expect(!cue.isCurrent(in: snap))
    store.apply(WorkoutEvent(schemaVersion: 1, eventId: 12, sessionId: "session-001", timestampMs: 1_800_000_000_001,
                             type: "session.state", payload: .sessionState(SessionStatePayload(state: .paused))))
    #expect(store.lastCoachingCue == nil)
    store.apply(cueEvent) // old replay must never bring back a cue
    #expect(store.lastCoachingCue == nil)
}
