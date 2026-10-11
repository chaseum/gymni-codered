import SwiftUI
import GymAndAIKit

struct ProgressViewScreen: View {
    let session: WorkoutSession

    var body: some View {
        Group {
            if let reps = session.completedReps {
                VStack(spacing: GymTheme.spacing) {
                    PipView().frame(width: 160, height: 140)
                    Text("Your last session").font(.title2.bold())
                    Text("\(reps) completed reps").font(.title)
                    Text("From this app session. Demo sessions contain simulated reps.")
                        .foregroundStyle(GymTheme.muted).multilineTextAlignment(.center)
                }
                .padding(GymTheme.spacing)
            } else {
                ContentUnavailableView("Your progress starts here", systemImage: "chart.bar", description: Text("Complete a workout to see your session recap."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GymTheme.background)
        .foregroundStyle(GymTheme.text)
    }
}
