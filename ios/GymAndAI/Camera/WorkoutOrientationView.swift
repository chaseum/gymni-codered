import SwiftUI
import UIKit

struct WorkoutOrientationView: UIViewControllerRepresentable {
    let landscape: Bool

    func makeUIViewController(context: Context) -> WorkoutOrientationController {
        WorkoutOrientationController()
    }

    func updateUIViewController(_ controller: WorkoutOrientationController, context: Context) {
        controller.setOrientation(landscape ? .landscape : .portrait)
    }

    static func dismantleUIViewController(_ controller: WorkoutOrientationController, coordinator: ()) {
        controller.setOrientation(.portrait)
    }
}
