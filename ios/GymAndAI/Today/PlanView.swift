import SwiftUI
import GymAndAIKit

struct PlanView: View {
    @Bindable var session: WorkoutSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    WorkoutHeaderView(context: "One exercise · One set", title: session.exercise.title,
                                      detail: "Review your exercise and how this set will be followed.")
                        .padding(.vertical, GymTheme.Space.small)
                }
                .listRowBackground(Color.clear)
                Section("Exercise") {
                    Picker("Exercise", selection: $session.exercise) {
                        ForEach(Exercise.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    LabeledContent("Equipment", value: session.exercise.equipment)
                    LabeledContent("Target", value: target)
                    Text(targetDetail).foregroundStyle(GymTheme.muted)
                }
                .listRowBackground(GymTheme.surface)
                Section("Workout source") {
                    Picker("Mode", selection: $session.mode) {
                        ForEach(WorkoutMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    if session.mode == .backend {
                        Picker("Input", selection: $session.inputSource) {
                            Text("Live webcam").tag(InputSource.live)
                            Text("Recorded footage").tag(InputSource.recorded)
                        }
                    }
                    Text(sourceDetail).foregroundStyle(GymTheme.muted)
                }
                .listRowBackground(GymTheme.surface)
                Section("Positioning guide") {
                    Label(session.exercise.positioning, systemImage: "viewfinder")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(GymTheme.surface)
                Section {
                    Text("This build runs one selected set. Personalized plans are not connected yet.")
                        .foregroundStyle(GymTheme.muted)
                }
                .listRowBackground(Color.clear)
            }
            .modifier(GymFormStyle())
            .navigationTitle("Your plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done", action: dismiss.callAsFunction) }
        }
    }

    private var target: String {
        switch session.mode {
        case .phone: "Manual · Unmeasured"
        case .demo: "8 simulated reps"
        case .backend: "8 reps requested"
        case .hub: "8 reps"
        }
    }

    private var targetDetail: String {
        switch session.mode {
        case .phone: "Start and end the set yourself. This camera does not measure reps or form yet."
        case .demo: "The walkthrough simulates eight reps. No movement is measured."
        case .backend: "A new set requests eight reps. An existing session keeps the laptop’s current exercise and target."
        case .hub: "Each set targets eight reps. This iPhone counts them from the camera device’s movement data."
        }
    }

    private var sourceDetail: String {
        switch session.mode {
        case .phone: "Use your iPhone camera to see your position. Video stays on your phone."
        case .demo: "A simulated set lets you explore coaching, rest, and recap. No camera runs."
        case .backend: "The laptop owns tracking and rep counting. Configure its connection in Settings."
        case .hub: "The camera device tracks your movement; this iPhone counts reps and coaches. Start the camera with the address shown during the workout."
        }
    }
}
