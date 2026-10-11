import Foundation
import Testing
@testable import GymAndAIKit

@MainActor @Test func hubLaunchSurvivesNormalRelaunch() throws {
    let suite = "workout-settings-\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let first = WorkoutSession(preferences: preferences)
    first.configureSimulatorLaunch(arguments: ["app", "--gymni-hub", "--exercise", "squat"])
    #expect(first.consumeSimulatorAutoStartRequest())
    #expect(!first.consumeSimulatorAutoStartRequest())

    let reopened = WorkoutSession(defaultMode: .phone, preferences: preferences)
    reopened.configureSimulatorLaunch(arguments: ["app"])
    #expect(reopened.mode == .hub)
    #expect(reopened.isHub && !reopened.isPhone)
    #expect(reopened.exercise == .squat)
    #expect(reopened.audioEnabled)
    #expect(!reopened.shouldAutoStartSimulatorSession)
}

@MainActor @Test func settingsPersistButWorkoutStateDoesNot() async throws {
    let suite = "workout-settings-\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let session = WorkoutSession(defaultMode: .hub, preferences: preferences)
    session.mode = .phone
    session.previewAddress = "192.168.1.30:8081"
    session.audioEnabled = false
    session.usesAppleWatch = false
    await session.start()
    await session.end()

    let next = WorkoutSession(preferences: preferences)
    #expect(next.isPhone)
    #expect(next.previewAddress == "192.168.1.30:8081")
    #expect(!next.audioEnabled)
    #expect(!next.usesAppleWatch)
    #expect(next.snapshot == nil)
    #expect(!next.presentsWorkout)
}

@MainActor @Test func unreadableSavedSettingsFallBackToDefaults() throws {
    let suite = "workout-settings-\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let removedMode = #"{"mode":"Laptop","exercise":"curl","previewAddress":"","audioEnabled":true,"usesAppleWatch":true}"#
    preferences.set(Data(removedMode.utf8), forKey: WorkoutConfiguration.preferencesKey)
    #expect(WorkoutSession(defaultMode: .phone, preferences: preferences).mode == .phone)
}
