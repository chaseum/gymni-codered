import Foundation

public enum TrainingFocus: String, Codable, CaseIterable, Sendable, Identifiable {
    case strength, muscle, fitness
    public var id: String { rawValue }
    public var title: String {
        switch self { case .strength: "Get stronger"; case .muscle: "Build muscle"; case .fitness: "Feel fitter" }
    }
    public var companion: String {
        switch self { case .strength: "atlas"; case .muscle: "flex"; case .fitness: "pip" }
    }
    public var detail: String {
        switch self {
        case .strength: "Atlas is your companion for strength training."
        case .muscle: "Flex is your companion for muscle growth."
        case .fitness: "Pip is your companion for general fitness."
        }
    }
}
