import SwiftUI
import GymAndAIKit

struct WorkoutControlsView: View {
    let session: WorkoutSession

    var body: some View {
        GymActionDock {
            if session.isSending { PendingWorkoutActionView() }
            Button("Pause", systemImage: "pause.fill", action: pause)
                .buttonStyle(PrimaryButtonStyle()).disabled(session.isSending)
            Button("End workout", action: end)
                .buttonStyle(SecondaryButtonStyle()).disabled(session.isSending)
        }
    }

    private func pause() { Task { await session.pause() } }
    private func end() { Task { await session.end() } }
}
