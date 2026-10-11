import SwiftUI

struct CameraGlassPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(GymTheme.surface, in: .rect(cornerRadius: GymTheme.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: GymTheme.controlRadius)
                    .strokeBorder(GymTheme.divider, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}
