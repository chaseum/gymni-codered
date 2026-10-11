import SwiftUI
import GymAndAIKit

struct TodayWorkoutCard: View {
    let exercise: Exercise
    let mode: WorkoutMode
    let mascotState: MascotState
    let celebrate: () -> Void
    let openPlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GymTheme.Space.section) {
            TodayWorkoutHero(exercise: exercise, state: mascotState, celebrate: celebrate)
            TodayWorkoutDetails(exercise: exercise, mode: mode)
            Rectangle().fill(GymTheme.divider).frame(height: 1)
                .accessibilityHidden(true)

            Button(action: openPlan) {
                HStack {
                    Text("View plan")
                    Spacer()
                    Image(systemName: "arrow.right")
                        .foregroundStyle(GymTheme.accentText)
                        .accessibilityHidden(true)
                }
                .font(.headline)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(GymTheme.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GymSurface())
    }
}
