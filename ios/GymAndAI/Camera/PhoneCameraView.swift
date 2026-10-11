import SwiftUI

struct PhoneCameraView: View {
    let camera: PhoneCameraController
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color.black
            if camera.state == .ready {
                PhoneCameraPreview(camera: camera)
                    .accessibilityLabel("Live iPhone camera preview")
            }
            if camera.state != .ready {
                VStack(spacing: 12) {
                    Image(systemName: "camera").font(.largeTitle)
                    Text(camera.state.message).multilineTextAlignment(.center)
                    if camera.state == .denied {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    } else if case .failed = camera.state { retryButton }
                    else if case .interrupted = camera.state { retryButton }
                }
                .padding(24)
                .foregroundStyle(.white)
            }
        }
    }

    private var retryButton: some View {
        Button("Retry camera") { Task { await camera.start() } }
            .buttonStyle(SecondaryButtonStyle())
    }
}
