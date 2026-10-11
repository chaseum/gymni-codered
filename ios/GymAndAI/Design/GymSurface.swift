import SwiftUI

struct GymSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(GymTheme.surface, in: .rect(cornerRadius: GymTheme.radius))
            .overlay {
                RoundedRectangle(cornerRadius: GymTheme.radius)
                    .strokeBorder(GymTheme.divider, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}
