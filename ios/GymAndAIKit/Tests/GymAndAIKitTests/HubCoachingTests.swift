import Foundation
import Testing
@testable import GymAndAIKit

private func measuredRep(_ count: Int, duration: Double = 2500, issues: [[String: Any]] = [], source: String = "live") throws -> CameraObservation {
    let body: [String: Any] = [
        "observation_id": "rep-\(count)", "session_id": "phone", "source": source,
        "exercise": "curl", "tracking_status": "ready", "time_base": "capture_monotonic",
        "source_timestamp_ms": count * 2500, "inference_provenance": "fixture",
        "completed_rep": ["rep_index": count, "duration_ms": duration], "issues": issues,
        "measurements": ["min_elbow_angle_deg": 70]
    ]
    return try Contracts.decoder.decode(CameraObservation.self, from: JSONSerialization.data(withJSONObject: body))
}

@MainActor @Test func phoneCuesUseCommittedCountsAndSustainedRelativePace() throws {
    var clock = 0.0
    let hub = HubSession(sessionId: "phone", clock: { clock })
    let store = WorkoutStore(sessionId: "phone")
    hub.onEvent = store.apply; store.apply(hub.snapshot())
    hub.command(.start, args: CommandArgs(exercise: .curl, targetReps: 8))
    for n in 1...3 { clock = Double(n) * 2500; hub.observe(try measuredRep(n)) }
    #expect(store.snapshot?.repCount == 3)
    #expect(store.lastCoachingCue == nil)
    clock = 10000; hub.observe(try measuredRep(4))
    #expect(store.lastCoachingCue?.text == "4 reps. Halfway there.")
    clock = 12500; hub.observe(try measuredRep(5, duration: 1000))
    #expect(store.lastCoachingCue == nil)
    clock = 16500; hub.observe(try measuredRep(6, duration: 1000))
    #expect(store.lastCoachingCue?.kind == "pace_fast")
    #expect(store.lastCoachingCue?.text == "Faster than your opening reps. Keep control.")
    hub.command(.rest)
    #expect(store.lastCoachingCue == nil)
    hub.command(.resume)
    clock = 24000; hub.observe(try measuredRep(7, duration: 4000))
    #expect(store.lastCoachingCue == nil) // pause discarded the baseline
    clock = 28000; hub.observe(try measuredRep(8))
    #expect(store.lastCoachingCue?.text == "8 reps. Target reached. Rest when you're ready.")
    #expect(store.snapshot?.state == .active) // reaching a target does not invent a completed set
}

@MainActor @Test func correctionsAreSpacedAndUncertainIssuesNeverBecomeAdvice() throws {
    var clock = 0.0
    let hub = HubSession(sessionId: "phone", clock: { clock })
    var feedback: [FeedbackIssued] = []
    var coaching: [CoachingCue] = []
    hub.onEvent = { if case .feedbackIssued(let cue) = $0.payload { feedback.append(cue) }; if case .coachingCue(let cue) = $0.payload { coaching.append(cue) } }
    hub.command(.start, args: CommandArgs(exercise: .curl, targetReps: 8))
    for n in 1...4 {
        clock = Double(n) * 2500
        hub.observe(try measuredRep(n, issues: [["code": "curl.partial_range", "evidence": ["probability": 0.95]], ["code": "squat.shallow_depth"]]))
    }
    #expect(feedback.count == 2)
    #expect(feedback[0].feedbackId == feedback[1].feedbackId)
    #expect(feedback[0].utteranceId != feedback[1].utteranceId)
    #expect(feedback.allSatisfy { $0.issueCode == "curl.partial_range" })
    #expect(coaching.isEmpty)
    clock = 20000
    hub.observe(try measuredRep(5, issues: [["code": "curl.elbow_drift", "evidence": ["probability": 0.2]]]))
    #expect(feedback.count == 2)
    #expect(coaching.isEmpty)
    #expect(hub.observe(try measuredRep(6, source: "recorded")).ignored == "wrong_source_or_set")
}

@MainActor @Test func phoneWorkoutJSONIncludesOnlyCommittedRepsAndTheirEvidence() async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "workout-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let hub = HubSession(sessionId: "phone", historyURL: url)
    hub.command(.start, args: CommandArgs(exercise: .curl, targetReps: 8))
    hub.observe(try measuredRep(1))
    hub.observe(try measuredRep(1))
    hub.command(.rest)
    hub.observe(try measuredRep(2))
    hub.command(.resume)
    hub.observe(try measuredRep(2))
    hub.observe(try measuredRep(3))
    hub.command(.end)
    await hub.flushHistory()
    let document = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let set = try #require((document["sets"] as? [[String: Any]])?.first)
    #expect(document["state"] as? String == "complete")
    #expect(set["expected_reps"] as? Int == 8)
    #expect(set["actual_reps"] as? Int == 2)
    #expect(set["rep_duration_ms"] as? Int == 5000)
    #expect(set["ended_at_ms"] != nil)
    let reps = try #require(set["reps"] as? [[String: Any]])
    #expect(reps.count == 2)
    let observation = try #require(reps[0]["observation"] as? [String: Any])
    #expect(observation["source_timestamp_ms"] as? Int == 2500)
    #expect(observation["inference_provenance"] as? String == "fixture")
}

@MainActor @Test func mainAppUsesPiInsteadOfSavedPhonePositioningMode() throws {
    let suite = "main-app-\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let old = WorkoutSession(defaultMode: .phone, preferences: preferences)
    old.mode = .phone; old.hostedAPIAddress = "https://example.invalid"
    let main = WorkoutSession(preferences: preferences)
    main.useMainAppConfiguration()
    #expect(main.mode == .hub)
    #expect(!main.isPhone)
    #expect(main.repCount == 0 && main.snapshot == nil)
    #expect(main.hostedAPIAddress == "https://example.invalid")
    #expect(WorkoutSession().mode == .hub)
    main.configureSimulatorLaunch(arguments: ["app", "--hosted-api-url", "http://127.0.0.1:18081"])
    #expect(main.hostedAPIAddress == "http://127.0.0.1:18081")
    #expect(!main.shouldAutoStartSimulatorSession)
}
