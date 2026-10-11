import Foundation

struct HostedVoiceConfiguration: Codable, Sendable {
    var voiceProvider: String
    var voiceRevision: String
    var voiceAvailable: Bool
}
