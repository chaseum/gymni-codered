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
                    CompanionStage(state: mascotState)
                        .frame(maxWidth: 260)
                    VStack(spacing: GymTheme.Space.tight) {
                        Text("Workout Complete").font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text(session.plan.title).foregroundStyle(GymTheme.muted)
                    }
                    Grid(horizontalSpacing: GymTheme.Space.related) {
                        GridRow {
                            stat("Time", session.elapsed(at: completedAt))
                            stat("Sets", "\(session.setsDone)")
                            stat("Reps", "\(session.totalReps)")
                        }
                    }
                    if let note {
                        (Text("\(companion.name)  ").bold().foregroundStyle(GymTheme.accentText) + Text(note))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("recap-note")
                    }
                    if !nextTime.isEmpty {
                        VStack(alignment: .leading, spacing: GymTheme.Space.related) {
                            Text("Next Time").font(.headline)
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

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.title, design: .rounded).bold()).monospacedDigit()
            Text(label).font(.subheadline).foregroundStyle(GymTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, GymTheme.Space.inset)
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
