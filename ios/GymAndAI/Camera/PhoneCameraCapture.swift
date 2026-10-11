@preconcurrency import AVFoundation
import Foundation

// All capture configuration and start/stop operations are confined to this serial queue.
// The preview layer receives the session only to render; it never configures capture.
final class PhoneCameraCapture: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.gymandai.camera")
    private var input: AVCaptureDeviceInput?
    private var wantsCapture = false
    private var observers: [NSObjectProtocol] = []
    private let report: @Sendable (PhoneCameraState) -> Void

    init(report: @escaping @Sendable (PhoneCameraState) -> Void) {
        self.report = report
        observe(.AVCaptureSessionWasInterrupted) { capture in
            capture.report(.interrupted("Camera interrupted. Return to the app and retry."))
        }
        observe(.AVCaptureSessionInterruptionEnded) { capture in
            if capture.wantsCapture { capture.startOnQueue() }
        }
        observe(.AVCaptureSessionRuntimeError) { capture in
            capture.report(.failed("Camera stopped unexpectedly. Retry the camera."))
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func start() {
        queue.async { [self] in
            wantsCapture = true
            startOnQueue()
        }
    }

    func stop() {
        queue.async { [self] in
            wantsCapture = false
            if session.isRunning { session.stopRunning() }
            report(.stopped)
        }
    }

    func flip() {
        queue.async { [self] in
            guard wantsCapture else { return }
            report(.starting)
            do {
                try configure(position: input?.device.position == .front ? .back : .front)
                report(session.isRunning ? .ready : .starting)
            } catch { report(.failed(error.localizedDescription)) }
        }
    }

    private func startOnQueue() {
        do {
            if input == nil { try configure(position: .front) }
            if !session.isRunning { session.startRunning() }
            report(session.isRunning ? .ready : .failed("Camera could not start. Retry."))
        } catch { report(.failed(error.localizedDescription)) }
    }

    private func configure(position: AVCaptureDevice.Position) throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw NSError(domain: "GymCamera", code: 1, userInfo: [NSLocalizedDescriptionKey: "No camera available on this device."])
        }
        let replacement = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720
        let previous = input
        if let previous { session.removeInput(previous) }
        guard session.canAddInput(replacement) else {
            if let previous, session.canAddInput(previous) { session.addInput(previous) }
            throw NSError(domain: "GymCamera", code: 2, userInfo: [NSLocalizedDescriptionKey: "This camera cannot be opened."])
        }
        session.addInput(replacement)
        input = replacement
    }

    private func observe(_ name: Notification.Name, action: @escaping @Sendable (PhoneCameraCapture) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.queue.async { action(self) }
        })
    }
}
