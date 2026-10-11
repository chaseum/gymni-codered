import SwiftUI
import GymAndAIKit

/// The working weight for an exercise: − 62.5 kg +, or "Add Weight" until one is logged.
struct WeightControl: View {
    let session: WorkoutSession
    let exercise: Exercise

    var body: some View {
        Group {
            if let kg = session.loads[exercise] {
                HStack(spacing: GymTheme.Space.inset) {
                    Button("Lighter", systemImage: "minus") { step(kg, by: -1) }
                        .buttonStyle(RoundButtonStyle(size: 40))
                    Text(TrainingLoad.text(kg, imperial: session.usesImperial))
                        .font(.title3.bold())
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .frame(minWidth: 96)
                        .accessibilityIdentifier("weight-value")
                    Button("Heavier", systemImage: "plus") { step(kg, by: 1) }
                        .buttonStyle(RoundButtonStyle(size: 40))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(exercise.title) weight")
                .accessibilityValue(TrainingLoad.text(kg, imperial: session.usesImperial))
                .accessibilityAdjustableAction { direction in
                    step(kg, by: direction == .increment ? 1 : -1)
                }
            } else {
                Button("Add Weight", systemImage: "plus") {
                    session.setLoad(TrainingLoad.starting(for: exercise, imperial: session.usesImperial), for: exercise)
                }
                .font(.subheadline.bold())
                .padding(.horizontal, GymTheme.Space.inset)
                .frame(minHeight: 40)
                .background(GymTheme.surface, in: .capsule)
                .accessibilityIdentifier("add-weight")
            }
        }
        .sensoryFeedback(.selection, trigger: session.loads[exercise])
        .animation(.snappy, value: session.loads[exercise])
    }

    private func step(_ kg: Double, by steps: Double) {
        session.setLoad(TrainingLoad.adjusted(kg, steps: steps, exercise: exercise, imperial: session.usesImperial), for: exercise)
    }
}
