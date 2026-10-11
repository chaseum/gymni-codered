import SwiftUI
import GymAndAIKit

struct RestControlsView: View {
    let session: WorkoutSession

    var body: some View {
        VStack(spacing: 10) {
            Button("Resume workout", action: resume).buttonStyle(PrimaryButtonStyle()).disabled(!session.canResume)
            Button("More time", action: moreTime).buttonStyle(SecondaryButtonStyle()).disabled(session.isSending)
            Button("End workout", action: end).buttonStyle(SecondaryButtonStyle()).disabled(session.isSending)
        }
        .padding(.horizontal, GymTheme.spacing).padding(.vertical, 12)
        .background(GymTheme.background)
    }

    private func resume() { Task { await session.resume() } }
    private func moreTime() { Task { await session.extendRest() } }
    private func end() { Task { await session.end() } }
}
