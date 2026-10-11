import SwiftUI
import GymAndAIKit

struct SessionStatusView: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sourceText)
                .font(.subheadline.bold()).foregroundStyle(GymTheme.cyan)
            Label(trackingText, systemImage: session.hasConnection && session.snapshot?.trackingStatus == .ready ? "checkmark.circle" : "viewfinder")
                .font(.subheadline).foregroundStyle(GymTheme.muted)
        }
    }

    private var sourceText: String {
        if session.isDemo { return "DEMO · SIMULATED DATA" }
        switch session.snapshot?.source {
        case .live: return "LIVE INPUT · LAPTOP"
        case .recorded: return "RECORDED INPUT"
        case nil: return "CAMERA SOURCE PENDING"
        }
    }

    private var trackingText: String {
        guard session.hasConnection else { return "Reconnecting to laptop…" }
        switch session.snapshot?.trackingStatus {
        case .ready: return "Tracking ready"
        case .lowVisibility: return "Tracking limited · Adjust your position"
        case .unassessable: return "This view cannot be assessed"
        default: return "Waiting for camera tracking"
        }
    }
}
