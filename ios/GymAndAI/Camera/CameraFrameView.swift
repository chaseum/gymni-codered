import SwiftUI

struct CameraFrameView: View {
    let stream: CameraPreviewStream
    let date: Date
    let hasURL: Bool
    var isRecorded = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if let image = stream.image, let frameDate = stream.frameDate, date.timeIntervalSince(frameDate) < 3 {
                GeometryReader { geometry in
                    Image(decorative: image, scale: 1)
                        .resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .accessibilityLabel(isRecorded ? "Recorded camera preview" : "Pi or laptop camera preview")
                        .accessibilityHidden(false)
                }
            } else {
                ContentUnavailableView(
                    "Camera preview unavailable", systemImage: "video.slash",
                    description: Text(hasURL ? stream.image != nil ? "The feed is stale. Waiting for a new frame." : stream.status : "Add the Pi or laptop camera preview address in Settings.")
                )
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
