import SwiftUI

struct WatchWorkoutView: View {
    let manager: WatchWorkoutManager

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Gym&AI").font(.headline).foregroundStyle(Color(red: 0, green: 0.59, blue: 0.70))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(manager.heartRateText(at: context.date))
                        .font(.system(.largeTitle, design: .rounded).bold()).monospacedDigit()
                        .accessibilityLabel("Heart rate: \(manager.heartRateText(at: context.date))")
                }
                Text(manager.status).font(.footnote).multilineTextAlignment(.center)
                if manager.canRetry {
                    Button("Retry tracking") { manager.retry() }
                }
                if manager.hasWorkout {
                    Button("End Watch tracking", role: .destructive) { manager.stopFromWatch() }
                }
            }
            .padding(8)
        }
    }
}
