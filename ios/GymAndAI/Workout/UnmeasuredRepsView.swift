import SwiftUI

struct UnmeasuredRepsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: GymTheme.Space.related) {
            Label("Reps not measured", systemImage: "viewfinder")
                .font(GymTheme.TypeStyle.heading)
            Text("This camera session doesn’t count reps or assess form yet.")
                .font(.body).foregroundStyle(GymTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, GymTheme.Space.section)
        .accessibilityElement(children: .combine)
    }
}
