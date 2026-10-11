import Foundation

/// A change for the next workout, suggested from the last one. People can turn each one off.
public struct PlanAdjustment: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case addLoad, reduceLoad, holdLoad, formFocus }
    public let exercise: Exercise
    public let kind: Kind
    /// A few words: "Add weight".
    public let title: String
    /// Why, in one short line: "Every set hit 12."
    public let detail: String
    /// The suggested working weight in kg, when one was logged last time.
    public let load: Double?
    public var id: Exercise { exercise }

    func applied(to item: WorkoutPlan.Item) -> WorkoutPlan.Item {
        var changed = item
        changed.note = title
        changed.weight = load ?? item.weight
        guard kind == .formFocus else { return changed }
        // Form first: two fewer reps per set so every rep can be clean.
        let low = max(3, (item.low ?? item.reps) - 2)
        return WorkoutPlan.Item(exercise: item.exercise, sets: item.sets, reps: max(low, item.reps - 2),
                                restSeconds: item.restSeconds, low: low, note: title, weight: changed.weight)
    }
}

/// A fact Gym&I has learned, with a symbol for it.
public struct Memory: Equatable, Sendable, Hashable {
    public let symbol: String
    public let text: String
    public init(symbol: String, text: String) { self.symbol = symbol; self.text = text }
}

/// The adaptive part: what to change next time, and what Gym&I knows about the person. Pure rules, no network.
public enum Coach {
    /// Double progression (ACSM): add load once every set reaches the top of the range; go lighter when sets fall
    /// below it; fix form before adding load when the same correction keeps coming up.
    public static func adjustments(from history: [CompletedWorkout], imperial: Bool = false) -> [PlanAdjustment] {
        var latest: [Exercise: ExerciseResult] = [:]
        for workout in history {  // newest first
            for result in workout.results ?? [] where latest[result.exercise] == nil && !result.reps.isEmpty {
                latest[result.exercise] = result
            }
        }
        return Exercise.allCases.compactMap { (exercise: Exercise) -> PlanAdjustment? in
            guard let result = latest[exercise] else { return nil }
            let weight = result.lastWeight
            func moved(_ steps: Double) -> Double? {
                weight.map { TrainingLoad.adjusted($0, steps: steps, exercise: exercise, imperial: imperial) }
            }
            if let top = result.topCorrection, top.count >= 3 {
                return PlanAdjustment(exercise: exercise, kind: .formFocus, title: "Form first",
                                      detail: "\(top.count)× “\(top.cue.trimmingCharacters(in: .punctuationCharacters))”", load: weight)
            }
            if result.reps.allSatisfy({ $0 >= result.high }) {
                return PlanAdjustment(exercise: exercise, kind: .addLoad, title: "Add weight",
                                      detail: "Every set hit \(result.high)", load: moved(1))
            }
            if let short = result.reps.firstIndex(where: { $0 < result.low }) {
                let steps = weight.map { -max(1, ($0 * 0.075 / TrainingLoad.step(for: exercise, imperial: imperial)).rounded()) } ?? -1
                return PlanAdjustment(exercise: exercise, kind: .reduceLoad, title: "Go lighter",
                                      detail: "Set \(short + 1): \(result.reps[short]) reps", load: moved(steps))
            }
            return PlanAdjustment(exercise: exercise, kind: .holdLoad, title: "Same weight",
                                  detail: "Aim for one more rep", load: weight)
        }
    }

