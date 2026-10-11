import Foundation

/// A change for the next workout, suggested from the last one. People can turn each one off.
public struct PlanAdjustment: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case addLoad, reduceLoad, holdLoad, formFocus }
    public let exercise: Exercise
    public let kind: Kind
    public let title: String
    public let detail: String
    /// The short tag shown on the plan.
    public let note: String
    public var id: Exercise { exercise }

    func applied(to item: WorkoutPlan.Item) -> WorkoutPlan.Item {
        guard kind == .formFocus else {
            return WorkoutPlan.Item(exercise: item.exercise, sets: item.sets, reps: item.reps, restSeconds: item.restSeconds,
                                    low: item.low, note: note)
        }
        // Form first: two fewer reps per set, same sets, so every rep can be clean.
        let low = max(3, (item.low ?? item.reps) - 2)
        return WorkoutPlan.Item(exercise: item.exercise, sets: item.sets, reps: max(low, item.reps - 2),
                                restSeconds: item.restSeconds, low: low, note: note)
    }
}

/// The adaptive part: what to change next time, and what Gym&I knows about the person. Pure rules, no network.
public enum Coach {
    /// Double progression (ACSM): add load once every set reaches the top of the range; lighten it when sets fall
    /// below the range; fix form before adding load when the same correction keeps coming up.
    public static func adjustments(from history: [CompletedWorkout]) -> [PlanAdjustment] {
        var latest: [Exercise: ExerciseResult] = [:]
        for workout in history {  // newest first
            for result in workout.results ?? [] where latest[result.exercise] == nil && !result.reps.isEmpty {
                latest[result.exercise] = result
            }
        }
        return Exercise.allCases.compactMap { exercise in
            guard let result = latest[exercise] else { return nil }
            let name = exercise.displayName
            if let top = result.topCorrection, top.count >= 3 {
                return PlanAdjustment(exercise: exercise, kind: .formFocus, title: "\(name): form first",
                                      detail: "“\(top.cue)” came up \(top.count) times. Keep the weight, take 3 seconds on the way down, and do two fewer reps per set.",
                                      note: "Form focus")
            }
            if result.reps.allSatisfy({ $0 >= result.high }) {
                return PlanAdjustment(exercise: exercise, kind: .addLoad, title: "\(name): add weight",
                                      detail: "You reached \(result.high) reps on every set. Add about 5% (\(exercise.loadStep)) and work back up the range.",
                                      note: "Add \(exercise.loadStep)")
            }
            if let short = result.reps.firstIndex(where: { $0 < result.low }) {
                return PlanAdjustment(exercise: exercise, kind: .reduceLoad, title: "\(name): lighten the load",
                                      detail: "Set \(short + 1) stopped at \(result.reps[short]) reps, under \(result.low). Drop 5–10% so every set lands in \(result.low)–\(result.high).",
                                      note: "5–10% lighter")
            }
            return PlanAdjustment(exercise: exercise, kind: .holdLoad, title: "\(name): one more rep",
                                  detail: "Keep the same weight and aim for one more rep per set. Add weight once every set hits \(result.high).",
                                  note: "Same weight, +1 rep")
        }
    }

    /// Short facts Gym&I has learned, for Progress.
    public static func memories(profile: TrainingProfile?, history: [CompletedWorkout], now: Date = .now) -> [String] {
        var facts: [String] = []
        if let profile {
            var line = profile.focus.title
            if let days = profile.answers[OnboardingQuestion.days.rawValue].flatMap(Int.init) {
                line += ", \(days) day\(days == 1 ? "" : "s") a week"
            }
            if let minutes = profile.answers[OnboardingQuestion.duration.rawValue] { line += ", about \(minutes) min" }
            facts.append(line)
            if let equipment = OnboardingQuestion.equipment.choices.first(where: { $0.id == profile.answers[OnboardingQuestion.equipment.rawValue] }) {
                facts.append("Trains with: \(equipment.title.lowercased())")
            }
        }
        let results = history.flatMap { $0.results ?? [] }
        var cues: [String: Int] = [:]
        for result in results { cues.merge(result.corrections, uniquingKeysWith: +) }
        if let (cue, count) = cues.max(by: { $0.value < $1.value }), count > 1 {
            facts.append("Most common cue: “\(cue)” (\(count) times)")
        }
        for exercise in Exercise.allCases {
            if let best = results.filter({ $0.exercise == exercise }).flatMap(\.reps).max() {
                facts.append("Best \(exercise.displayName.lowercased()) set: \(best) reps")
            }
        }
        let fortnight = history.filter { now.timeIntervalSince($0.date) < 14 * 86_400 }.count
        if fortnight > 0 { facts.append("\(fortnight) workout\(fortnight == 1 ? "" : "s") in the last two weeks") }
        return facts
    }

