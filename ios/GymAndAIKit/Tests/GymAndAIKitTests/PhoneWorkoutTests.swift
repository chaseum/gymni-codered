import Foundation
import Testing
@testable import GymAndAIKit

@MainActor @Test func phoneWorkoutRequiresManualStartAndNeverSimulatesReps() async {
    let session = WorkoutSession()
    session.mode = .phone
    await session.start()
    #expect(session.isPositioning)
    #expect(session.snapshot?.state == .ready)
    #expect(session.targetReps == nil)
    #expect(session.snapshot?.trackingStatus == .unassessable)
    session.beginPhoneSet()
    #expect(session.snapshot?.state == .active)
    session.display = .camera
    #expect(session.repCount == 0)
    await session.pause()
    #expect(session.snapshot?.state == .paused)
    #expect(!session.isPositioning)
    await session.resume()
    #expect(session.isPositioning)
    #expect(session.snapshot?.state == .ready)
    await session.end()
    session.beginPhoneSet()
    #expect(session.snapshot?.state == .complete)
    #expect(session.repCount == 0)
    session.returnToday()
    #expect(session.completedReps == nil)
    #expect(session.completedUnmeasuredSession)
}

@Test func watchTelemetryRequiresCurrentSessionAndFreshRealMeasurement() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let valid = WatchTelemetry(workoutID: "current", bpm: 110, sampleDate: now.addingTimeInterval(-2), isRunning: true, message: "Live")
    #expect(valid.heartRate(for: "current", at: now).bpm == 110)
    #expect(valid.heartRate(for: "old", at: now).status == .unavailable)
    #expect(valid.heartRate(for: "current", at: now.addingTimeInterval(HeartRateView.maxSampleAge + 1)).status == .unavailable)
    for value in [0.0, 19, 251, .infinity, .nan] {
        let invalid = WatchTelemetry(workoutID: "current", bpm: value, sampleDate: now, isRunning: true, message: "Live")
        #expect(invalid.heartRate(for: "current", at: now).status == .unavailable)
    }
    let future = WatchTelemetry(workoutID: "current", bpm: 110, sampleDate: now.addingTimeInterval(1), isRunning: true, message: "Live")
    #expect(future.heartRate(for: "current", at: now).status == .unavailable)
    let stopped = WatchTelemetry(workoutID: "current", bpm: 110, sampleDate: now, isRunning: false, message: "Paused")
    #expect(stopped.heartRate(for: "current", at: now).status == .unavailable)
}

@MainActor @Test func pauseAndNewWorkoutRejectOldWatchHeartRate() async {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let session = WorkoutSession()
    session.mode = .phone
    await session.start()
    session.beginPhoneSet()
    let id = session.store.sessionId
    let live = WatchTelemetry(workoutID: id, bpm: 115, sampleDate: now, isRunning: true, message: "Live")
    session.receiveWatchTelemetry(live, at: now)
    #expect(session.heartRate.bpm == 115)
    let older = WatchTelemetry(workoutID: id, bpm: 90, sampleDate: now.addingTimeInterval(-1), isRunning: true, message: "Live")
    session.receiveWatchTelemetry(older, at: now)
    #expect(session.heartRate.bpm == 115)
    #expect(!session.heartRateText(at: now.addingTimeInterval(HeartRateView.maxSampleAge + 1)).contains("bpm"))
    await session.pause()
    session.receiveWatchTelemetry(live, at: now)
    #expect(session.heartRate.status == .unavailable)
    await session.end()
    session.returnToday()
    await session.start()
    #expect(session.store.sessionId != id)
    session.receiveWatchTelemetry(live, at: now)
    #expect(session.heartRate.status == .unavailable)
    await session.end()
}

@MainActor @Test func lateWatchStopCannotOverwriteNewerLiveTelemetry() async {
    let session = WorkoutSession()
    session.mode = .phone
    await session.start()
    let now = Date.now
    let live = WatchTelemetry(workoutID: session.store.sessionId, bpm: 100, sampleDate: now,
                              isRunning: true, message: "Live", emittedAt: now)
    session.receiveWatchTelemetry(live, at: now)
    let lateStop = WatchTelemetry(workoutID: session.store.sessionId, isRunning: false,
                                  message: "Paused", emittedAt: now.addingTimeInterval(-1))
    session.receiveWatchTelemetry(lateStop, at: now)
    #expect(session.heartRate.bpm == 100)
    let stopped = WatchTelemetry(workoutID: session.store.sessionId, isRunning: false,
                                 message: "Ended", emittedAt: now.addingTimeInterval(1))
    session.receiveWatchTelemetry(stopped, at: now.addingTimeInterval(1))
    #expect(session.heartRate.status == .unavailable)
    await session.end()
}

@MainActor @Test func resumedWorkoutRequiresHeartRateMeasuredAfterResume() async {
    let session = WorkoutSession()
    session.mode = .phone
    await session.start()
    session.beginPhoneSet()
    let beforePause = Date.now.addingTimeInterval(-2)
    await session.pause()
    await session.resume()
    let now = Date.now
    let old = WatchTelemetry(workoutID: session.store.sessionId, bpm: 100, sampleDate: beforePause,
                            isRunning: true, message: "Live", emittedAt: now)
    session.receiveWatchTelemetry(old, at: now)
    #expect(session.heartRate.status == .unavailable)
    let fresh = WatchTelemetry(workoutID: session.store.sessionId, bpm: 110, sampleDate: now,
                              isRunning: true, message: "Live", emittedAt: now)
    session.receiveWatchTelemetry(fresh, at: now)
    #expect(session.heartRate.bpm == 110)
    await session.end()
}
