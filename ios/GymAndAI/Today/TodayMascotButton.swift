import SwiftUI

struct TodayMascotButton: View {
    let state: MascotState
    let celebrate: () -> Void
    @AppStorage("companion") private var companion = CompanionKind.pip

    var body: some View {
        Button(action: celebrate) {
            PipView(state: state)
                .frame(width: 120, height: 132)
        }
        .buttonStyle(.plain)
        .disabled(state == .celebrate)
        .accessibilityLabel("Celebrate with \(companion.name)")
        .accessibilityHint("Plays a short celebration.")
        .accessibilityIdentifier("celebrate-pip")
    }
}