    /// Instant line for the rest screen, before (or instead of) a written one.
    public static func restLine(name: String?, result: ExerciseResult?, set: Int, next: WorkoutPlan.Step?) -> String {
        let you = name.map { ", \($0)" } ?? ""
        guard let result, let reps = result.reps.last else { return "Breathe and reset\(you)." }
        if let cue = result.topCorrection?.cue {
            return "\(reps) reps\(you). Next set, think: \(cue.lowercased().trimmingCharacters(in: .punctuationCharacters))."
        }
        if reps >= result.high { return "\(reps) clean reps\(you). That set looked strong." }
        if reps < result.low { return "\(reps) reps\(you). Take the full rest before the next one." }
        return "\(reps) reps in the range\(you). Same again on the next set."
    }

    /// The prompt for the hosted writer: facts only, one or two sentences back.
    public static func prompt(task: String, name: String?, profile: TrainingProfile?, results: [ExerciseResult],
                              adjustments: [PlanAdjustment] = []) -> String {
        var lines = ["You write short lines inside the Gym&I workout app, speaking directly to the person.",
                     "Rules: \(task) Warm and specific, plain words, no questions, no emojis, no medical advice."]
        if let name, !name.isEmpty { lines.append("Name: \(name)") }
        if let profile { lines.append("Goal: \(profile.focus.title)") }
        for result in results {
            var line = "\(result.exercise.displayName): sets of \(result.reps.map(String.init).joined(separator: ", ")) reps (range \(result.low)–\(result.high))"
            if !result.corrections.isEmpty {
                line += "; corrections: " + result.corrections.map { "\($0.key) ×\($0.value)" }.sorted().joined(separator: "; ")
            }
            lines.append(line)
        }
        for change in adjustments { lines.append("Planned change: \(change.title). \(change.detail)") }
        return lines.joined(separator: "\n")
    }

    /// Keeps a model reply to at most two statements: drops questions, markdown, and overlong text.
    public static func clean(_ reply: String) -> String? {
        let text = reply.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "\n", with: " ")
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            guard let sentence = sentence?.trimmingCharacters(in: .whitespaces), !sentence.isEmpty,
                  !sentence.hasSuffix("?") else { return }
            sentences.append(sentence)
        }
        let kept = sentences.prefix(2).joined(separator: " ")
        guard !kept.isEmpty else { return nil }
        return kept.count > 240 ? String(kept.prefix(237)) + "…" : kept
    }
}

/// Writes personalized lines with the hosted coach (Gemini). Nil when offline; callers keep their rule-based line.
public enum CoachWriter {
    public static func write(_ prompt: String, baseURL: URL = URL(string: WorkoutSession.hostedAPI)!,
                             session: URLSession = .shared) async -> String? {
        var request = URLRequest(url: baseURL.appending(path: "api/coach/messages"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["message": prompt])
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let reply = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["reply"] as? String else { return nil }
        return Coach.clean(reply)
    }
}

extension Exercise {
    public var displayName: String {
        switch self {
        case .curl: "Biceps curl"
        case .squat: "Squat"
        case .deadlift: "Deadlift"
        }
    }

    /// About a 5% jump for a typical load.
    var loadStep: String {
        switch self {
        case .curl: "1–2 kg"
        case .squat, .deadlift: "2.5–5 kg"
        }
    }
}
