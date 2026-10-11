import Foundation

enum HealthAccessState: Equatable {
    case ready
    case requesting
    case requestFinished
    case unavailable
    case failed(String)

    var message: String {
        switch self {
        case .ready: "Choose whether Gym&AI can read your heart rate."
        case .requesting: "Waiting for your choice in Apple’s permission sheet…"
        case .requestFinished: "Permission request finished. You can review or change Heart Rate access for Gym&AI in the Health app."
        case .unavailable: "Apple Health is unavailable on this device."
        case .failed(let message): message
        }
    }
}
