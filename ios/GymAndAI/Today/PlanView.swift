import SwiftUI
import GymAndAIKit

struct PlanView: View {
    let session: WorkoutSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: GymTheme.Space.tight) {
                        Text(session.plan.title).font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text("\(session.plan.items.count) exercises, about \(session.plan.minutes) min")
                            .foregroundStyle(GymTheme.muted)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: GymTheme.Space.small, trailing: 4))
                }
                Section {
                    ForEach(session.plan.items) { item in
                        HStack(spacing: GymTheme.Space.inset) {
                            ExerciseIcon(exercise: item.exercise)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.exercise.title).font(.headline)
                                Text(item.exercise.muscles).font(.footnote).foregroundStyle(GymTheme.muted)
                                Text(item.weight.map { "\(item.sets) × \(item.rangeText) at \(TrainingLoad.text($0, imperial: session.usesImperial))" }
                                     ?? "\(item.sets) sets of \(item.rangeText) reps").font(.subheadline)
                                if let note = item.note {
                                    Text(note).font(.subheadline.bold()).foregroundStyle(GymTheme.accentText)
                                }
                            }
                            Spacer()
                            Text(Duration.seconds(item.restSeconds).formatted(.time(pattern: .minuteSecond)))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(GymTheme.muted)
                                .accessibilityLabel("Rest \(Duration.seconds(item.restSeconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide)))")
                        }
                        .padding(.vertical, GymTheme.Space.tight)
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    HStack { Text("Exercise"); Spacer(); Text("Rest") }
                } footer: {
                    Text("Rep ranges and rest follow ACSM guidance for your goal. When every set reaches the top of the range, add weight.")
                }
                .listRowBackground(GymTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(GymTheme.background.ignoresSafeArea())
            .foregroundStyle(GymTheme.text)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(action: start) { Label("Start", systemImage: "play.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, GymTheme.Space.page)
                    .padding(.vertical, GymTheme.Space.related)
                    .accessibilityLabel("Start workout")
            }
            .toolbar { Button("Done", action: dismiss.callAsFunction) }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func start() {
        dismiss()
        Task { await session.start() }
    }
}
