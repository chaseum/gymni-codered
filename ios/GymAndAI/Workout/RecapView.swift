import SwiftUI
import GymAndAIKit

struct RecapView: View {
    let session: WorkoutSession
    var mascotState = MascotState.celebrate
    @AppStorage("userName") private var name = ""
    @AppStorage("companion") private var companion = CompanionKind.pip
    @Environment(OnboardingStore.self) private var onboarding
    @State private var completedAt = Date.now
    @State private var note: String?

    var body: some View {
        VStack(spacing: GymTheme.Space.related) {
            ScrollView {
                VStack(spacing: GymTheme.Space.section) {
                    CompanionStage(state: mascotState, size: .medium, pulse: 1)
                    VStack(spacing: GymTheme.Space.tight) {
                        Text("Workout Complete").font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text(session.plan.title).foregroundStyle(GymTheme.muted)
                    }
                    Grid(horizontalSpacing: GymTheme.Space.related) {
                        GridRow {
                            stat("Time", Metric(value: session.elapsed(at: completedAt), unit: ""))
                            if volume > 0 {
                                stat("Reps", Metric(value: "\(session.totalReps)", unit: ""))
                                stat("Volume", Metric(value: TrainingLoad.value(volume, imperial: session.usesImperial).formatted(.number.precision(.fractionLength(0))),
                                                      unit: session.usesImperial ? "lb" : "kg"))
                            } else {
                                stat("Sets", Metric(value: "\(session.setsDone)", unit: ""))
                                stat("Reps", Metric(value: "\(session.totalReps)", unit: ""))
                            }
                        }
                    }
                    if let note {
                        (Text("\(companion.name)  ").bold().foregroundStyle(GymTheme.muted) + Text(note))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("recap-note")
                    }
                    if !nextTime.isEmpty {
                        VStack(alignment: .leading, spacing: GymTheme.Space.related) {
                            Text("Next time").font(.headline)
                            ForEach(nextTime) { AdjustmentRow(change: $0, imperial: session.usesImperial) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(GymTheme.Space.inset)
                        .background(GymTheme.surface, in: .rect(cornerRadius: GymTheme.radius))
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            Button("Done", action: session.returnToday)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, GymTheme.Space.page)
        .padding(.bottom, GymTheme.Space.small)
        .gymPage()
        .task { await writeNote() }
    }

    /// What this workout suggests for the next one (Progress lets people turn each off).
    private var nextTime: [PlanAdjustment] {
        Coach.adjustments(from: [CompletedWorkout(date: completedAt, title: "", sets: 0, reps: 0, durationSeconds: 0,
                                                  results: session.results)], imperial: session.usesImperial)
    }

    private func writeNote() async {
        let person = name.isEmpty ? nil : name
        note = Coach.recapLine(name: person, results: session.results)
        guard let startedAt = session.startedAt, !session.results.isEmpty else { return }
        let prompt = Coach.prompt(task: "Two short sentences for the end-of-workout screen: what went well, and the one thing that will change next time.",
                                  name: person, profile: onboarding.profile, results: session.results, adjustments: nextTime)
        let written = await CoachWriter.write(prompt)
        if let written { note = written }
        session.setNote(written ?? note ?? "", workoutStartedAt: startedAt)
    }

    /// Weight × reps over every set that had a weight, in kg.
    private var volume: Double {
        session.results.reduce(0) { total, result in
            total + zip(result.reps, result.weights ?? []).reduce(0) { $0 + Double($1.0) * ($1.1 ?? 0) }
        }
    }

    private func stat(_ label: String, _ value: Metric) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.subheadline).foregroundStyle(GymTheme.muted)
            value
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(GymTheme.Space.inset)
        .background(GymTheme.surface, in: .rect(cornerRadius: GymTheme.radius))
        .accessibilityElement(children: .combine)
    }
}

extension PlanAdjustment {
    var symbol: String {
        switch kind {
        case .addLoad: "arrow.up.circle.fill"
        case .reduceLoad: "arrow.down.circle.fill"
        case .holdLoad: "equal.circle.fill"
        case .formFocus: "figure.strengthtraining.functional"
        }
    }
}
