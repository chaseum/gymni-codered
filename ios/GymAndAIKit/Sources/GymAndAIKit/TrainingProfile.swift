import Foundation

public struct TrainingProfile: Codable, Equatable, Sendable {
    public let version: Int
    public let weightKg: Double?
    public let heightCm: Double?
    public let sex: String?
    public let answers: [String: String]
    public let focus: TrainingFocus
    public let completedAt: Date
    init(draft: OnboardingDraft) {
        version = 1; weightKg = draft.weightKg; heightCm = draft.heightCm; sex = draft.sex
        answers = draft.answers; focus = draft.selectedFocus ?? draft.recommendedFocus; completedAt = .now
    }
}
