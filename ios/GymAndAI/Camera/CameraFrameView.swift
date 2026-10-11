import SwiftUI

struct CameraFrameView: View {
    let stream: CameraPreviewStream
    let date: Date
    let isDemo: Bool
    let hasURL: Bool

    var body: some View {
        Group {
            if isDemo {
                VStack(spacing: 16) {
                    Text("Simulated camera view").font(.headline)
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 64)).foregroundStyle(GymTheme.accentText).accessibilityHidden(true)
                }
                .padding(.bottom, 44)
            } else if let image = stream.image, let frameDate = stream.frameDate, date.timeIntervalSince(frameDate) < 3 {
                GeometryReader { geometry in
                    Image(decorative: image, scale: 1)
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .accessibilityLabel("Live webcam preview")
                        .accessibilityHidden(false)
                }
            } else {
                ContentUnavailableView(
                    "Camera preview unavailable", systemImage: "video.slash",
                    description: Text(hasURL ? stream.image != nil ? "The feed is stale. Waiting for a new frame." : stream.status : "Configure the laptop’s MJPEG preview URL in Settings.")
                )
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
