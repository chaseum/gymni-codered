import SwiftUI

struct TodayWelcomeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ready when you are.")
                .font(.title3.bold())
                .fontDesign(.rounded)
                .accessibilityAddTraits(.isHeader)
            Text("A little progress starts with showing up.")
                .font(.subheadline)
                .foregroundStyle(GymTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
