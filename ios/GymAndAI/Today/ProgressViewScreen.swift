import SwiftUI
import GymAndAIKit

struct ProgressViewScreen: View {
    let session: WorkoutSession

    var body: some View {
        GymPage {
            if session.completedReps != nil || session.completedUnmeasuredSession {
                WorkoutHeaderView(context: "Last session", title: session.completedExercise?.title ?? "Your last session",
                                  detail: "Retained during this app session.")
                VStack(alignment: .leading, spacing: GymTheme.Space.related) {
                    Label(sourceTitle, systemImage: session.completedUnmeasuredSession ? "camera" : "checkmark.circle")
                        .font(GymTheme.TypeStyle.label).foregroundStyle(GymTheme.accentText)
                    if let reps = session.completedReps {
                        RepCounterView(count: reps, target: nil)
                    } else {
                        Text("You completed a camera session").font(GymTheme.TypeStyle.heading)
                        UnmeasuredRepsView()
                    }
                }
                .padding(GymTheme.Space.page)
                .modifier(GymSurface())
                Text(sourceDetail).foregroundStyle(GymTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A new workout replaces this recap. Workout history isn’t saved yet.")
                    .font(GymTheme.TypeStyle.detail).foregroundStyle(GymTheme.muted)
            } else {
                WorkoutHeaderView(context: "Session recaps", title: "Your progress starts here")
                PipView().frame(width: 104, height: 100)
                ContentUnavailableView("One set is a start", systemImage: "figure.strengthtraining.traditional",
                                       description: Text("Complete a workout, then return to Today to see your last session here."))
                Text("Sets counted from your Pi or laptop camera and unmeasured iPhone sessions are labeled by source.")
                    .font(GymTheme.TypeStyle.detail).foregroundStyle(GymTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sourceTitle: String {
        if session.completedUnmeasuredSession { return "iPhone camera · Unmeasured" }
        return "Pi or laptop camera · Counted on this iPhone"
    }

    private var sourceDetail: String {
        if session.completedUnmeasuredSession { return "Reps and form were not measured during this camera session." }
        return "These reps were counted on this iPhone from your Pi or laptop camera."
    }
}