    /// Short facts Gym&I has learned, for Progress.
    public static func memories(profile: TrainingProfile?, history: [CompletedWorkout], now: Date = .now,
                                imperial: Bool = false) -> [Memory] {
        var facts: [Memory] = []
        if let profile {
            var line = profile.focus.title
            if let days = profile.answers[OnboardingQuestion.days.rawValue].flatMap(Int.init) { line += ", \(days) days a week" }
            facts.append(Memory(symbol: "target", text: line))
            if let equipment = OnboardingQuestion.equipment.choices.first(where: { $0.id == profile.answers[OnboardingQuestion.equipment.rawValue] }) {
                facts.append(Memory(symbol: "dumbbell.fill", text: equipment.title))
            }
        }
        let results = history.flatMap { $0.results ?? [] }
        var cues: [String: Int] = [:]
        for result in results { cues.merge(result.corrections, uniquingKeysWith: +) }
        if let (cue, count) = cues.max(by: { $0.value < $1.value }), count > 1 {
            facts.append(Memory(symbol: "exclamationmark.bubble.fill", text: "Most common cue: \(cue.trimmingCharacters(in: .punctuationCharacters).lowercased()) (\(count)×)"))
        }
        for exercise in Exercise.allCases {
            let mine = results.filter { $0.exercise == exercise }
            if let heaviest = mine.compactMap(\.lastWeight).max() {
                facts.append(Memory(symbol: "trophy.fill", text: "Heaviest \(exercise.displayName.lowercased()): \(TrainingLoad.text(heaviest, imperial: imperial))"))
            } else if let best = mine.flatMap(\.reps).max() {
                facts.append(Memory(symbol: "trophy.fill", text: "Best \(exercise.displayName.lowercased()) set: \(best) reps"))
            }
        }
        let fortnight = history.filter { now.timeIntervalSince($0.date) < 14 * 86_400 }.count
        if fortnight > 0 { facts.append(Memory(symbol: "flame.fill", text: "\(fortnight) workout\(fortnight == 1 ? "" : "s") in the last two weeks")) }
        return facts
    }

    /// Instant line for the rest screen, before (or instead of) a written one.
    public static func restLine(name: String?, result: ExerciseResult?, set: Int, next: WorkoutPlan.Step?) -> String {
        let you = name.map { ", \($0)" } ?? ""
        guard let result, let reps = result.reps.last else { return "Breathe and reset\(you)." }
        if let cue = result.topCorrection?.cue {
            return "\(reps) reps\(you). Next set, think: \(cue.lowercased().trimmingCharacters(in: .punctuationCharacters))."
        }
        if reps >= result.high { return "\(reps) of \(result.high)\(you). Top of the range." }
        if reps < result.low { return "\(reps) reps\(you), under \(result.low). Take the full rest." }
        return "\(reps) reps\(you), in the \(result.low)–\(result.high) range."
    }

    /// Instant recap line, before (or instead of) a written one.
    public static func recapLine(name: String?, results: [ExerciseResult]) -> String {
        let you = name.map { ", \($0)" } ?? ""
        let sets = results.reduce(0) { $0 + $1.reps.count }
        guard sets > 0 else { return "Every session counts\(you)." }
        let inRange = results.reduce(0) { total, result in total + result.reps.filter { $0 >= result.low }.count }
        return inRange == sets ? "All \(sets) sets in range\(you)." : "\(inRange) of \(sets) sets in range\(you). The next plan adjusts."
    }

    /// The prompt for the hosted writer: facts only, one or two sentences back.
    public static func prompt(task: String, name: String?, profile: TrainingProfile?, results: [ExerciseResult],
                              adjustments: [PlanAdjustment] = []) -> String {
        var lines = ["You write short lines inside the Gym&I workout app, speaking directly to the person.",
                     "Rules: \(task) One sentence, at most 14 words, and it must mention one real number from the data. Specific, plain words, no questions, no emojis, no medical advice."]
        if let name, !name.isEmpty { lines.append("Name: \(name)") }
        if let profile { lines.append("Goal: \(profile.focus.title)") }
        for result in results {
            var line = "\(result.exercise.displayName): sets of \(result.reps.map(String.init).joined(separator: ", ")) reps (range \(result.low)–\(result.high))"
            if !result.corrections.isEmpty {
                line += "; corrections: " + result.corrections.map { "\($0.key) ×\($0.value)" }.sorted().joined(separator: "; ")
            }
            lines.append(line)
        }
        for change in adjustments { lines.append("Planned change for \(change.exercise.displayName): \(change.title) (\(change.detail)).") }
        return lines.joined(separator: "\n")
    }

    /// Keeps a model reply to one statement: drops questions, markdown, extra sentences, and overlong text.
    public static func clean(_ reply: String) -> String? {
        let text = reply.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "\n", with: " ")
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            guard let sentence = sentence?.trimmingCharacters(in: .whitespaces), !sentence.isEmpty,
                  !sentence.hasSuffix("?") else { return }
            sentences.append(sentence)
        }
        guard let first = sentences.first else { return nil }
        return first.count > 140 ? String(first.prefix(137)) + "…" : first
    }
}

/// Writes personalized lines with the hosted coach (Gemini). Nil when offline; callers keep their rule-based line.
public enum CoachWriter {
    public static func write(_ prompt: String, baseURL: URL = URL(string: "https://gymni-coach.vercel.app")!,
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

}
