import SwiftUI

struct RepCounterView: View {
    let count: Int
    let target: Int?
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize = 88

    var body: some View {
        VStack(spacing: GymTheme.Space.tight) {
            Text(count, format: .number)
                .font(.system(size: numberSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("rep-count")
            Text(target.map { "of \($0) reps" } ?? "completed reps")
                .font(.title3).foregroundStyle(GymTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, GymTheme.Space.section)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(target.map { "\(count) of \($0) completed reps" } ?? "\(count) completed reps")
    }
}
