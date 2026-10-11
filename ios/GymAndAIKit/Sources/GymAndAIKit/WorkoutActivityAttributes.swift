#if os(iOS)
import ActivityKit
import Foundation

/// Lock Screen and Dynamic Island workout status, shared by the app and its widget extension.
public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var bpm: Int?
        public var reps: Int
        public var targetReps: Int?
        public var status: String
        /// Active coaching cue, "Good form", or nil when form isn't measured (iPhone camera mode).
        public var form: String?
        public var formIssue: Bool
        public var restEndsAt: Date?

        public init(bpm: Int?, reps: Int, targetReps: Int?, status: String,
                    form: String? = nil, formIssue: Bool = false, restEndsAt: Date? = nil) {
            self.bpm = bpm
            self.reps = reps
            self.targetReps = targetReps
            self.status = status
            self.form = form
            self.formIssue = formIssue
            self.restEndsAt = restEndsAt
        }
    }

    public var exercise: String

    public init(exercise: String) { self.exercise = exercise }
}
#endif
