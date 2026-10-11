import SwiftUI
import GymAndAIKit

struct CameraWorkoutOverlay: View {
    let session: WorkoutSession
    let camera: PhoneCameraController
    let toggleAudio: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GymGlassContainer {
            VStack(spacing: 12) {
                if dynamicTypeSize.isAccessibilitySize {
                    ScrollView {
                        VStack(spacing: 16) {
                            CameraWorkoutMetrics(session: session)
                            CameraCoachCaption(message: message)
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    CameraWorkoutMetrics(session: session)
                    Spacer(minLength: 8)
                    CameraCoachCaption(message: message)
                }
                CameraWorkoutControls(session: session, camera: camera, toggleAudio: toggleAudio)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var message: String {
        if session.isPhone {
            return camera.state == .ready
                ? "Camera live. Rep and form analysis pending."
                : camera.state.message
        }
        return session.coachingMessage
    }
}
