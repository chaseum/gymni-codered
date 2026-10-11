import SwiftUI

struct PipView: View {
    var state = MascotState.idle
    @AppStorage("companion") private var companion = CompanionKind.pip

    var body: some View {
        CompanionSceneView(state: state, companion: companion)
            .id(companion)
    }
}

struct CompanionSceneView: View {
    let state: MascotState
    let companion: CompanionKind
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    @State private var controller = PipSceneController()
    @State private var isVisible = false

    var body: some View {
        ZStack {
            Image(companion.preview)
                .resizable().scaledToFit()
                .opacity(controller.loadState == .ready && rendersScene ? 0 : 1)
            if rendersScene {
                PipRealityView(controller: controller, companion: companion, state: state,
                               reducesMotion: effectiveReducedMotion)
                    .opacity(controller.loadState == .ready ? 1 : 0)
            }
            if isVisible && scenePhase == .active && !effectiveReducedMotion
                && (state == .celebrate || state == .rest) {
                CompanionEffectsView(state: state)
                    .id(state)
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(companion.name), your workout companion")
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
