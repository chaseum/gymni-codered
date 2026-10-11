import Foundation
import GymAndAIKit

extension WorkoutSession {
    var cameraConnected: Bool { cameraLastSeen.map { $0.timeIntervalSinceNow > -4 } ?? false }

    /// One short line from the coach, under the companion.
    var coachingMessage: String {
        switch coachingTrackingReady {
        case true: break
        case false: return cameraConnected ? "Step into view so I can see you." : "Connecting to your camera"
        default: return cameraConnected ? "Step into view so I can see you." : "Connecting to your camera"
        }
        if let feedback = store.lastFeedback,
           feedback.setId == snapshot?.setId,
           snapshot?.activeIssues.contains(feedback.issueCode) == true {
            let given = results.first { $0.exercise == snapshot?.exercise }?.corrections[feedback.text] ?? 0
            return given >= 2 ? "Again: \(feedback.text)" : feedback.text  // it keeps coming up; say so
        }
        if let cue = store.lastCoachingCue, cue.isCurrent(in: snapshot) { return cue.text }
        guard let target = targetReps else { return "\(repCount) reps" }
        let left = target - repCount
        return left > 0 ? "\(left) to go" : "Last one done"
    }
}

extension WorkoutSession {
    /// Beats per minute from a fresh Apple Watch sample, else nil.
    func bpm(at date: Date) -> Int? {
        let rate = heartRate
        guard rate.source == "apple_watch", rate.status == .live, let bpm = rate.bpm, bpm.isFinite, (20...250).contains(bpm),
              let timestamp = rate.sampleTimestampMs else { return nil }
        let age = date.timeIntervalSince1970 - Double(timestamp) / 1_000
        return age >= 0 && age <= HeartRateView.maxSampleAge ? Int(bpm.rounded()) : nil
    }

    func elapsed(at date: Date) -> String {
        let seconds = startedAt.map { max(0, Int(date.timeIntervalSince($0))) } ?? 0
        return Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    var repProgress: Double {
        guard let target = targetReps, target > 0 else { return 0 }
        return Double(repCount) / Double(target)
    }
}
