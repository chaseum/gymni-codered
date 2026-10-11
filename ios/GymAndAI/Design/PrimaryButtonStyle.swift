import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, GymTheme.Space.section)
            .padding(.vertical, GymTheme.Space.related)
            .frame(maxWidth: .infinity, minHeight: GymTheme.controlHeight)
            .foregroundStyle(GymTheme.charcoal)
            .background(GymTheme.accent, in: .rect(cornerRadius: GymTheme.controlRadius))
            .opacity(isEnabled ? configuration.isPressed ? 0.8 : 1 : 0.45)
            .contentShape(.rect(cornerRadius: GymTheme.controlRadius))
    }
}
