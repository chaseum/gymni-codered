import SwiftUI
import GymAndAIKit

/// Summary-style cards: this week, what changes next time, how the last session went, and what Gym&I remembers.
struct ProgressViewScreen: View {
    let session: WorkoutSession
    @Environment(OnboardingStore.self) private var onboarding
    @AppStorage("companion") private var companion = CompanionKind.pip
    @AppStorage("userName") private var name = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GymTheme.Space.section) {
                weekCard
                if !session.nextAdjustments.isEmpty {
                    header("Next Workout")
                    card {
                        ForEach(Array(session.nextAdjustments.enumerated()), id: \.element.id) { index, change in
                            if index > 0 { Divider().padding(.leading, 52) }
                            AdjustmentRow(change: change, imperial: session.usesImperial,
                                          isOn: !session.adjustmentsOff.contains(change.exercise)) {
                                session.setAdjustment(change.exercise, enabled: session.adjustmentsOff.contains(change.exercise))
                            }
                        }
                    }
                }
                if !latestResults.isEmpty {
                    header("Last Session")
                    card {
                        ForEach(Array(latestResults.enumerated()), id: \.element.id) { index, result in
                            if index > 0 { Divider() }
                            SetBars(result: result, imperial: session.usesImperial)
                        }
                    }
                }
                header("\(companion.name) Remembers")
                card {
                    if memories.isEmpty {
                        Text("Finish a workout and I’ll learn how you train.").foregroundStyle(GymTheme.muted)
                    }
                    ForEach(memories, id: \.self) { memory in
                        Label {
                            Text(memory.text)
                        } icon: {
                            Image(systemName: memory.symbol).foregroundStyle(GymTheme.accent)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if !session.history.isEmpty {
                    NavigationLink {
                        HistoryView(session: session)
                    } label: {
                        HStack {
                            Label("All Workouts", systemImage: "clock.arrow.circlepath")
                            Spacer()
                            Text("\(session.history.count)").foregroundStyle(GymTheme.muted)
                            Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(GymTheme.muted)
                        }
                        .padding(GymTheme.Space.inset)
                        .background(GymTheme.surface, in: .rect(cornerRadius: GymTheme.radius))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, GymTheme.Space.inset)
            .padding(.bottom, GymTheme.Space.page)
        }
        .gymPage()
    }

    private var weekCard: some View {
        card {
            HStack(spacing: GymTheme.Space.section) {
                ZStack {
                    Circle().stroke(GymTheme.ringTrack, lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: min(Double(done) / Double(goal), 1))
                        .stroke(GymTheme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("This Week").font(.subheadline).foregroundStyle(GymTheme.muted)
                    Text("\(done) of \(goal)").font(.system(.title, design: .rounded).bold()).monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("This week, \(done) of \(goal) workouts")
            if let note = session.history.first?.note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.muted)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.title3.bold()).padding(.top, GymTheme.Space.small).accessibilityAddTraits(.isHeader)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: GymTheme.Space.related) { content() }
            .padding(GymTheme.Space.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GymTheme.surface, in: .rect(cornerRadius: GymTheme.radius))
    }

    private var done: Int { session.workoutsThisWeek() }
    private var goal: Int { session.plan.weeklyGoal }

    /// The most recent result for each exercise.
    private var latestResults: [ExerciseResult] {
        var seen = Set<Exercise>()
        return session.history.flatMap { $0.results ?? [] }.filter { seen.insert($0.exercise).inserted }
    }

    private var memories: [Memory] {
        (name.isEmpty ? [] : [Memory(symbol: "person.fill", text: name)])
            + Coach.memories(profile: onboarding.profile, history: session.history, imperial: session.usesImperial)
    }
}

/// One change for next time: what, why, the new weight, and a check to keep it.
struct AdjustmentRow: View {
    let change: PlanAdjustment
    let imperial: Bool
    var isOn = true
    var toggle: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: GymTheme.Space.related) {
            Image(systemName: change.symbol)
                .font(.title2)
                .foregroundStyle(change.color)
                .frame(width: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(change.exercise.title).font(.headline)
                Text(change.title).font(.subheadline.bold()).foregroundStyle(change.color)
                Text(change.detail).font(.footnote).foregroundStyle(GymTheme.muted).lineLimit(1)
            }
            Spacer(minLength: GymTheme.Space.small)
            if let load = change.load {
                Text(TrainingLoad.text(load, imperial: imperial))
                    .font(.headline).monospacedDigit()
                    .foregroundStyle(isOn ? GymTheme.text : GymTheme.muted)
            }
            if let toggle {
                Button(isOn ? "Skip change" : "Keep change", systemImage: isOn ? "checkmark.circle.fill" : "circle", action: toggle)
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundStyle(isOn ? GymTheme.accent : GymTheme.muted)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("adjustment-\(change.exercise.rawValue)")
            }
        }
        .opacity(isOn ? 1 : 0.55)
        .accessibilityElement(children: .combine)
    }
}

/// Reps per set as small bars against the target, with the weight and the main cue.
private struct SetBars: View {
    let result: ExerciseResult
    let imperial: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: GymTheme.Space.small) {
            HStack {
                Text(result.exercise.title).font(.headline)
                Spacer()
                if let weight = result.lastWeight {
                    Text(TrainingLoad.text(weight, imperial: imperial)).font(.subheadline.bold()).foregroundStyle(GymTheme.muted)
                }
            }
            HStack(alignment: .bottom, spacing: GymTheme.Space.small) {
                ForEach(Array(result.reps.enumerated()), id: \.offset) { _, reps in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(reps >= result.low ? GymTheme.accent : Color.orange)
                            .frame(width: 14, height: 6 + 50 * min(Double(reps) / Double(result.high), 1))
                        Text("\(reps)").font(.caption.bold()).monospacedDigit().foregroundStyle(GymTheme.muted)
                    }
                }
                Spacer()
                Text("Target \(result.low)–\(result.high)").font(.caption).foregroundStyle(GymTheme.muted)
            }
            .frame(height: 76, alignment: .bottom)
            if let top = result.topCorrection {
                Label("\(top.cue.trimmingCharacters(in: .punctuationCharacters)) · \(top.count)×", systemImage: "exclamationmark.bubble")
                    .font(.subheadline).foregroundStyle(GymTheme.muted).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.exercise.title): sets of \(result.reps.map(String.init).joined(separator: ", ")) reps")
    }
}

/// Every finished workout.
private struct HistoryView: View {
    let session: WorkoutSession

    var body: some View {
        List(session.history) { workout in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(workout.title).font(.headline)
                    Spacer()
                    Text(workout.date, format: .dateTime.month(.abbreviated).day()).foregroundStyle(GymTheme.muted)
                }
                Text("\(workout.sets) sets · \(workout.reps) reps · \(Duration.seconds(workout.durationSeconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))")
                    .font(.subheadline).foregroundStyle(GymTheme.muted)
            }
            .listRowBackground(GymTheme.surface)
            .accessibilityElement(children: .combine)
        }
        .scrollContentBackground(.hidden)
        .background(GymTheme.background.ignoresSafeArea())
        .navigationTitle("All Workouts")
    }
}

extension PlanAdjustment {
    var color: Color {
        switch kind {
        case .addLoad: .green
        case .reduceLoad: .orange
        case .holdLoad: GymTheme.accent
        case .formFocus: .yellow
        }
    }
}
