import Foundation
import Observation

@MainActor @Observable
public final class OnboardingStore {
    public var draft: OnboardingDraft { didSet { saveDraft() } }
    public private(set) var profile: TrainingProfile?
    public private(set) var skipped: Bool
    public var usesImperial: Bool {
        get { draft.imperial }
        set { draft.changeUnits(toImperial: newValue) }
    }
    public var needsOnboarding: Bool { profile == nil && !skipped }
    @ObservationIgnored private let preferences: UserDefaults
    private static let draftKey = "gymni.onboarding.draft.v1"
    private static let profileKey = "gymni.trainingProfile.v1"
    private static let skipKey = "gymni.onboarding.skipped.v1"

    public init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        profile = preferences.data(forKey: Self.profileKey).flatMap { try? JSONDecoder().decode(TrainingProfile.self, from: $0) }
        skipped = preferences.bool(forKey: Self.skipKey)
        draft = preferences.data(forKey: Self.draftKey).flatMap { try? JSONDecoder().decode(OnboardingDraft.self, from: $0) } ?? OnboardingDraft()
        draft.step = min(max(draft.step, 0), OnboardingQuestion.allCases.count + 1)
    }
    public func choose(_ choice: OnboardingChoice, for question: OnboardingQuestion) {
        draft.answers[question.rawValue] = choice.id
        draft.selectedFocus = nil
    }
    public func beginEditing() {
        guard let profile else { return }
        var edited = OnboardingDraft()
        edited.weight = profile.weightKg; edited.height = profile.heightCm; edited.sex = profile.sex
        edited.answers = profile.answers; edited.selectedFocus = profile.focus
        draft = edited
    }
    @discardableResult public func complete() -> Bool {
        guard draft.isComplete else { return false }
        let saved = TrainingProfile(draft: draft)
        guard let data = try? JSONEncoder().encode(saved) else { return false }
        preferences.set(data, forKey: Self.profileKey)
        profile = saved
        skipped = false
        preferences.removeObject(forKey: Self.skipKey)
        return true
    }
    public func skip() {
        skipped = true
        preferences.set(true, forKey: Self.skipKey)
    }
    private func saveDraft() {
        if let data = try? JSONEncoder().encode(draft) { preferences.set(data, forKey: Self.draftKey) }
    }
}
