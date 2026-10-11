import SwiftUI

struct CameraCoachCaption: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.body.bold())
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .modifier(CameraGlassPanel())
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("coach-message")
    }
}
