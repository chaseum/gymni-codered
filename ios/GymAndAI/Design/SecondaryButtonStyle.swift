import SwiftUI

struct SecondaryButtonStyle: PrimitiveButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26, *), !reduceTransparency {
            Button(role: configuration.role, action: configuration.trigger) {
                configuration.label.font(.headline).frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.roundedRectangle(radius: 18))
            .controlSize(.large)
            .foregroundStyle(GymTheme.text)
        } else {
            Button(role: configuration.role, action: configuration.trigger) {
                configuration.label.font(.headline).frame(maxWidth: .infinity, minHeight: 36)
            }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .buttonBorderShape(.roundedRectangle(radius: 18))
                .tint(GymTheme.text)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
    }
}
