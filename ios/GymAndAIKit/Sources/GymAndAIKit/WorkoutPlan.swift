import Foundation

/// Today's workout, built from the training profile, what happened last time, and the changes the person kept.
///
/// Prescriptions follow the ACSM resistance-training position stand (2009) and later volume/rest research:
/// strength 3–5 sets of 3–6 reps with 2–3 min rest on big lifts; muscle growth 3–4 sets of 6–12 (10–15 for small
/// muscles) with 1.5–2 min rest; general fitness 2–3 sets of 8–15 with 1–1.5 min rest; beginners 8–12 reps and
/// fewer sets. Multi-joint lifts come first. Squat and deadlift days alternate so each lift gets heavy work about
/// twice a week without both being trained hard in one session.
public struct WorkoutPlan: Equatable, Sendable {
    public struct Item: Equatable, Sendable, Identifiable {
        public let exercise: Exercise
        public let sets: Int
        /// Top of the rep range: the set's target (it ends there, then rests).
        public let reps: Int
        public let restSeconds: Int
        /// Bottom of the rep range; nil means a fixed rep count.
        public var low: Int? = nil
        /// A change carried over from the last workout ("Add weight", "Form focus: …").
        public var note: String? = nil
        public var id: Exercise { exercise }
        public var range: ClosedRange<Int> { min(low ?? reps, reps)...reps }
    }

    /// One set to perform, in order.
    public struct Step: Equatable, Sendable {
        public let exercise: Exercise
        public let set: Int
        public let sets: Int
        public let reps: Int
        public let restSeconds: Int
    }

    public let title: String
    public let items: [Item]
    /// Workouts per week the person said they could keep.
    public let weeklyGoal: Int

    public var steps: [Step] {
        items.flatMap { item in
            (1...item.sets).map { Step(exercise: item.exercise, set: $0, sets: item.sets, reps: item.reps, restSeconds: item.restSeconds) }
        }
    }

    /// Rough length: about 4 s a rep plus rest, plus a 5-minute warm-up, to the nearest 5 minutes.
    public var minutes: Int {
        let seconds = steps.reduce(300) { $0 + $1.reps * 4 + $1.restSeconds }
        return max(5, Int((Double(seconds) / 300).rounded()) * 5)
    }

    public static func make(for profile: TrainingProfile?, history: [CompletedWorkout] = [],
                            adjustments: [PlanAdjustment] = []) -> WorkoutPlan {
        make(focus: profile?.focus ?? .fitness, answers: profile?.answers ?? [:], history: history, adjustments: adjustments)
    }

    public static func make(focus: TrainingFocus, answers: [String: String], history: [CompletedWorkout] = [],
                            adjustments: [PlanAdjustment] = []) -> WorkoutPlan {
        let squatDay = history.count.isMultiple(of: 2)  // A/B alternation: squat day, then deadlift day
        var title: String
        var items: [Item]
        switch focus {
        case .strength:
            title = squatDay ? "Strength · Squat Day" : "Strength · Deadlift Day"
            items = squatDay
                ? [Item(exercise: .squat, sets: 4, reps: 6, restSeconds: 180, low: 4),
                   Item(exercise: .curl, sets: 3, reps: 10, restSeconds: 90, low: 8)]
                : [Item(exercise: .deadlift, sets: 3, reps: 5, restSeconds: 180, low: 3),
                   Item(exercise: .squat, sets: 3, reps: 8, restSeconds: 150, low: 6),
                   Item(exercise: .curl, sets: 3, reps: 10, restSeconds: 90, low: 8)]
        case .muscle:
            title = squatDay ? "Muscle · Squat Day" : "Muscle · Deadlift Day"
            items = squatDay
                ? [Item(exercise: .squat, sets: 4, reps: 12, restSeconds: 120, low: 8),
                   Item(exercise: .curl, sets: 3, reps: 15, restSeconds: 75, low: 10)]
                : [Item(exercise: .deadlift, sets: 3, reps: 10, restSeconds: 150, low: 6),
                   Item(exercise: .squat, sets: 3, reps: 12, restSeconds: 120, low: 10),
                   Item(exercise: .curl, sets: 3, reps: 15, restSeconds: 75, low: 10)]
        case .fitness:
            title = "Full Body"
            items = [Item(exercise: .squat, sets: 3, reps: 12, restSeconds: 90, low: 10),
                     Item(exercise: .deadlift, sets: 2, reps: 10, restSeconds: 120, low: 8),
                     Item(exercise: .curl, sets: 2, reps: 15, restSeconds: 60, low: 12)]
        }
        if answers[OnboardingQuestion.equipment.rawValue] == "bodyweight" {
            // No external load: work the squat in the muscular-endurance range instead.
            title = "Bodyweight"
            items = [Item(exercise: .squat, sets: 3, reps: 20, restSeconds: 60, low: 15)]
        }
        if answers[OnboardingQuestion.experience.rawValue] == "new" {
            // Beginners: 8–12-style ranges and one set fewer while technique settles.
            items = items.map { item in
                let low = max(item.low ?? item.reps, 6)
                return Item(exercise: item.exercise, sets: max(2, item.sets - 1), reps: max(item.reps, low + 2),
                            restSeconds: item.restSeconds, low: low)
            }
        }
        if answers[OnboardingQuestion.duration.rawValue] == "20" {
            items = Array(items.prefix(2)).map { Item(exercise: $0.exercise, sets: min($0.sets, 3), reps: $0.reps,
                                                       restSeconds: min($0.restSeconds, 120), low: $0.low) }
        }
        items = items.map { item in
            guard let change = adjustments.first(where: { $0.exercise == item.exercise }) else { return item }
            return change.applied(to: item)
        }
        let days = Int(answers[OnboardingQuestion.days.rawValue] ?? "") ?? 3
        return WorkoutPlan(title: title, items: items, weeklyGoal: min(max(days, 1), 7))
    }
}

/// What happened on one exercise in a workout.
public struct ExerciseResult: Codable, Equatable, Sendable, Identifiable {
    public let exercise: Exercise
    public var reps: [Int]
    public let low: Int
    public let high: Int
    /// Coaching cue → how many times it was given.
    public var corrections: [String: Int]
    public var id: Exercise { exercise }

    public init(exercise: Exercise, reps: [Int], low: Int, high: Int, corrections: [String: Int] = [:]) {
        self.exercise = exercise; self.reps = reps; self.low = low; self.high = high; self.corrections = corrections
    }

    public var topCorrection: (cue: String, count: Int)? {
        corrections.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }.map { ($0.key, $0.value) }
    }
}

/// A finished workout, kept on this iPhone for Progress, the weekly ring and the next plan.
public struct CompletedWorkout: Codable, Equatable, Sendable, Identifiable {
    public let date: Date
    public let title: String
    public let sets: Int
    public let reps: Int
    public let durationSeconds: Int
    /// Per exercise (absent in workouts saved before this was tracked).
    public var results: [ExerciseResult]? = nil
    /// The coach's written note about this workout.
    public var note: String? = nil
    public var id: Date { date }
}
