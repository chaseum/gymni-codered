import SwiftUI
import GymAndAIKit

struct PositioningView: View {
    let session: WorkoutSession
    let camera: PhoneCameraController
    let watch: WatchConnectionController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GymTheme.spacing) {
                Text(session.isPhone ? "IPHONE CAMERA" : "DEMO · SIMULATED TRACKING")
                    .font(.subheadline).foregroundStyle(GymTheme.accentText)
                Text("Step into view.").font(.largeTitle.bold())
                if session.isPhone {
                    PhoneCameraView(camera: camera).frame(height: 280)
                        .clipShape(.rect(cornerRadius: GymTheme.radius))
                    Text(camera.state.message).foregroundStyle(GymTheme.accentText)
                        .accessibilityIdentifier("phone-camera-status")
                    Button("Flip camera", systemImage: "arrow.triangle.2.circlepath.camera", action: camera.flip)
                        .frame(minHeight: 44).disabled(camera.state != .ready)
                    Text(session.exercise.positioning).font(.title3)
                    Text("Video stays on your phone and isn’t recorded. Rep counting and form feedback will connect when your trained model is ready.")
                        .foregroundStyle(GymTheme.muted)
                    if session.usesAppleWatch {
                        Text(watch.status).font(.subheadline).foregroundStyle(GymTheme.muted)
                        Button("Start Watch tracking") { Task { await watch.retry(session) } }
                            .frame(minHeight: 44)
                    }
                    Button("Start set", action: session.beginPhoneSet)
                        .buttonStyle(PrimaryButtonStyle()).disabled(camera.state != .ready)
                } else {
                    CameraPreviewView(session: session)
                    Text(session.exercise.positioning).font(.title3)
                    Label("Simulating readiness…", systemImage: "viewfinder").foregroundStyle(GymTheme.accentText)
                    Text("No camera is accessed in Demo mode. Your set starts after three seconds.")
                        .foregroundStyle(GymTheme.muted)
                }
                Button("End workout", action: end).buttonStyle(SecondaryButtonStyle())
            }
            .padding(GymTheme.spacing)
        }
    }

    private func end() { Task { await session.end() } }
}
