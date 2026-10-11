import Foundation

enum CompanionKind: String, CaseIterable, Identifiable {
    case pip, atlas, flex

    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var resource: String { self == .pip ? "Pip" : "\(name)Animated" }
    var preview: String { "\(name)Preview" }

    var focus: String {
        switch self {
        case .pip: "Feel fitter"
        case .atlas: "Get stronger"
        case .flex: "Build muscle"
        }
    }
}
