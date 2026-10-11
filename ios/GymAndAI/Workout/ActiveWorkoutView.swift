import SwiftUI
import GymAndAIKit

struct ActiveWorkoutView: View {
    @Bindable var session: WorkoutSession
    var mascotState = MascotState.idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GymTheme.spacing) {
                SessionStatusView(session: session)
                Text((session.snapshot?.exercise ?? session.exercise).title).font(.largeTitle.bold())
                Text(session.isDemo ? "Demo set · Illustrative data" : "Set \(session.snapshot?.setId ?? "—")")
                    .foregroundStyle(GymTheme.muted)
                Picker("Workout view", selection: $session.display) {
                    ForEach(WorkoutDisplay.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(minHeight: 44)
                .accessibilityIdentifier("workout-view-picker")
                RepCounterView(count: session.repCount, target: session.targetReps)
                CoachMessageView(session: session, mascotState: mascotState)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Label(session.heartRateText(at: context.date), systemImage: "heart")
                        .font(.subheadline).foregroundStyle(GymTheme.muted)
                }
            }
            .padding(GymTheme.spacing)
        }
        .safeAreaInset(edge: .bottom) {
            WorkoutControlsView(session: session)
        }
    }
}
