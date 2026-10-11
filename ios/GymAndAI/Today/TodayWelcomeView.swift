import SwiftUI
import GymAndAIKit

struct TodayWelcomeView: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: GymTheme.Space.small) {
            Label("Before you start", systemImage: "viewfinder")
                .font(GymTheme.TypeStyle.label).accessibilityAddTraits(.isHeader)
            Text(exercise.positioning)
                .font(GymTheme.TypeStyle.detail).foregroundStyle(GymTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
