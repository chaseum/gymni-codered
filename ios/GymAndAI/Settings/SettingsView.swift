import SwiftUI
import GymAndAIKit

struct SettingsView: View {
    @Bindable var session: WorkoutSession
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("companion") private var companion = CompanionKind.pip
    @State private var showsProfileEditor = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Companion") {
                    Picker("Companion", selection: $companion) {
                        ForEach(CompanionKind.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("companion-choice")
                }
                Section {
                    Toggle("Voice Coaching", isOn: $session.audioEnabled)
                }
                Section {
                    Button("Edit Training Profile") {
                        onboarding.beginEditing()
                        showsProfileEditor = true
                    }
                    .accessibilityIdentifier("edit-training-profile")
                    Button("Permissions") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(GymTheme.background.ignoresSafeArea())
            .tint(GymTheme.accent)
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
