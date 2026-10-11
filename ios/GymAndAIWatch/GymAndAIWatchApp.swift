import SwiftUI

@main
struct GymAndAIWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchApplicationDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup { WatchWorkoutView(manager: delegate.manager) }
    }
}
