import SwiftUI

struct PrimaryButtonStyle: PrimitiveButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26, *), !reduceTransparency {
            Button(role: configuration.role, action: configuration.trigger) {
                configuration.label.font(.headline).frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: 18))
            .controlSize(.large)
            .tint(GymTheme.accent)
            .foregroundStyle(GymTheme.charcoal)
        } else {
            Button(role: configuration.role, action: configuration.trigger) {
                configuration.label.font(.headline).frame(maxWidth: .infinity, minHeight: 36)
            }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .buttonBorderShape(.roundedRectangle(radius: 18))
                .tint(GymTheme.accent)
                .foregroundStyle(GymTheme.charcoal)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
    }
}
