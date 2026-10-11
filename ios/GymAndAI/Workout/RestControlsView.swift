import SwiftUI
import GymAndAIKit

struct RestControlsView: View {
    let session: WorkoutSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GymActionDock {
            if session.isSending { PendingWorkoutActionView() }
            Button("Resume workout", systemImage: "play.fill", action: resume)
                .buttonStyle(PrimaryButtonStyle()).disabled(!session.canResume)
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: GymTheme.Space.small))
                : AnyLayout(HStackLayout(spacing: GymTheme.Space.small))
            layout {
                Button("More time", action: moreTime).buttonStyle(SecondaryButtonStyle())
                Button("End workout", action: end).buttonStyle(SecondaryButtonStyle())
            }
            .disabled(session.isSending)
        }
    }

    private func resume() { Task { await session.resume() } }
    private func moreTime() { Task { await session.extendRest() } }
    private func end() { Task { await session.end() } }
}
