import Foundation

public struct WatchTelemetry: Codable, Sendable {
    public let workoutID: String
    public let bpm: Double?
    public let sampleTimestampMs: Int64?
    public let isRunning: Bool
    public let message: String
    public let emittedAtMs: Int64

    public init(workoutID: String, bpm: Double? = nil, sampleDate: Date? = nil, isRunning: Bool, message: String, emittedAt: Date = .now) {
        self.workoutID = workoutID
        self.bpm = bpm
        sampleTimestampMs = sampleDate.map { Int64($0.timeIntervalSince1970 * 1_000) }
        self.isRunning = isRunning
        self.message = message
        emittedAtMs = Int64(emittedAt.timeIntervalSince1970 * 1_000)
    }

    public func heartRate(for workoutID: String, at now: Date) -> HeartRateView {
        guard self.workoutID == workoutID, isRunning,
              let bpm, bpm.isFinite, (20...250).contains(bpm),
              let timestamp = sampleTimestampMs else { return .unavailable }
        let age = now.timeIntervalSince1970 - Double(timestamp) / 1_000
        guard age >= 0, age <= 10 else { return .unavailable }
        return HeartRateView(
            status: .live, bpm: bpm, sampleId: "\(workoutID):\(timestamp)",
            sampleTimestampMs: timestamp, source: "apple_watch"
        )
    }
}
