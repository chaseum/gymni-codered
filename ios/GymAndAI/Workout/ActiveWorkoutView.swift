import SwiftUI
import GymAndAIKit

struct ActiveWorkoutView: View {
    @Bindable var session: WorkoutSession
    let camera: PhoneCameraController
    var mascotState = MascotState.idle

    var body: some View {
        GymPage {
            WorkoutHeaderView(context: "Current set",
                              title: (session.snapshot?.exercise ?? session.exercise).title)
            Picker("Workout view", selection: $session.display) {
                ForEach(WorkoutDisplay.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            .accessibilityIdentifier("workout-view-picker")
            VStack(alignment: .leading, spacing: GymTheme.Space.related) {
                SessionStatusView(session: session)
                if session.isPhone {
                    Text(camera.state.message).font(GymTheme.TypeStyle.detail).foregroundStyle(GymTheme.muted)
                    if camera.state != .ready {
                        Button("Retry camera") { Task { await camera.start() } }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    UnmeasuredRepsView()
                } else {
                    RepCounterView(count: session.repCount, target: session.targetReps)
                }
                if !session.isDemo, let setID = session.snapshot?.setId {
                    Text("Set \(setID)").font(GymTheme.TypeStyle.detail).foregroundStyle(GymTheme.muted)
                }
            }
            .padding(GymTheme.Space.section)
            .modifier(GymSurface())
            CoachMessageView(session: session, mascotState: mascotState,
                             message: session.isPhone && camera.state != .ready ? camera.state.message : nil)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: GymTheme.Space.tight) {
                    Label("Apple Watch", systemImage: "heart")
                        .font(GymTheme.TypeStyle.label)
                    Text(session.heartRateText(at: context.date))
                        .font(GymTheme.TypeStyle.detail).foregroundStyle(GymTheme.muted)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { WorkoutControlsView(session: session) }
    }
}
