import Foundation

public struct WatchWorkoutMessage: Codable, Sendable {
    public let workoutID: String
    public let commandID: String
    public let createdAtMs: Int64
    public let state: SessionState

    public init(workoutID: String, state: SessionState, commandID: String = UUID().uuidString, date: Date = .now) {
        self.workoutID = workoutID
        self.state = state
        self.commandID = commandID
        createdAtMs = Int64(date.timeIntervalSince1970 * 1_000)
    }
}
