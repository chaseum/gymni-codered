import SwiftUI

struct GymGlassContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 8) { content }
        } else {
            content
        }
    }
}
