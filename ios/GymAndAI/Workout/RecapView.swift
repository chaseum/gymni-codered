import SwiftUI
import GymAndAIKit

struct RecapView: View {
    let session: WorkoutSession
    var mascotState = MascotState.celebrate

    var body: some View {
        GymPage {
            WorkoutHeaderView(context: session.isDemo ? "Demo recap · Simulated data" : "Session recap",
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
            Text(session.isDemo ? "This walkthrough simulated your reps and coaching. No movement or heart rate was measured." : session.isPhone ? "Your camera session ended. Reps and form were not measured." : "These completed reps came from your laptop session.")
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
        if session.isDemo { return "Simulated Demo set" }
        if session.isPhone { return "iPhone camera · Unmeasured" }
        if session.isHub { return "Camera device · Counted on this iPhone" }
        return session.snapshot?.source == .recorded ? "Laptop · Recorded footage" : "Laptop · Backend events"
    }
}
