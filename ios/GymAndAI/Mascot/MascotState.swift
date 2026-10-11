enum MascotState: String, CaseIterable {
    case idle = "Ready"
    case coaching = "Coaching"
    case celebrate = "Celebrating"
    case rest = "Resting"
    case happy = "Happy"
    case sad = "Sad"

    var clip: String {
        switch self {
        case .idle: "idle"
        case .coaching: "encouraging"
        case .celebrate: "celebration"
        case .rest: "rest"
        case .happy: "happy"
        case .sad: "sad"
        }
    }
}
