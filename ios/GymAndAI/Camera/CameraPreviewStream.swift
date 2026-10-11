import Foundation
import Observation
import ImageIO
import OSLog
import GymAndAIKit

@MainActor @Observable
final class CameraPreviewStream {
    private(set) var image: CGImage?
    private(set) var frameDate: Date?
    private(set) var status = "Connecting to camera…"
    private let logger = Logger(subsystem: "com.chasebeeler.gymandai", category: "PiCamera")

    func load(_ url: URL) async {
        image = nil
        frameDate = nil
        status = "Connecting to camera…"
        #if DEBUG
        UserDefaults.standard.set("Connecting to \(url.host ?? "unknown")", forKey: "gymni.previewDiagnostic")
        #endif
        while !Task.isCancelled {
            var failed = false
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
            } catch {
                if Task.isCancelled { return }
                failed = true
                status = "Couldn’t reach the Pi camera"
                logger.error("Preview connection to \(url.absoluteString, privacy: .private) failed: \(error.localizedDescription, privacy: .public)")
                #if DEBUG
                print("Pi camera connection failed for \(url.host ?? "unknown"): \(error)")
                UserDefaults.standard.set("\(url.host ?? "unknown"): \((error as NSError).code) \(error.localizedDescription)", forKey: "gymni.previewDiagnostic")
                #endif
            }
            guard !Task.isCancelled else { return }
            if !failed { status = "Reconnecting to Pi camera…" }
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
        }
    }
}
