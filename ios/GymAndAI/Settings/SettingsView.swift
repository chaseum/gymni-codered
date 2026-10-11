import SwiftUI
import GymAndAIKit

struct SettingsView: View {
    @Bindable var session: WorkoutSession
    let healthAccess: HealthAccessController
    let watch: WatchConnectionController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                HealthAccessSection(healthAccess: healthAccess)
                Section("Workout mode") {
                    Picker("Mode", selection: $session.mode) {
                        ForEach(WorkoutMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("iPhone uses this phone’s camera. Rep and form analysis awaits the trained model. Demo simulates movement. Laptop receives backend events.")
                        .foregroundStyle(.secondary)
                }
                Section("Apple Watch") {
                    Toggle("Use Watch heart rate", isOn: $session.usesAppleWatch)
                    Text(watch.status).foregroundStyle(.secondary)
                    Button("Refresh Watch connection", action: watch.refresh)
                    Text("Install Gym&AI on the paired Watch and allow Health access there. Starting a workout on iPhone launches the Watch companion.")
                        .foregroundStyle(.secondary)
                }
                Section("Laptop connection") {
                    TextField("Backend URL", text: $session.backendAddress)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Existing session ID", text: $session.backendSessionId)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Access token (optional)", text: $session.token)
                    Text("Use localhost in Simulator. On an iPhone, enter the laptop’s LAN address. Start the backend and create the session first.")
                        .foregroundStyle(.secondary)
                }
                Section("Camera preview") {
                    TextField("MJPEG preview URL (optional)", text: $session.previewAddress)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Requires a separate MJPEG feed from the same webcam and session. The current backend does not publish video yet. A missing feed never replaces real video with a simulated image.")
                        .foregroundStyle(.secondary)
                }
                Section("Coaching") {
                    Toggle("Spoken coaching", isOn: $session.audioEnabled)
                    Text("Uses the iPhone’s speech voice in this build. Captions remain visible. Watch heart rate comes from the Gym&AI Watch companion. Voice commands are not connected yet.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done", action: dismiss.callAsFunction) }
            .tint(GymTheme.accent)
        }
    }
}
