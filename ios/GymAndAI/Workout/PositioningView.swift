import SwiftUI
import GymAndAIKit

struct PositioningView: View {
    let session: WorkoutSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GymTheme.spacing) {
                Text("DEMO · SIMULATED TRACKING").font(.subheadline).foregroundStyle(GymTheme.cyan)
                Text("Step into view.").font(.largeTitle.bold())
                CameraPreviewView(session: session)
                Text(session.exercise.positioning).font(.title3)
                Label("Simulating readiness…", systemImage: "viewfinder").foregroundStyle(GymTheme.cyan)
                Text("No camera is accessed in Demo mode. Your set starts after three seconds.")
                    .foregroundStyle(GymTheme.muted)
                Button("End workout", action: end).buttonStyle(SecondaryButtonStyle())
            }
            .padding(GymTheme.spacing)
        }
    }

    private func end() { Task { await session.end() } }
}
