import Combine
import Observation
import RealityKit
import UIKit

@MainActor
@Observable
final class PipSceneController {
    private(set) var loadState = PipLoadState.loading

    @ObservationIgnored private weak var view: ARView?
    @ObservationIgnored private var motion: PipMotion?
    @ObservationIgnored private var updates: AnyCancellable?
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

    func load() async {
        let attachment = attachmentID
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-PipForceFallback") {
                throw CocoaError(.fileNoSuchFile)
            }
            #endif
            let character = try await PipAssetLibrary.shared.character()
            guard attachment == attachmentID else { return }
            try Task.checkCancellation()
            guard let view else { return }
            let anchor = AnchorEntity(world: .zero)
            let root = Entity()
            root.name = "PipMotionRoot"
            root.addChild(character)
            anchor.addChild(root)
            view.scene.addAnchor(anchor)
            motion = try PipMotion(root: root, character: character)
            motion?.setState(state)
            motion?.setReducedMotion(reducesMotion)
            if let lighting = try? await PipAssetLibrary.shared.lighting() {
                guard attachment == attachmentID else { return }
                try Task.checkCancellation()
                view.environment.lighting.resource = lighting
                view.environment.lighting.intensityExponent = 0.65
            }
            try Task.checkCancellation()
            loadState = .ready
            subscribeToMotion()
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
        motion?.setState(state)
        motion?.setReducedMotion(reducesMotion)
        subscribeToMotion()
    }

    func detach() {
        attachmentID += 1
        updates?.cancel()
        updates = nil
        motion = nil
        view?.scene.anchors.removeAll()
        view = nil
    }

    private func subscribeToMotion() {
        guard !reducesMotion, motion != nil, let view else {
            updates?.cancel()
            updates = nil
            return
        }
        guard updates == nil else { return }
        if #available(iOS 18, *) {
            let subscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                self?.motion?.advance(by: min(event.deltaTime, 0.1))
            }
            updates = AnyCancellable { subscription.cancel() }
        } else {
            updates = view.scene.publisher(for: SceneEvents.Update.self).sink { [weak self] event in
                self?.motion?.advance(by: min(event.deltaTime, 0.1))
            }
        }
    }
}
