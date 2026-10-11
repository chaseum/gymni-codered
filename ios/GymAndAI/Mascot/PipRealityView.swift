import RealityKit
import SwiftUI

struct PipRealityView: UIViewRepresentable {
    let controller: PipSceneController
    let state: MascotState
    let reducesMotion: Bool

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        controller.attach(to: view)
        controller.configure(state: state, reducesMotion: reducesMotion)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        controller.configure(state: state, reducesMotion: reducesMotion)
    }

    func makeCoordinator() -> PipSceneController { controller }

    static func dismantleUIView(_ view: ARView, coordinator: PipSceneController) {
        coordinator.detach()
    }
}
