import SwiftUI
import GymAndAIKit

struct SettingsView: View {
    @Bindable var session: WorkoutSession
    let healthAccess: HealthAccessController
    let watch: WatchConnectionController
    @Environment(OnboardingStore.self) private var onboarding
    @State private var showsProfileEditor = false
    @Environment(\.dismiss) private var dismiss
    @AppStorage("companion") private var companion = CompanionKind.pip

    var body: some View {
        NavigationStack {
            Form {
                Section("Training profile") {
                    if let profile = onboarding.profile {
                        LabeledContent("Focus", value: profile.focus.title)
                        Text("Matched companion: \(profile.focus.companion.capitalized)")
                            .foregroundStyle(GymTheme.muted)
                    } else {
                        Text("Your training profile hasn’t been set up yet.").foregroundStyle(GymTheme.muted)
                    }
                    Button(onboarding.profile == nil ? "Set up training profile" : "Edit training profile") {
                        onboarding.beginEditing()
                        showsProfileEditor = true
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("edit-training-profile")
                }
                .listRowBackground(GymTheme.surface)
                Section("Coach voice") {
                    if let status = session.voiceStatus { Text(status).foregroundStyle(GymTheme.muted) }
                    else { Label("ElevenLabs voice ready", systemImage: "checkmark.circle").foregroundStyle(GymTheme.accentText) }
                    Text("Coach prompts are saved on this iPhone after the first download. Your workout measurements stay on this iPhone.")
                        .foregroundStyle(GymTheme.muted)
                }
                .listRowBackground(GymTheme.surface)
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
                Section("Pi camera") {
                    Text("Your Pi runs the camera and movement model. Start a workout, then connect the Pi to the iPhone address shown on screen.")
                        .foregroundStyle(GymTheme.muted)
                    Text("Reps count only while the model recognizes your exercise and tracking is ready.")
                        .foregroundStyle(GymTheme.muted)
                    TextField("Pi preview URL (optional)", text: $session.previewAddress, prompt: Text("Pi preview URL (optional)").foregroundStyle(GymTheme.muted))
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if ProcessInfo.processInfo.arguments.contains("--gymni-ui-testing") {
                        Picker("Mode", selection: $session.mode) {
                            ForEach(WorkoutMode.allCases) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                    }
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
                Section("Spoken coaching") {
                    Toggle("Spoken coaching", isOn: $session.audioEnabled)
                        .tint(GymTheme.accent)
                    Text("Measured reps select form corrections, pace reminders, and count milestones. ElevenLabs clips are saved for reuse. Captions stay visible when muted or voice is unavailable.")
                        .foregroundStyle(GymTheme.muted)
                }
                .listRowBackground(GymTheme.surface)
            }
            .modifier(GymFormStyle())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done", action: dismiss.callAsFunction) }
            .sheet(isPresented: $showsProfileEditor) {
                NavigationStack {
                    OnboardingFlowView(store: onboarding, isEditing: true) { showsProfileEditor = false }
                        .toolbar(.hidden, for: .navigationBar)
                }
                .interactiveDismissDisabled()
            }
        }
    }

}
