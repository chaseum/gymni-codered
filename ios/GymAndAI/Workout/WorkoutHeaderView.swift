import SwiftUI

struct WorkoutHeaderView: View {
    let context: String
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: GymTheme.Space.small) {
            Text(context).font(GymTheme.TypeStyle.label).foregroundStyle(GymTheme.accentText)
            Text(title).font(GymTheme.TypeStyle.title)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail).font(.body).foregroundStyle(GymTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
