import Foundation

public struct HostedVoiceRequest: Codable, Sendable {
    public var kind: String
    public var code: String?
    public var repCount: Int?
    public var targetReps: Int?

    public static func prompt(_ cue: CoachVoiceCue) -> Self { Self(kind: "prompt", code: cue.rawValue) }
    public static func form(_ feedback: FeedbackIssued) -> Self { Self(kind: "form", code: feedback.issueCode) }
    public static func coaching(_ cue: CoachingCue, target: Int?) -> Self {
        Self(kind: cue.kind, repCount: cue.kind == "count" ? cue.repCount : nil, targetReps: cue.kind == "count" ? target : nil)
    }
}
