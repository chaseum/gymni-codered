import Foundation

/// Training loads are stored in kilograms and shown, stepped and rounded in the person's units.
public enum TrainingLoad {
    static let kgPerLb = 0.45359237

    /// The smallest sensible jump: about 5% of a typical working weight (plates on a bar, dumbbell steps).
    public static func step(for exercise: Exercise, imperial: Bool) -> Double {
        switch (exercise, imperial) {
        case (.curl, false): 1
        case (.curl, true): 2.5 * kgPerLb
        case (_, false): 2.5
        case (_, true): 5 * kgPerLb
        }
    }

    /// Where a first-time weight starts: an empty bar, or a light pair of dumbbells.
    public static func starting(for exercise: Exercise, imperial: Bool) -> Double {
        switch (exercise, imperial) {
        case (.curl, false): 10
        case (.curl, true): 20 * kgPerLb
        case (_, false): 20
        case (_, true): 45 * kgPerLb
        }
    }

    /// The load in the person's units, rounded to the nearest half unit.
    public static func value(_ kg: Double, imperial: Bool) -> Double {
        ((imperial ? kg / kgPerLb : kg) * 2).rounded() / 2
    }

    /// "62.5 kg" / "135 lb".
    public static func text(_ kg: Double, imperial: Bool) -> String {
        "\(value(kg, imperial: imperial).formatted(.number.precision(.fractionLength(0...1)))) \(imperial ? "lb" : "kg")"
    }

    /// `kg` moved by `steps` and snapped to the step grid in the person's units (never below one step).
    public static func adjusted(_ kg: Double, steps: Double, exercise: Exercise, imperial: Bool) -> Double {
        let step = step(for: exercise, imperial: imperial)
        return max(step, ((kg / step) + steps).rounded() * step)
    }
}
