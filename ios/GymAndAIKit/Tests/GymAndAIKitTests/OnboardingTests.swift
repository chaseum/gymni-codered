import Foundation
import Testing
@testable import GymAndAIKit

private func answeredDraft(goal: String = "strength", style: String = "muscle", motivation: String = "fitness") -> OnboardingDraft {
    var draft = OnboardingDraft()
    draft.answers = ["goal": goal, "experience": "new", "activity": "seated", "days": "3", "duration": "30", "equipment": "gym", "style": style, "motivation": motivation]
    return draft
}

@Test func statedGoalWinsAndUndecidedUsersMatchTheirPreferences() {
    for focus in TrainingFocus.allCases {
        let other = focus == .strength ? "muscle" : "strength"
        #expect(answeredDraft(goal: focus.rawValue, style: other, motivation: other).recommendedFocus == focus)
    }
    #expect(answeredDraft(goal: "unsure", style: "muscle", motivation: "fitness").recommendedFocus == .muscle)
    #expect(answeredDraft(goal: "unsure", style: "fitness", motivation: "strength").recommendedFocus == .fitness)
    #expect(TrainingFocus.strength.companion == "atlas")
    #expect(TrainingFocus.muscle.companion == "flex")
    #expect(TrainingFocus.fitness.companion == "pip")
}

@Test func measurementsNeverClassifyFocusAndUnitsKeepTheSameMeasurement() throws {
    var draft = answeredDraft()
    let focus = draft.recommendedFocus
    draft.weight = 80; draft.height = 180; draft.sex = "female"
    draft.changeUnits(toImperial: true)
    #expect(abs(try #require(draft.weightKg) - 80) < 0.000001)
    #expect(abs(try #require(draft.heightCm) - 180) < 0.000001)
    #expect(draft.recommendedFocus == focus)
    draft.changeUnits(toImperial: false)
    #expect(abs(try #require(draft.height) - 180) < 0.000001)
    #expect(draft.isComplete)
    draft.weight = -1
    #expect(!draft.isComplete)
    draft.weight = nil; draft.height = nil; draft.sex = nil
    #expect(draft.isComplete)
    draft.answers["days"] = "invented"
    #expect(!draft.isComplete)
}

@MainActor @Test func onboardingDraftResumesAndConfirmedProfileSurvivesRelaunch() throws {
    let suite = "onboarding-\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let first = OnboardingStore(preferences: preferences)
    #expect(first.needsOnboarding)
    first.draft = answeredDraft()
    first.draft.step = 4
    first.draft.weight = 75
    let resumed = OnboardingStore(preferences: preferences)
    #expect(resumed.draft.step == 4 && resumed.draft.weight == 75)
    #expect(resumed.needsOnboarding)
    resumed.draft.selectedFocus = .muscle
    #expect(resumed.complete())
    let reopened = OnboardingStore(preferences: preferences)
    #expect(!reopened.needsOnboarding)
    #expect(reopened.profile?.focus == .muscle)
    #expect(reopened.profile?.weightKg == 75)
    #expect(reopened.profile?.answers["days"] == "3")
    reopened.beginEditing()
    #expect(reopened.draft.step == 0)
    #expect(reopened.draft.selectedFocus == .muscle)
    #expect(reopened.draft.answers["days"] == "3")
    #expect(reopened.profile?.focus == .muscle)
}

@MainActor @Test func skippingRetainsAnUnfinishedDraftWithoutInventingAProfile() throws {
    let suite = "onboarding-skip-\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let store = OnboardingStore(preferences: preferences)
    store.draft.answers["goal"] = "fitness"
    store.draft.step = 2
    #expect(!store.complete())
    store.skip()
    let next = OnboardingStore(preferences: preferences)
    #expect(!next.needsOnboarding && next.profile == nil)
    #expect(next.draft.step == 2 && next.draft.answers["goal"] == "fitness")
}
