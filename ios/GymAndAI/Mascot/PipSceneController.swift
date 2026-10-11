import Observation
import RealityKit
import UIKit

@MainActor
@Observable
final class PipSceneController {
    private(set) var loadState = PipLoadState.loading

    @ObservationIgnored private weak var view: ARView?
    @ObservationIgnored private var motion: PipMotion?
    @ObservationIgnored private var state = MascotState.idle
    @ObservationIgnored private var reducesMotion = false
    @ObservationIgnored private var attachmentID = 0

    func attach(to view: ARView) {
        attachmentID += 1
        self.view = view
        loadState = .loading
        view.isUserInteractionEnabled = false
        view.isOpaque = false
        view.backgroundColor = .clear
        view.environment.background = .color(.clear)
        view.renderOptions = [.disableMotionBlur, .disableDepthOfField]

        let studio = AnchorEntity(world: .zero)
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 36
        camera.look(at: [0, 0.87, 0], from: [0.95, 1.95, 3.0], relativeTo: nil)
        studio.addChild(camera)
        let light = DirectionalLight()
        light.light.intensity = 1_200
        light.look(at: [0, 0.8, 0], from: [-3, 4, 4], relativeTo: nil)
        studio.addChild(light)
        let fill = DirectionalLight()
        fill.light.intensity = 650
        fill.light.color = UIColor(red: 0.78, green: 0.91, blue: 1, alpha: 1)
        fill.look(at: [0, 0.8, 0], from: [3, 2, 4], relativeTo: nil)
        studio.addChild(fill)
        view.scene.addAnchor(studio)
    }

    func load(companion: CompanionKind) async {
        let attachment = attachmentID
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-PipForceFallback") {
                throw CocoaError(.fileNoSuchFile)
            }
            #endif
            let character = try await PipAssetLibrary.shared.character(companion)
            guard attachment == attachmentID else { return }
            try Task.checkCancellation()
            guard let view else { return }
            let anchor = AnchorEntity(world: .zero)
            let root = Entity()
            root.name = "PipMotionRoot"
            root.addChild(character)
            let bounds = character.visualBounds(relativeTo: root)
            guard bounds.extents.y.isFinite, bounds.extents.y > 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            character.position -= bounds.center - SIMD3<Float>(0, bounds.extents.y / 2, 0)
            root.scale = SIMD3<Float>(repeating: 1.6 / bounds.extents.y)
            anchor.addChild(root)
            view.scene.addAnchor(anchor)
            motion = try PipMotion(character: character, companion: companion)
            motion?.configure(state: state, reducesMotion: reducesMotion)
            if let lighting = try? await PipAssetLibrary.shared.lighting() {
                guard attachment == attachmentID else { return }
                try Task.checkCancellation()
                view.environment.lighting.resource = lighting
                view.environment.lighting.intensityExponent = 0.65
            }
            try Task.checkCancellation()
            loadState = .ready
        } catch is CancellationError {
            if attachment == attachmentID { detach() }
        } catch {
            guard attachment == attachmentID else { return }
            detach()
            loadState = .failed
        }
    }

    func configure(state: MascotState, reducesMotion: Bool) {
        self.state = state
        self.reducesMotion = reducesMotion
        motion?.configure(state: state, reducesMotion: reducesMotion)
    }

    func detach() {
        attachmentID += 1
        motion?.stop()
        motion = nil
        view?.scene.anchors.removeAll()
        view = nil
    }

}
