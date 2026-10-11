import SwiftUI
import GymAndAIKit

struct CameraWorkoutControls: View {
    let session: WorkoutSession
    let camera: PhoneCameraController
    let toggleAudio: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                CameraNavigationControls(session: session, camera: camera, toggleAudio: toggleAudio)
                Spacer(minLength: 12)
                CameraSessionControls(session: session)
            }
            VStack(spacing: 8) {
                CameraNavigationControls(session: session, camera: camera, toggleAudio: toggleAudio)
                    .frame(maxWidth: .infinity, alignment: .leading)
                CameraSessionControls(session: session)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .disabled(session.isSending)
    }
}
