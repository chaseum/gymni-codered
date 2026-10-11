import SwiftUI
import GymAndAIKit

struct SessionStatusView: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: GymTheme.Space.small) {
            Text(sourceText)
                .font(GymTheme.TypeStyle.label).foregroundStyle(GymTheme.accentText)
            Label(session.trackingMessage, systemImage: session.snapshot?.trackingStatus == .ready ? "checkmark.circle" : "viewfinder")
                .font(GymTheme.TypeStyle.detail).foregroundStyle(GymTheme.muted)
        }
    }

    private var sourceText: String {
        if session.isPhone { return "iPhone camera · Unmeasured" }
        return "Pi or laptop camera · Counted on this iPhone"
    }
}
