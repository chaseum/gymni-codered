import Foundation

/// Phone-owned controls for the standalone camera. Revision changes discard partial or queued reps.
public struct CameraConfiguration: Codable, Sendable {
    public var service = "gymni-phone"
    public var schemaVersion = 1
    public var workoutId: String
    public var sessionId: String
    public var setId: String
    public var exercise: Exercise
    public var state: SessionState
    public var revision: Int
}
