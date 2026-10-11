import SwiftUI
import GymAndAIKit

struct CameraSessionControls: View {
    let session: WorkoutSession

    var body: some View {
        HStack(spacing: 12) {
            Button("Pause", systemImage: "pause.fill", action: pause)
                .buttonStyle(PrimaryButtonStyle())
                .fixedSize(horizontal: true, vertical: false)
            Button("End", action: end)
                .buttonStyle(SecondaryButtonStyle())
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("End workout")
        }
    }

    private func pause() { Task { await session.pause() } }
    private func end() { Task { await session.end() } }
}
