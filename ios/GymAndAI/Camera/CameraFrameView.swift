import SwiftUI

struct CameraFrameView: View {
    let stream: CameraPreviewStream
    let date: Date
    let isDemo: Bool
    let hasURL: Bool
    var isRecorded = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if isDemo {
                VStack(spacing: GymTheme.Space.inset) {
                    Text("Simulated camera view").font(.headline)
                    Text("Demo · No camera is running").font(.subheadline).foregroundStyle(GymTheme.muted)
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 64)).foregroundStyle(GymTheme.accentText).accessibilityHidden(true)
                }
                .padding(.bottom, 44)
                .opacity(dynamicTypeSize.isAccessibilitySize ? 0 : 1)
                .accessibilityHidden(dynamicTypeSize.isAccessibilitySize)
            } else if let image = stream.image, let frameDate = stream.frameDate, date.timeIntervalSince(frameDate) < 3 {
                GeometryReader { geometry in
                    Image(decorative: image, scale: 1)
                        .resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .accessibilityLabel(isRecorded ? "Recorded laptop camera preview" : "Laptop webcam preview")
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
