import SwiftUI

struct RestCountdownView: View {
    let seconds: Int
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if seconds > 0 {
                Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                    .font(.system(size: timerSize, weight: .bold, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                Text("Rest remaining").foregroundStyle(GymTheme.muted)
            } else { Text("Continue when ready.").font(.title.bold()) }
        }
        .accessibilityElement(children: .combine)
    }
}
