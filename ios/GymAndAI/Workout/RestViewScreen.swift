import SwiftUI
import GymAndAIKit

struct RestViewScreen: View {
    let session: WorkoutSession
    var mascotState = MascotState.rest

    var body: some View {
        GymPage(accessibilityIdentifier: "rest-content") {
            WorkoutHeaderView(context: session.isDemo ? "Demo · Workout paused" : "Workout paused",
                              title: "Take a breath.",
                              detail: (session.snapshot?.exercise ?? session.exercise).title)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                RestCountdownView(seconds: session.restRemaining(at: context.date))
                    .padding(GymTheme.Space.page)
                    .modifier(GymSurface())
            }
            HStack(spacing: GymTheme.Space.related) {
                PipView(state: mascotState).frame(width: 80, height: 80)
                Text("Take the time you need. Water if you need it.")
                    .font(.body).foregroundStyle(GymTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if session.isDemo {
                Text("Shortened demo timer · Illustrative data")
                    .font(GymTheme.TypeStyle.detail).foregroundStyle(GymTheme.muted)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { RestControlsView(session: session) }
    }
}
