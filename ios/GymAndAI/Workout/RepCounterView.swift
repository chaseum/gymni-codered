import SwiftUI

struct RepCounterView: View {
    let count: Int
    let target: Int?
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize = 110

    var body: some View {
        VStack(spacing: 6) {
            Text(count, format: .number)
                .font(.system(size: numberSize, weight: .bold, design: .rounded))
                .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                .accessibilityIdentifier("rep-count")
            Text(target.map { "of \($0) reps" } ?? "completed reps").font(.title3).foregroundStyle(GymTheme.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(target.map { "\(count) of \($0) completed reps" } ?? "\(count) completed reps")
    }
}
