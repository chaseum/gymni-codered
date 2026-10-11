import Foundation

/// A factual count or relative pace cue selected from a committed backend rep.
public struct CoachingCue: Codable, Sendable {
    public var cueId: String
    public var kind: String
    public var text: String
    public var setId: String
    public var repCount: Int

    public func isCurrent(in snapshot: Snapshot?) -> Bool {
        snapshot?.state == .active && snapshot?.trackingStatus == .ready &&
            snapshot?.setId == setId && snapshot?.repCount == repCount &&
            snapshot?.activeIssues.isEmpty == true
    }
}
