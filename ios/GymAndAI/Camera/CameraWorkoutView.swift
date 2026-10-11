import SwiftUI
import GymAndAIKit

struct CameraWorkoutView: View {
    @Bindable var session: WorkoutSession
    let camera: PhoneCameraController
    let toggleAudio: () -> Void
    @State private var stream = CameraPreviewStream()

    var body: some View {
        ZStack {
            GymTheme.charcoal.ignoresSafeArea()
            Group {
                if session.isPhone { PhoneCameraView(camera: camera) }
                else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        CameraFrameView(stream: stream, date: context.date, isDemo: session.isDemo, hasURL: session.previewURL != nil)
                    }
                }
            }
            .ignoresSafeArea()
            LinearGradient(
                stops: [
                    .init(color: GymTheme.charcoal.opacity(0.45), location: 0),
                    .init(color: .clear, location: 0.3),
                    .init(color: .clear, location: 0.65),
                    .init(color: GymTheme.charcoal.opacity(0.55), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            CameraWorkoutOverlay(session: session, camera: camera, toggleAudio: toggleAudio)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: session.previewURL) {
            if !session.isDemo, !session.isPhone, let url = session.previewURL { await stream.load(url) }
        }
    }
}
