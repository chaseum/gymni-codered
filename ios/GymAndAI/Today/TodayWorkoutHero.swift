import SwiftUI
import GymAndAIKit

struct TodayWorkoutHero: View {
    let exercise: Exercise
    let state: MascotState
    let celebrate: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: GymTheme.Space.inset))
            : AnyLayout(HStackLayout(alignment: .center, spacing: GymTheme.Space.small))

        layout {
            VStack(alignment: .leading, spacing: GymTheme.Space.related) {
                Text(exercise.title)
                    .font(GymTheme.TypeStyle.title)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Your next set")
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TodayMascotButton(state: state, celebrate: celebrate)
        }
    }
}
