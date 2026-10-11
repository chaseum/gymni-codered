import SwiftUI

struct PipView: View {
    var state = MascotState.idle
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    @State private var controller = PipSceneController()
    @State private var isVisible = false

    var body: some View {
        ZStack {
            Image("PipPreview")
                .resizable().scaledToFit()
                .opacity(controller.loadState == .ready && rendersScene ? 0 : 1)
            if rendersScene {
                PipRealityView(controller: controller, state: state, reducesMotion: effectiveReducedMotion)
                    .opacity(controller.loadState == .ready ? 1 : 0)
                    .task { await controller.load() }
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pip, your workout companion")
        .accessibilityValue("\(state.rawValue), \(controller.loadState.description)\(effectiveReducedMotion ? ", motion reduced" : "")")
        .accessibilityIdentifier("pip-mascot")
    }

    private var rendersScene: Bool {
        isVisible && scenePhase == .active && controller.loadState != .failed
    }

    private var effectiveReducedMotion: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PipReduceMotion") { return true }
        #endif
        return reducesMotion
    }
}
