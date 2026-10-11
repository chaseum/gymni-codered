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
                Section("Laptop connection") {
                    TextField("Backend URL", text: $session.backendAddress)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Existing session ID", text: $session.backendSessionId)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Access token (optional)", text: $session.token)
                    Text("Use localhost in Simulator. On an iPhone, enter the laptop’s LAN address. Start the backend and create the session first.")
                        .foregroundStyle(GymTheme.muted)
                }
                .listRowBackground(GymTheme.surface)
                Section("Laptop camera preview") {
                    TextField("MJPEG preview URL (optional)", text: $session.previewAddress)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Requires a separate MJPEG feed from the same webcam and session. The current backend does not publish video yet. A missing feed never replaces real video with a simulated image. Workout events can continue without a preview.")
                        .foregroundStyle(GymTheme.muted)
                }
                .listRowBackground(GymTheme.surface)
                Section("Spoken coaching") {
                    Toggle("Spoken coaching", isOn: $session.audioEnabled)
                        .tint(GymTheme.accent)
                    Text("Laptop corrections use ElevenLabs audio when cue files are available; otherwise the iPhone voice is used. Captions remain visible when muted.")
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
        case .demo: "Demo simulates reps and coaching. No camera, movement, or heart rate is measured."
        case .backend: "Laptop receives backend events. The laptop owns workout state and rep counting."
        }
    }
}
