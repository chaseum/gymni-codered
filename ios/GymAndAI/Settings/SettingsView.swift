import SwiftUI
import GymAndAIKit

struct SettingsView: View {
    @Bindable var session: WorkoutSession
    let healthAccess: HealthAccessController
    let watch: WatchConnectionController
    @Environment(\.dismiss) private var dismiss
    @AppStorage("companion") private var companion = CompanionKind.pip

    var body: some View {
        NavigationStack {
            Form {
                Section("Companion") {
                    Picker("Companion", selection: $companion) {
                        ForEach(CompanionKind.allCases) { choice in
                            Text("\(choice.name) · \(choice.focus)").tag(choice)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityIdentifier("companion-choice")
                }
                .listRowBackground(GymTheme.surface)
                Section("Workout mode") {
                    Picker("Mode", selection: $session.mode) {
                        ForEach(WorkoutMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(modeDetail).foregroundStyle(GymTheme.muted)
                }
                .listRowBackground(GymTheme.surface)
                HealthAccessSection(healthAccess: healthAccess)
                    .listRowBackground(GymTheme.surface)
                Section("Apple Watch") {
                    Toggle("Use Watch heart rate", isOn: $session.usesAppleWatch)
                        .tint(GymTheme.accent)
                    Text(watch.status).foregroundStyle(GymTheme.muted)
                    Button("Refresh Watch connection", action: watch.refresh).frame(minHeight: 44)
                    Text("Install Gym&I on the paired Watch and allow Health access there. Starting a workout on iPhone launches the Watch companion. Missing or stale readings show unavailable.")
                        .foregroundStyle(GymTheme.muted)
                }
                .listRowBackground(GymTheme.surface)
                Section("Pi or laptop camera preview") {
                    TextField("Camera preview address, like 192.168.1.30:8081", text: $session.previewAddress)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Run the camera with --preview-port 8081 and enter its address. Reps still count without a preview.")
                        .foregroundStyle(GymTheme.muted)
                }
                .listRowBackground(GymTheme.surface)
                Section("Spoken coaching") {
                    Toggle("Spoken coaching", isOn: $session.audioEnabled)
                        .tint(GymTheme.accent)
                    Text("Form corrections are spoken with the iPhone voice. Captions remain visible when muted.")
                        .foregroundStyle(GymTheme.muted)
                }
                .listRowBackground(GymTheme.surface)
            }
            .modifier(GymFormStyle())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done", action: dismiss.callAsFunction) }
        }
    }

    private var modeDetail: String {
        switch session.mode {
        case .phone: "iPhone uses this phone’s camera. Rep and form analysis awaits the trained model."
        case .hub: "A Pi or laptop runs only the camera and model and sends what it sees to this iPhone, which counts reps and coaches."
        }
    }
}
