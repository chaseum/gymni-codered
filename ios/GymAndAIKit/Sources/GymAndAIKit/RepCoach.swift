import Foundation

/// Selects cues from measured reps using the shared policy, without an LLM.
struct RepCoach {
    static let policy: [String: PolicyValue] = {
        let url = Bundle.module.url(forResource: "coaching_policy", withExtension: "json")!
        return try! JSONDecoder().decode([String: PolicyValue].self, from: Data(contentsOf: url))
    }()
    private(set) var baselineMs: Double?
    var lastCueMs: Double?
    private var opening: [Double] = []
    private var direction: String?
    private var streak = 0
    private var stream: String?
    private var lastTimestamp: Double?

    static var cooldownMs: Double { policy["cue_cooldown_ms"]!.number! }

    mutating func resetTiming() {
        opening = []; baselineMs = nil; direction = nil; streak = 0; stream = nil; lastTimestamp = nil
    }

    mutating func select(_ observation: CameraObservation, count: Int, target: Int?, hasIssues: Bool, clockMs: Double) -> (kind: String, text: String)? {
        let identity = "\(observation.source.rawValue):\(observation.clipId ?? ""):\(observation.timeBase ?? "")"
        let stamp = observation.sourceTimestampMs
        if identity != stream || (stamp != nil && lastTimestamp != nil && stamp! <= lastTimestamp!) { resetTiming() }
        stream = identity; lastTimestamp = stamp
        var pace: String?
        // Missing camera timestamps cannot establish a trustworthy pace baseline.
        if hasIssues || stamp == nil || observation.completedRep?.durationMs == nil || observation.completedRep!.durationMs! <= 0 {
            direction = nil; streak = 0
        } else if baselineMs == nil {
            opening.append(observation.completedRep!.durationMs!)
            if opening.count == Int(Self.policy["baseline_reps"]!.number!) { baselineMs = opening.sorted()[opening.count / 2] }
        } else {
            let ratio = observation.completedRep!.durationMs! / baselineMs!
            pace = ratio < Self.policy["fast_ratio"]!.number! ? "pace_fast" : ratio > Self.policy["slow_ratio"]!.number! ? "pace_slow" : nil
            streak = pace != nil && pace == direction ? streak + 1 : (pace == nil ? 0 : 1)
            direction = pace
        }
        guard !hasIssues, lastCueMs == nil || clockMs - lastCueMs! >= Self.cooldownMs else { return nil }
        let selected: (String, String)
        if let pace, streak >= Int(Self.policy["consecutive_pace_reps"]!.number!) {
            selected = (pace, Self.policy[pace]!.text!); streak = 0
        } else if let text = Self.countText(count, target: target) { selected = ("count", text) }
        else { return nil }
        lastCueMs = clockMs
        return selected
    }

    static func countText(_ count: Int, target: Int?) -> String? {
        let key: String
        if let target, count == target { key = "count_target" }
        else if let target, target >= 4, count == target - 2 { key = "count_near_target" }
        else if let target, target >= 4, target % 2 == 0, count == target / 2 { key = "count_halfway" }
        else if count == 1 { key = "count_first" }
        else if target == nil, count % 5 == 0 { key = "count_open" }
        else { return nil }
        return policy[key]!.text!.replacingOccurrences(of: "{count}", with: String(count))
    }
}
