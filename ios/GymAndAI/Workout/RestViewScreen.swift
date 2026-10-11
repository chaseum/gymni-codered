import SwiftUI
import GymAndAIKit

struct RestViewScreen: View {
    let session: WorkoutSession
    var mascotState = MascotState.rest

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GymTheme.spacing) {
                Text(session.isDemo ? "DEMO · WORKOUT PAUSED" : "WORKOUT PAUSED")
                    .font(.subheadline).foregroundStyle(GymTheme.accentText)
                Text("Take a breath.").font(.largeTitle.bold())
                PipView(state: mascotState).frame(width: 160, height: 140)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    RestCountdownView(seconds: session.restRemaining(at: context.date))
                }
                Text("Take the time you need. Water if you need it.").font(.title3)
                if session.isDemo { Text("Shortened demo timer · Illustrative data").foregroundStyle(GymTheme.muted) }
            }
            .padding(GymTheme.spacing)
        }
        .safeAreaInset(edge: .bottom) { RestControlsView(session: session) }
    }
}
