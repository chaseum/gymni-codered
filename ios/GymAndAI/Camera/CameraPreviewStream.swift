import Foundation
import Observation
import ImageIO
import GymAndAIKit

@MainActor @Observable
final class CameraPreviewStream {
    private(set) var image: CGImage?
    private(set) var frameDate: Date?
    private(set) var status = "Connecting to camera…"

    func load(_ url: URL) async {
        image = nil
        frameDate = nil
        status = "Connecting to camera…"
        do {
            for try await frame in MJPEGStream.frames(from: url) {
                try Task.checkCancellation()
                let now = Date()
                // Preview rendering is independent of the analyzer's frame rate.
                if let frameDate, now.timeIntervalSince(frameDate) < 0.1 { continue }
                guard let source = CGImageSourceCreateWithData(frame as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
                self.image = image
                frameDate = now
                status = "Camera preview connected"
            }
            if !Task.isCancelled { status = "Camera feed disconnected"; image = nil }
        } catch {
            if !Task.isCancelled { status = "Camera feed unavailable"; image = nil }
        }
    }
}
