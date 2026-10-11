import SwiftUI

struct TodayStartButton: View {
    let isStarting: Bool
    let startWorkout: () -> Void

    var body: some View {
        Button(action: startWorkout) {
            HStack(spacing: 10) {
                if isStarting {
                    ProgressView().tint(GymTheme.charcoal)
                    Text("Starting…")
                } else {
                    Image(systemName: "play.fill").accessibilityHidden(true)
                    Text("Start workout")
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isStarting)
        .accessibilityLabel(isStarting ? "Starting workout" : "Start workout")
    }
}
