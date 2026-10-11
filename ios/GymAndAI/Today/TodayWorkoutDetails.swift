import SwiftUI
import GymAndAIKit

struct TodayWorkoutDetails: View {
    let exercise: Exercise
    let mode: WorkoutMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: GymTheme.Space.inset))
            : AnyLayout(HStackLayout(alignment: .top, spacing: GymTheme.Space.page))

        layout {
            TodayWorkoutDetail(label: "Equipment", value: exercise.equipment)
            TodayWorkoutDetail(label: "One set", value: target)
        }
    }

    private var target: String {
        switch mode {
        case .phone: "Manual set"
        case .demo: "8 demo reps"
        case .backend: "Laptop target"
        case .hub: "8 reps"
        }
    }
}
