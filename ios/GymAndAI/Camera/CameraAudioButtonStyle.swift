import SwiftUI

struct CameraAudioButtonStyle: PrimitiveButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26, *), !reduceTransparency {
            Button(role: configuration.role, action: configuration.trigger) {
                configuration.label.frame(minWidth: 28, minHeight: 36)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
        } else {
            Button(role: configuration.role, action: configuration.trigger) {
                configuration.label.frame(minWidth: 28, minHeight: 36)
            }
                .buttonStyle(.bordered)
                .controlSize(.large).buttonBorderShape(.circle)
                .frame(minWidth: 44, minHeight: 52)
        }
    }
}
