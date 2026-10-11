import Foundation
import Testing
@testable import GymAndAIKit

@MainActor @Test func laptopLaunchSurvivesNormalRelaunch() throws {
    let suite = "workout-settings-\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let first = WorkoutSession(preferences: preferences)
    first.configureSimulatorLaunch(arguments: ["app", "--gymni-laptop", "--backend-url", "http://127.0.0.1:8000",
                                               "--session-id", "live-first", "--exercise", "squat"])
    #expect(first.consumeSimulatorAutoStartRequest())
    #expect(!first.consumeSimulatorAutoStartRequest())

    let reopened = WorkoutSession(defaultMode: .phone, preferences: preferences)
    reopened.configureSimulatorLaunch(arguments: ["app"])
    #expect(reopened.mode == .backend)
    #expect(!reopened.isDemo && !reopened.isPhone)
    #expect(reopened.backendSessionId == "live-first")
    #expect(reopened.backendAddress == "http://127.0.0.1:8000")
    #expect(reopened.inputSource == .live)
    #expect(reopened.exercise == .squat)
    #expect(reopened.audioEnabled)
    #expect(!reopened.shouldAutoStartSimulatorSession)
}

@MainActor @Test func newLaptopLaunchReplacesOldSessionAndRecordedMode() throws {
    let suite = "workout-settings-\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let previous = WorkoutSession(preferences: preferences)
    previous.mode = .backend
    previous.backendSessionId = "old-session"
    previous.inputSource = .recorded
    previous.audioEnabled = false

    let next = WorkoutSession(preferences: preferences)
    next.configureSimulatorLaunch(arguments: ["app", "--gymni-laptop", "--backend-url", "http://127.0.0.1:8000",
                                              "--session-id", "live-second", "--exercise", "curl"])
    #expect(next.backendSessionId == "live-second")
    #expect(next.inputSource == .live)
    #expect(next.audioEnabled)
    #expect(next.shouldAutoStartSimulatorSession)
    #expect(WorkoutSession(preferences: preferences).backendSessionId == "live-second")
}

@MainActor @Test func explicitDemoChoicePersistsButTokensAndWorkoutStateDoNot() async throws {
    let suite = "workout-settings-\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let session = WorkoutSession(defaultMode: .backend, preferences: preferences)
    session.token = "private-lan-token"
    session.mode = .demo
    await session.start()
    await session.end()
    let next = WorkoutSession(preferences: preferences)
    #expect(next.isDemo)
    #expect(next.token.isEmpty)
    #expect(next.snapshot == nil)
    #expect(!next.presentsWorkout)
    let data = try #require(preferences.data(forKey: WorkoutConfiguration.preferencesKey))
    #expect(!String(decoding: data, as: UTF8.self).contains("private-lan-token"))
}

@MainActor @Test func failedLaptopConnectionNeverStartsSimulatedReps() async {
    let session = WorkoutSession(defaultMode: .backend)
    session.backendAddress = ""
    await session.start()
    #expect(session.errorMessage != nil)
    #expect(session.mode == .backend)
    #expect(!session.isDemo)
    #expect(!session.presentsWorkout)
    #expect(session.snapshot == nil)
    #expect(session.repCount == 0)
}
