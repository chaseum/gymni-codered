import SwiftUI
import GymAndAIKit

struct CameraWorkoutOverlay: View {
    let session: WorkoutSession
    let camera: PhoneCameraController
    let toggleAudio: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: GymTheme.Space.related) {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    VStack(spacing: GymTheme.Space.inset) {
                        CameraWorkoutMetrics(session: session)
                        CameraCoachCaption(message: message, status: captionStatus)
                    }
                    .padding(.vertical, 2)
                }
                .accessibilityIdentifier("camera-workout-details")
            } else {
                CameraWorkoutMetrics(session: session)
                Spacer(minLength: GymTheme.Space.small)
                CameraCoachCaption(message: message, status: captionStatus)
            }
            if session.isSending { PendingWorkoutActionView() }
            CameraWorkoutControls(session: session, camera: camera, toggleAudio: toggleAudio)
        }
        .padding(.horizontal, GymTheme.Space.section)
        .padding(.vertical, GymTheme.Space.related)
    }

    private var captionStatus: String? {
        if session.audioEnabled, let status = session.voiceStatus { return status }
        return session.isPhone ? nil : session.trackingMessage
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
