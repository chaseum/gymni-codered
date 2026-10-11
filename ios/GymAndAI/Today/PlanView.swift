import SwiftUI
import GymAndAIKit

struct PlanView: View {
    @Bindable var session: WorkoutSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Your first session") {
                    Picker("Exercise", selection: $session.exercise) {
                        ForEach(Exercise.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    LabeledContent("Target", value: "8 reps")
                    Text("This first build runs one set. Personalized plans will connect to the planner in a later update.")
                        .foregroundStyle(.secondary)
                }
                if session.mode == .backend {
                    Section("Camera source") {
                        Picker("Input", selection: $session.inputSource) {
                            Text("Live webcam").tag(InputSource.live)
                            Text("Recorded footage").tag(InputSource.recorded)
                        }
                    }
                }
                Section {
                    Text(session.exercise.positioning)
                }
            }
            .navigationTitle("Your plan")
            .toolbar { Button("Done", action: dismiss.callAsFunction) }
            .tint(GymTheme.lime)
        }
    }
}
