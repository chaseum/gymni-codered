import SwiftUI

struct CameraGlassPanel: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.background(GymTheme.surface, in: .rect(cornerRadius: 20))
        } else if #available(iOS 26, *) {
            content.glassEffect(.regular.tint(GymTheme.charcoal.opacity(0.35)), in: .rect(cornerRadius: 20))
        } else {
            content.background(.regularMaterial, in: .rect(cornerRadius: 20))
        }
    }
}
