import Foundation
import Testing
@testable import GymAndAIKit

@MainActor @Test func displaySwitchPreservesBackendSnapshot() throws {
    let session = WorkoutSession()
    #expect(session.targetReps == nil)
    let events = try steps("catalog.json", kind: "event").map { try Contracts.decoder.decode(WorkoutEvent.self, from: $0) }
    events.forEach(session.store.apply)
    let before = session.snapshot
    session.display = .camera
    #expect(session.snapshot == before)
    session.display = .reps
    #expect(session.snapshot == before)
}

@MainActor @Test func simulatedEventsUseTheSameEnvelopeTypesAsBackendEvents() {
    let source = DemoWorkoutSource()
    let snapshot = source.initialSnapshot(exercise: .curl)
    let paused = source.event(.sessionState(SessionStatePayload(state: .paused)))
    #expect(snapshot.type == "session.snapshot")
    #expect(paused.type == "session.state")
    #expect(paused.eventId > snapshot.eventId)
    #expect(paused.sessionId == snapshot.sessionId)
}

@MainActor @Test func restExpiryRequiresExplicitResumeAndPauseCancelsPositioning() async {
    let session = WorkoutSession()
    await session.start()
    #expect(session.isPositioning)
    await session.pause()
    #expect(session.snapshot?.state == .paused)
    #expect(session.restRemaining(at: Date().addingTimeInterval(60)) == 0)
    try? await Task.sleep(for: .seconds(3.2))
    #expect(session.snapshot?.state == .paused)
    #expect(session.repCount == 0)
    #expect(!session.isPositioning)
    await session.resume()
    #expect(session.isPositioning)
    await session.end()
}

@MainActor @Test func endingBeforeTrackingNeverStartsDelayedDemo() async {
    let session = WorkoutSession()
    await session.start()
    await session.end()
    try? await Task.sleep(for: .seconds(3.2))
    #expect(session.snapshot?.state == .complete)
    #expect(session.repCount == 0)
    #expect(!session.isPositioning)
}

@MainActor @Test func missingAndExpiredHeartRateNeverShowFreshBPM() throws {
    let session = WorkoutSession()
    #expect(session.heartRateText(at: .now) == "Heart rate unavailable")
    let events = try steps("catalog.json", kind: "event").map { try Contracts.decoder.decode(WorkoutEvent.self, from: $0) }
    events.forEach(session.store.apply)
    let timestamp = try #require(session.snapshot?.heartRate.sampleTimestampMs)
    let sampleDate = Date(timeIntervalSince1970: Double(timestamp) / 1_000)
    #expect(session.heartRateText(at: sampleDate).contains("bpm"))
    #expect(!session.heartRateText(at: sampleDate.addingTimeInterval(11)).contains("bpm"))
}

@Test func multipartDecoderHandlesSplitFramesAndBoundsCorruptInput() {
    var decoder = MJPEGFrameDecoder(maximumFrameBytes: 8)
    let bytes: [UInt8] = [13, 10, 0xff, 0xd8, 1, 2, 0xff, 0xd9, 13, 10, 0xff, 0xd8, 3, 0xff, 0xd9]
    let frames = bytes.compactMap { decoder.append($0) }
    #expect(frames == [Data([0xff, 0xd8, 1, 2, 0xff, 0xd9]), Data([0xff, 0xd8, 3, 0xff, 0xd9])])
    let corrupt: [UInt8] = [0xff, 0xd8] + Array(repeating: 1, count: 20)
    #expect(corrupt.compactMap { decoder.append($0) }.isEmpty)
    let recovered = [UInt8](arrayLiteral: 0xff, 0xd8, 4, 0xff, 0xd9).compactMap { decoder.append($0) }
    #expect(recovered == [Data([0xff, 0xd8, 4, 0xff, 0xd9])])
}

@MainActor @Test func lastRecapKeepsItsSourceAfterSetupChanges() async {
    let session = WorkoutSession()
    session.exercise = .squat
    await session.start()
    await session.end()
    session.returnToday()
    session.mode = .backend
    session.exercise = .deadlift
    session.inputSource = .recorded
    #expect(session.completedMode == .demo)
    #expect(session.completedExercise == .squat)
    #expect(session.completedReps == 0)
    #expect(!session.completedUnmeasuredSession)
    session.mode = .phone
    await session.start()
    #expect(session.completedMode == nil)
    await session.end()
    session.returnToday()
    session.mode = .demo
    #expect(session.completedMode == .phone)
    #expect(session.completedExercise == .deadlift)
    #expect(session.completedReps == nil)
    #expect(session.completedUnmeasuredSession)
}

@MainActor @Test func invalidBackendHeartRateIsUnavailable() {
    let session = WorkoutSession()
    let demo = DemoWorkoutSource()
    session.store.apply(demo.initialSnapshot(exercise: .curl))
    let now = Date.now
    for bpm in [0.0, 19, 251, Double.infinity, Double.nan] {
        let rate = HeartRateView(status: .live, bpm: bpm, sampleId: "invalid",
                                 sampleTimestampMs: Int64(now.timeIntervalSince1970 * 1_000), source: "apple_watch")
        session.store.apply(demo.event(.heartRate(rate)))
        #expect(session.heartRateText(at: now) == "Heart rate unavailable")
    }
}
