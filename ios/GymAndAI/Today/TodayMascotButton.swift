import SwiftUI

struct TodayMascotButton: View {
    let state: MascotState
    let celebrate: () -> Void

    var body: some View {
        Button(action: celebrate) {
            PipView(state: state)
                .frame(width: 152, height: 160)
        }
        .buttonStyle(.plain)
        .disabled(state == .celebrate)
        .accessibilityLabel("Celebrate with Pip")
        .accessibilityHint("Plays a short celebration.")
        .accessibilityIdentifier("celebrate-pip")
    }
}
