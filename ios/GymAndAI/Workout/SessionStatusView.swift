import SwiftUI
import GymAndAIKit

struct SessionStatusView: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: GymTheme.Space.small) {
            Text(sourceText)
                .font(GymTheme.TypeStyle.label).foregroundStyle(GymTheme.accentText)
            Label(session.trackingMessage, systemImage: session.hasConnection && session.snapshot?.trackingStatus == .ready ? "checkmark.circle" : "viewfinder")
                .font(GymTheme.TypeStyle.detail).foregroundStyle(GymTheme.muted)
        }
    }

    private var sourceText: String {
        if session.isDemo { return "Demo · Simulated data" }
        if session.isPhone { return "iPhone camera · Unmeasured" }
        switch session.snapshot?.source {
        case .live: return "Laptop · Live input"
        case .recorded: return "Laptop · Recorded input"
        case nil: return "Camera source pending"
        }
    }
}
