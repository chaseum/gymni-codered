import Foundation
import Testing
@testable import GymAndAIKit

/// Decodes the shared fixtures in contracts/fixtures so Swift can't drift from the schema silently.
let fixtures = URL(filePath: #filePath).deletingLastPathComponent()
    .appending(path: "../../../../contracts/fixtures").standardized

func steps(_ file: String, kind: String) throws -> [Data] {
    let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appending(path: file))) as! [String: Any]
    return try (obj["steps"] as! [[String: Any]]).filter { $0["kind"] as? String == kind }
        .map { try JSONSerialization.data(withJSONObject: $0["data"]!) }
}

@Test func catalogEventsDecode() throws {
    let events = try steps("catalog.json", kind: "event").map { try Contracts.decoder.decode(WorkoutEvent.self, from: $0) }
    #expect(events.count == 15)
    let unknown = events.filter { if case .unknown = $0.payload { true } else { false } }
    #expect(unknown.map(\.type) == ["some.future_type"])
}

@Test func acksAndCommandsRoundTrip() throws {
    for d in try steps("catalog.json", kind: "command_ack") { _ = try Contracts.decoder.decode(CommandAck.self, from: d) }
    for d in try steps("explicit_pause.json", kind: "command") { _ = try Contracts.decoder.decode(Command.self, from: d) }
    let cmd = Command(sessionId: "s", intent: .extendRest, args: CommandArgs(restSeconds: 30))
    let json = String(decoding: try Contracts.encoder.encode(cmd), as: UTF8.self)
    #expect(json.contains("\"command_id\"") && json.contains("\"extend_rest\"") && json.contains("\"rest_seconds\":30"))
}

@Test func heartRateSampleDecodes() throws {
    let hr = try Contracts.decoder.decode(HeartRateSample.self, from: steps("watch_hr_unavailable.json", kind: "heart_rate")[0])
    #expect(hr.source == "apple_watch" && hr.bpm == 118)
}

@MainActor @Test func storeAppliesSnapshotThenDedupes() throws {
    let store = WorkoutStore(baseURL: URL(string: "http://localhost:8000")!, sessionId: "session-001")
    let events = try steps("catalog.json", kind: "event").map { try Contracts.decoder.decode(WorkoutEvent.self, from: $0) }
    events.forEach(store.apply)
    let rep = events.first { $0.type == "rep.completed" }!
    store.apply(rep)  // replayed event must not change state
    #expect(store.snapshot?.repCount == 3)  // exercise.changed reset to 0, rep.completed set 3, replay ignored
    #expect(store.snapshot?.exercise == .deadlift)
    #expect(store.lastEventId == 15)
    #expect(store.snapshot?.heartRate.status == .live)
}
