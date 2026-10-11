import SwiftUI

struct RestCountdownView: View {
    let seconds: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize = 64

    var body: some View {
        VStack(alignment: .leading, spacing: GymTheme.Space.related) {
            Text("Rest remaining").font(GymTheme.TypeStyle.label).foregroundStyle(GymTheme.muted)
            if seconds > 0 {
                Text(dynamicTypeSize.isAccessibilitySize ? seconds.formatted(.number) : clockText)
                    .font(.system(size: timerSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                if dynamicTypeSize.isAccessibilitySize {
                    Text("seconds").font(.title3).foregroundStyle(GymTheme.muted)
                }
            } else {
                Text("Continue when ready.").font(GymTheme.TypeStyle.heading)
            }
            Text("Your workout stays paused until you resume.")
                .font(GymTheme.TypeStyle.detail).foregroundStyle(GymTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("rest-countdown")
    }

    private var clockText: String {
        let twoDigits = IntegerFormatStyle<Int>.number.grouping(.never).precision(.integerLength(2...))
        return "\((seconds / 60).formatted(twoDigits)):\((seconds % 60).formatted(twoDigits))"
    }
}
