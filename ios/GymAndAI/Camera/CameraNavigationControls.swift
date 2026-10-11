import SwiftUI
import GymAndAIKit

struct CameraNavigationControls: View {
    let session: WorkoutSession
    let camera: PhoneCameraController
    let toggleAudio: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("Reps", systemImage: "arrow.left", action: showReps)
                .buttonStyle(SecondaryButtonStyle())
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("camera-back-to-reps")
            Button(session.audioEnabled ? "Mute coach" : "Unmute coach", systemImage: session.audioEnabled ? "speaker.wave.2" : "speaker.slash", action: toggleAudio)
                .labelStyle(.iconOnly)
                .buttonStyle(CameraAudioButtonStyle())
            if session.isPhone {
                Button("Flip camera", systemImage: "arrow.triangle.2.circlepath.camera", action: camera.flip)
                    .labelStyle(.iconOnly)
                    .buttonStyle(CameraAudioButtonStyle())
                    .disabled(camera.state != .ready)
            }
        }
    }

    private func showReps() { session.display = .reps }
}
