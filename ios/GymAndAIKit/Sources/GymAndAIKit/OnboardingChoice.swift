import Foundation

public struct OnboardingChoice: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let focus: TrainingFocus?
    public init(id: String, title: String) {
        self.id = id; self.title = title; self.detail = ""; self.focus = nil
    }
    init(_ id: String, _ title: String, _ detail: String = "", focus: TrainingFocus? = nil) {
        self.id = id; self.title = title; self.detail = detail; self.focus = focus
    }
}
