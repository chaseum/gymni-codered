import Foundation
import Testing
@testable import GymAndAIKit

/// The JSON fitness-ml POSTs (extra fields included, as on the wire).
private func observationJSON(_ id: String, rep: Int? = nil, exercise: String = "curl", tracking: String = "ready",
                             issues: [String] = []) -> Data {
    let body: [String: Any] = [
        "schema_version": 1, "observation_id": id, "session_id": "phone", "source": "live",
        "time_base": "capture_monotonic", "source_timestamp_ms": 1000, "exercise": exercise,
        "exercise_confidence": NSNull(), "tracking_status": tracking, "phase": "lowered",
        "completed_rep": rep.map { ["rep_index": $0, "duration_ms": 1200] as [String: Any] } ?? NSNull(),
        "measurements": ["rep_min_elbow_angle_deg": 70], "issues": issues.map { ["code": $0, "evidence": [:]] },
        "inference_provenance": "trained_model",
    ]
    return try! JSONSerialization.data(withJSONObject: body)
}

private func observation(_ id: String, rep: Int? = nil, exercise: String = "curl", tracking: String = "ready",
                         issues: [String] = []) -> CameraObservation {
    try! Contracts.decoder.decode(CameraObservation.self,
                                  from: observationJSON(id, rep: rep, exercise: exercise, tracking: tracking, issues: issues))
}

@MainActor @Test func hubCommitsTrustedRepsAndCues() {
    let hub = HubSession(sessionId: "phone")
    let store = WorkoutStore(baseURL: URL(filePath: "/"), sessionId: "phone")
    hub.onEvent = store.apply
    store.apply(hub.snapshot())
    #expect(hub.command(.start, args: CommandArgs(exercise: .curl, targetReps: 8)) == nil)
    #expect(store.snapshot?.state == .active)
    #expect(store.snapshot?.setId == "set-001")

    hub.observe(observation("o1", rep: 5, issues: ["curl.partial_range", "curl.not_a_cue"]))
    #expect(store.snapshot?.repCount == 1)
    #expect(store.snapshot?.trackingStatus == .ready)
    #expect(store.snapshot?.activeIssues == ["curl.partial_range"])
    #expect(store.lastFeedback?.text == "Let the weight come all the way down.")

    #expect(hub.observe(observation("o1", rep: 6)).duplicate)                       // same observation id
    #expect(hub.observe(observation("o2", rep: 5)).ignored == nil)                 // stale rep index
    #expect(hub.observe(observation("o3", rep: 6, exercise: "other")).ignored == "rep_not_trusted")
    #expect(store.snapshot?.repCount == 1)

    hub.observe(observation("o4", rep: 7))                                           // clean rep resolves the cue
    #expect(store.snapshot?.repCount == 2)
    #expect(store.snapshot?.activeIssues == [])
}

@MainActor @Test func hubIgnoresRepsWhilePausedEvenAfterResume() {
    let hub = HubSession(sessionId: "phone")
    let store = WorkoutStore(baseURL: URL(filePath: "/"), sessionId: "phone")
    hub.onEvent = store.apply
    store.apply(hub.snapshot())
    hub.command(.start, args: CommandArgs(exercise: .curl))
    hub.command(.rest, args: CommandArgs(restSeconds: 60))
    #expect(store.snapshot?.state == .paused)
    #expect(store.snapshot?.rest != nil)
    #expect(hub.observe(observation("p1", rep: 3)).ignored == "not_active")
    #expect(hub.command(.start) != nil)                                              // invalid transition
    hub.command(.resume)
    hub.observe(observation("p2", rep: 3))                                           // done while paused
    #expect(store.snapshot?.repCount == 0)
    hub.observe(observation("p3", rep: 4))
    #expect(store.snapshot?.repCount == 1)
}

@Test func hubServerAcceptsFitnessMLPosts() async throws {
    let port = UInt16.random(in: 20_000...40_000)
    let received = ReceivedObservations()
    let server = try HubServer(port: port) { observation in
        await received.add(observation.observationId)
        return IngestAck(accepted: true, duplicate: false, ignored: nil)
    }
    defer { server.stop() }
    try await Task.sleep(for: .milliseconds(200))  // listener comes up asynchronously

    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/api/sessions/anything/observations")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = observationJSON("wire-1", rep: 1)
    let (data, response) = try await URLSession.shared.data(for: request)
    #expect((response as? HTTPURLResponse)?.statusCode == 200)
    #expect(try Contracts.decoder.decode(IngestAck.self, from: data).accepted)
    #expect(await received.ids == ["wire-1"])

    let (_, health) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/health")!)
    #expect((health as? HTTPURLResponse)?.statusCode == 200)
}

private actor ReceivedObservations {
    var ids: [String] = []
    func add(_ id: String) { ids.append(id) }
}
