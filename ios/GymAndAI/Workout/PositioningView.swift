import SwiftUI
import GymAndAIKit

struct PositioningView: View {
    let session: WorkoutSession
    let camera: PhoneCameraController
    let watch: WatchConnectionController

    var body: some View {
        GymPage {
            WorkoutHeaderView(context: sourceTitle, title: "Get positioned",
                              detail: (session.snapshot?.exercise ?? session.exercise).title)
            if session.isPhone {
                PhoneCameraView(camera: camera).frame(height: 240)
                    .clipShape(.rect(cornerRadius: GymTheme.radius))
                Text(camera.state.message).font(GymTheme.TypeStyle.label)
                    .foregroundStyle(GymTheme.accentText)
                    .accessibilityIdentifier("phone-camera-status")
                Button("Flip camera", systemImage: "arrow.triangle.2.circlepath.camera", action: camera.flip)
                    .buttonStyle(SecondaryButtonStyle()).disabled(camera.state != .ready)
            } else {
                CameraPreviewView(session: session)
                SessionStatusView(session: session)
            }
            VStack(alignment: .leading, spacing: GymTheme.Space.related) {
                Label("Positioning guide", systemImage: "viewfinder").font(GymTheme.TypeStyle.label)
                Text(session.exercise.positioning).font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(GymTheme.Space.section)
            .modifier(GymSurface())
            if session.isPhone {
                Text("Video stays on your phone and isn’t recorded. Rep counting and form feedback will connect when your trained model is ready.")
                    .foregroundStyle(GymTheme.muted)
                if session.usesAppleWatch {
                    Text(watch.status).font(GymTheme.TypeStyle.detail).foregroundStyle(GymTheme.muted)
                    Button("Start Watch tracking") { Task { await watch.retry(session) } }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GymActionDock {
                if session.isSending { PendingWorkoutActionView() }
                if session.isPhone {
                    Button("Start set", action: session.beginPhoneSet)
                        .buttonStyle(PrimaryButtonStyle()).disabled(camera.state != .ready)
                }
                Button("End workout", action: end)
                    .buttonStyle(SecondaryButtonStyle()).disabled(session.isSending)
            }
        }
    }

    private var sourceTitle: String {
        if session.isPhone { return "iPhone camera · Unmeasured set" }
        return "Pi or laptop camera · Counted on this iPhone"
    }

    private func end() { Task { await session.end() } }
}
