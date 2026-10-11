import SwiftUI

struct PendingWorkoutActionView: View {
    var body: some View {
        ProgressView("Confirming action…")
            .font(GymTheme.TypeStyle.detail)
            .tint(GymTheme.accentText)
            .accessibilityIdentifier("workout-action-pending")
    }
}
