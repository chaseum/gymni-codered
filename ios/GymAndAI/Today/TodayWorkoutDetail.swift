import SwiftUI

struct TodayWorkoutDetail: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: GymTheme.Space.small) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(GymTheme.muted)
            Text(value)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
