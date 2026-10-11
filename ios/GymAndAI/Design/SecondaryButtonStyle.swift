import SwiftUI

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, GymTheme.Space.section)
            .padding(.vertical, GymTheme.Space.related)
            .frame(maxWidth: .infinity, minHeight: GymTheme.controlHeight)
            .foregroundStyle(GymTheme.text)
            .background(GymTheme.surface, in: .rect(cornerRadius: GymTheme.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: GymTheme.controlRadius)
                    .strokeBorder(GymTheme.divider, lineWidth: 1)
            }
            .opacity(isEnabled ? configuration.isPressed ? 0.7 : 1 : 0.45)
            .contentShape(.rect(cornerRadius: GymTheme.controlRadius))
    }
}
