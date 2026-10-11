import Foundation

public struct OnboardingDraft: Codable, Equatable, Sendable {
    public var step = 0
    public var weight: Double?
    public var height: Double?
    public var imperial = false
    public var sex: String?
    public var answers: [String: String] = [:]
    public var selectedFocus: TrainingFocus?
    public init() {}
    public var weightKg: Double? { weight.map { imperial ? $0 * 0.45359237 : $0 } }
    public var heightCm: Double? { height.map { imperial ? $0 * 2.54 : $0 } }
    public var metricsAreValid: Bool {
        (weightKg.map { $0.isFinite && (20...500).contains($0) } ?? true) &&
        (heightCm.map { $0.isFinite && (80...260).contains($0) } ?? true)
    }
    public var isComplete: Bool {
        metricsAreValid && OnboardingQuestion.allCases.allSatisfy { question in
            question.choices.contains { $0.id == answers[question.rawValue] }
        }
    }
    public var recommendedFocus: TrainingFocus {
        var scores: [TrainingFocus: Int] = [.fitness: 0, .muscle: 0, .strength: 0]
        for question in OnboardingQuestion.allCases {
            if let choice = question.choices.first(where: { $0.id == answers[question.rawValue] }), let focus = choice.focus {
                scores[focus, default: 0] += question.focusWeight
            }
        }
        // A tied or unanswered recommendation stays general; a stated goal always outweighs the other two votes.
        return [TrainingFocus.fitness, .muscle, .strength].reduce(.fitness) { best, candidate in
            scores[candidate, default: 0] > scores[best, default: 0] ? candidate : best
        }
    }
    public mutating func changeUnits(toImperial: Bool) {
        guard imperial != toImperial else { return }
        let kilograms = weightKg, centimeters = heightCm
        imperial = toImperial
        weight = kilograms.map { toImperial ? $0 / 0.45359237 : $0 }
        height = centimeters.map { toImperial ? $0 / 2.54 : $0 }
    }
}
