import SwiftUI

@main
struct GymAndAIApp: App {
    @UIApplicationDelegateAdaptor(WorkoutOrientationDelegate.self) private var orientationDelegate

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .preferredColorScheme(.dark)
        }
    }
}
