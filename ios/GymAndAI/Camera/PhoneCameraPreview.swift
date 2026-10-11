import AVFoundation
import SwiftUI

struct PhoneCameraPreview: UIViewRepresentable {
    let camera: PhoneCameraController

    func makeUIView(context: Context) -> PhoneCameraPreviewSurface {
        let view = PhoneCameraPreviewSurface()
        view.preview.session = camera.captureSession
        view.preview.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PhoneCameraPreviewSurface, context: Context) { view.setNeedsLayout() }

    static func dismantleUIView(_ view: PhoneCameraPreviewSurface, coordinator: ()) {
        view.preview.session = nil
    }
}
