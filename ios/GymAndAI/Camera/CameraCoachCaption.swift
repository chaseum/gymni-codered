import SwiftUI

struct CameraCoachCaption: View {
    let message: String
    var status: String? = nil

    var body: some View {
        VStack(spacing: GymTheme.Space.small) {
            if let status {
                Text(status).font(GymTheme.TypeStyle.detail).foregroundStyle(GymTheme.accentText)
            }
            Text(message)
                .accessibilityIdentifier("coach-message")
        }
        .font(.body.bold())
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, GymTheme.Space.section)
        .padding(.vertical, GymTheme.Space.related)
        .modifier(CameraGlassPanel())
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }
}
