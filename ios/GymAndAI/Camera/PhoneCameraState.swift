import Foundation

enum PhoneCameraState: Equatable, Sendable {
    case stopped, requesting, starting, ready, denied, unavailable
    case interrupted(String)
    case failed(String)

    var message: String {
        switch self {
        case .stopped: "Camera stopped"
        case .requesting: "Allow camera access to see your workout."
        case .starting: "Starting camera…"
        case .ready: "Camera ready · Movement analysis awaiting model"
        case .denied: "Camera access is off. Enable it in Settings."
        case .unavailable: "No camera available. Use a physical iPhone."
        case .interrupted(let message), .failed(let message): message
        }
    }
}
