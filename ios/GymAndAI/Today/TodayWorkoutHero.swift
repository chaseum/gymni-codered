import SwiftUI
import GymAndAIKit

struct TodayWorkoutHero: View {
    let exercise: Exercise
    let state: MascotState
    let celebrate: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))

        layout {
            VStack(alignment: .leading, spacing: 12) {
                Text(exercise.title)
                    .font(.largeTitle.bold())
                    .fontDesign(.rounded)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Strength foundations")
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TodayMascotButton(state: state, celebrate: celebrate)
        }
    }
}
