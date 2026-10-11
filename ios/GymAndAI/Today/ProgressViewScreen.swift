import SwiftUI
import GymAndAIKit

struct ProgressViewScreen: View {
    let session: WorkoutSession

    var body: some View {
        List {
            Section {
                HStack(spacing: GymTheme.Space.page) {
                    ZStack {
                        Circle().stroke(GymTheme.ringTrack, lineWidth: 12)
                        Circle()
                            .trim(from: 0, to: min(Double(done) / Double(goal), 1))
                            .stroke(GymTheme.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 76, height: 76)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This Week").font(.subheadline).foregroundStyle(GymTheme.muted)
                        Text("\(done)/\(goal)").font(.system(.largeTitle, design: .rounded).bold()).monospacedDigit()
                        Text("workouts").font(.subheadline).foregroundStyle(GymTheme.muted)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("This week, \(done) of \(goal) workouts")
                }
                .padding(.vertical, GymTheme.Space.small)
            }
            .listRowBackground(GymTheme.surface)

            Section("History") {
                if session.history.isEmpty {
                    Text("Finished workouts appear here.").foregroundStyle(GymTheme.muted)
                }
                ForEach(session.history) { workout in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(workout.title).font(.headline)
                            Spacer()
                            Text(workout.date, format: .dateTime.month(.abbreviated).day())
                                .font(.subheadline).foregroundStyle(GymTheme.muted)
                        }
                        Text("\(workout.sets) sets · \(workout.reps) reps · \(Duration.seconds(workout.durationSeconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))")
                            .font(.subheadline).foregroundStyle(GymTheme.muted)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }
            .listRowBackground(GymTheme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(GymTheme.background.ignoresSafeArea())
        .foregroundStyle(GymTheme.text)
    }

    private var done: Int { session.workoutsThisWeek() }
    private var goal: Int { session.plan.weeklyGoal }
}
