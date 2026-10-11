import UIKit

@MainActor
final class WorkoutOrientationController: UIViewController {
    private var orientations: UIInterfaceOrientationMask = .portrait

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestOrientation()
    }

    func setOrientation(_ orientations: UIInterfaceOrientationMask) {
        guard self.orientations != orientations else { return }
        self.orientations = orientations
        requestOrientation()
    }

    private func requestOrientation() {
        WorkoutOrientationDelegate.orientations = orientations
        guard let window = view.window, let scene = window.windowScene else { return }
        var presented = window.rootViewController
        while let next = presented?.presentedViewController { presented = next }
        presented?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
    }
}
