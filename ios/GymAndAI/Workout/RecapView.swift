import SwiftUI
import GymAndAIKit

struct RecapView: View {
    let session: WorkoutSession
    var mascotState = MascotState.celebrate

    var body: some View {
        GymPage {
            WorkoutHeaderView(context: "Session recap",
                              title: "You showed up.")
            PipView(state: mascotState).frame(width: 120, height: 110)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: GymTheme.Space.related) {
                Text((session.snapshot?.exercise ?? session.exercise).title)
                    .font(GymTheme.TypeStyle.heading).accessibilityAddTraits(.isHeader)
                if session.isPhone { UnmeasuredRepsView() }
                else { RepCounterView(count: session.repCount, target: session.targetReps) }
                Text(sourceDescription).font(GymTheme.TypeStyle.label).foregroundStyle(GymTheme.accentText)
            }
            .padding(GymTheme.Space.page)
            .modifier(GymSurface())
            Text(session.isPhone ? "Your camera session ended. Reps and form were not measured." : "These reps were counted on this iPhone from your camera’s movement data.")
                .font(.body).foregroundStyle(GymTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GymActionDock {
                Button("Back to Today", action: session.returnToday).buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private var sourceDescription: String {
        if session.isPhone { return "iPhone camera · Unmeasured" }
        return "Pi or laptop camera · Counted on this iPhone"
    }
}
