import SwiftUI

struct CameraAudioButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(minWidth: GymTheme.controlHeight, minHeight: GymTheme.controlHeight)
            .foregroundStyle(GymTheme.text)
            .background(GymTheme.surface, in: .circle)
            .overlay { Circle().strokeBorder(GymTheme.divider, lineWidth: 1) }
            .opacity(isEnabled ? configuration.isPressed ? 0.7 : 1 : 0.45)
            .contentShape(.circle)
    }
}
