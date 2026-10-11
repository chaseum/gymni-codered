import AVFoundation
import Observation

@MainActor @Observable
final class PhoneCameraController {
    private(set) var state: PhoneCameraState = .stopped
    @ObservationIgnored private var wantsCapture = false
    @ObservationIgnored private lazy var capture = PhoneCameraCapture { [weak self] state in
        Task { @MainActor [weak self] in
            guard let self, self.wantsCapture, self.state != .unavailable, self.state != .denied, state != .stopped else { return }
            self.state = state
        }
    }

    var captureSession: AVCaptureSession { capture.session }

    func start() async {
        wantsCapture = true
        #if targetEnvironment(simulator)
        state = .unavailable
        return
        #else
        state = .requesting
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: authorized = true
        case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
        default: authorized = false
        }
        guard wantsCapture, !Task.isCancelled else { return }
        guard authorized else { state = .denied; return }
        state = .starting
        capture.start()
        #endif
    }

    func stop() {
        wantsCapture = false
        capture.stop()
        state = .stopped
    }

    func flip() { capture.flip() }
}
