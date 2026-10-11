import SwiftUI
import GymAndAIKit

struct RecapView: View {
    let session: WorkoutSession
    var mascotState = MascotState.celebrate

    var body: some View {
        VStack(spacing: GymTheme.Space.section) {
            CompanionStage(state: mascotState)
                .frame(maxWidth: 260)
            VStack(spacing: GymTheme.Space.tight) {
                Text("Workout Complete").font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(session.plan.title).foregroundStyle(GymTheme.muted)
            }
            Grid(horizontalSpacing: GymTheme.Space.related) {
                GridRow {
                    stat("Time", session.elapsed(at: completedAt))
                    stat("Sets", "\(session.setsDone)")
                    stat("Reps", "\(session.totalReps)")
                }
            }
            Spacer(minLength: 0)
            Button("Done", action: session.returnToday)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, GymTheme.Space.page)
        .padding(.bottom, GymTheme.Space.small)
        .gymPage()
    }

    @State private var completedAt = Date.now

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.title, design: .rounded).bold()).monospacedDigit()
            Text(label).font(.subheadline).foregroundStyle(GymTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, GymTheme.Space.inset)
        .background(GymTheme.surface, in: .rect(cornerRadius: GymTheme.radius))
        .accessibilityElement(children: .combine)
    }
}
