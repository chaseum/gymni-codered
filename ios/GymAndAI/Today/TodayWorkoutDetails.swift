import SwiftUI
import GymAndAIKit

struct TodayWorkoutDetails: View {
    let exercise: Exercise
    let mode: WorkoutMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 24))

        layout {
            TodayWorkoutDetail(label: "Equipment", value: equipment)
            TodayWorkoutDetail(label: "One set", value: target)
        }
    }

    private var equipment: String {
        switch exercise {
        case .curl: "Dumbbell"
        case .squat: "Bodyweight"
        case .deadlift: "Barbell"
        }
    }

    private var target: String {
        switch mode {
        case .phone: "Manual set"
        case .demo: "8 demo reps"
        case .backend: "8 reps"
        }
    }
}
