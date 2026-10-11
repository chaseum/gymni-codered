import SwiftUI
import GymAndAIKit

struct WorkoutControlsView: View {
    let session: WorkoutSession

    var body: some View {
        VStack(spacing: 10) {
            Button("Pause", systemImage: "pause.fill", action: pause)
                .buttonStyle(PrimaryButtonStyle()).disabled(session.isSending)
            Button("End workout", action: end)
                .buttonStyle(SecondaryButtonStyle()).disabled(session.isSending)
        }
        .padding(.horizontal, GymTheme.spacing).padding(.vertical, 12)
        .background(GymTheme.background)
    }

    private func pause() { Task { await session.pause() } }
    private func end() { Task { await session.end() } }
}
