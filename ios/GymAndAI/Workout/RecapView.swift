import SwiftUI
import GymAndAIKit

struct RecapView: View {
    let session: WorkoutSession
    var mascotState = MascotState.celebrate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GymTheme.spacing) {
                Text(session.isDemo ? "DEMO RECAP · SIMULATED DATA" : "SESSION RECAP")
                    .font(.subheadline).foregroundStyle(GymTheme.cyan)
                Text("You showed up.").font(.largeTitle.bold())
                PipView(state: mascotState).frame(width: 160, height: 140)
                Text((session.snapshot?.exercise ?? session.exercise).title).font(.title2)
                RepCounterView(count: session.repCount, target: session.targetReps)
                Text(session.isDemo ? "This walkthrough simulated your reps and coaching. No movement or heart rate was measured." : "These completed reps came from your laptop session.")
                    .foregroundStyle(GymTheme.muted)
                Button("Back to Today", action: session.returnToday).buttonStyle(PrimaryButtonStyle())
            }
            .padding(GymTheme.spacing)
        }
    }
}
