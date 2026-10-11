import SwiftUI
import GymAndAIKit

struct AppRootView: View {
    @State private var onboarding: OnboardingStore
    private let bypassOnboarding: Bool
    @State private var session: WorkoutSession
    @State private var heartRate = HeartRateMonitor()
    @State private var showsSettings = false
    @State private var showsPlan = false
    @State private var showsIntro: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let testing = arguments.contains("--gymni-ui-testing")
        let defaultMode: WorkoutMode = .hub
        let preferences: UserDefaults?
        if let flag = arguments.firstIndex(of: "--gymni-preferences-suite"), arguments.indices.contains(flag + 1) {
            preferences = UserDefaults(suiteName: arguments[flag + 1])
        } else {
            preferences = arguments.contains("--gymni-ui-testing") ? nil : .standard
        }
        let workout = WorkoutSession(defaultMode: defaultMode, preferences: preferences)
        if !testing { workout.useMainAppConfiguration() }
        #if targetEnvironment(simulator)
        workout.configureSimulatorLaunch(arguments: arguments)
        #endif
        // Connect to the preset coach and download the workout clips now, so they're on the phone before a set.
        if !testing { workout.configureHostedCoach(warmWorkout: true) }
        _onboarding = State(initialValue: OnboardingStore(preferences: preferences ?? .standard))
        #if DEBUG
        bypassOnboarding = (testing && !arguments.contains("--gymni-onboarding-testing")) || arguments.contains("--gymni-skip-onboarding") || workout.shouldAutoStartSimulatorSession
        #else
        bypassOnboarding = false
        #endif
        _session = State(initialValue: workout)
        _showsIntro = State(initialValue: !workout.shouldAutoStartSimulatorSession)
    }

    var body: some View {
        @Bindable var session = session
        ZStack {
            if onboarding.needsOnboarding && !bypassOnboarding {
                NavigationStack {
                    OnboardingFlowView(store: onboarding, onComplete: {})
                        .toolbar(.hidden, for: .navigationBar)
                }
            } else {
                dashboard(session: session)
            }

            if showsIntro && !reduceMotion {
                GymLogoIntroView {
                    withAnimation(.easeOut(duration: 0.25)) {
                        showsIntro = false
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .onAppear {
            if reduceMotion { showsIntro = false }
        }
        .onChange(of: onboarding.profile, initial: true) { session.usePlan(WorkoutPlan.make(for: onboarding.profile)) }
        .task {
            guard session.consumeSimulatorAutoStartRequest() else { return }
            await session.start()
        }
        .tint(GymTheme.accent)
        .sheet(isPresented: $showsSettings) { SettingsView(session: session) }
        .sheet(isPresented: $showsPlan) { PlanView(session: session) }
        .fullScreenCover(isPresented: $session.presentsWorkout) { WorkoutFlowView(session: session, heartRate: heartRate) }
        .alert("Couldn’t complete that action", isPresented: errorBinding) {
            Button("OK", action: session.clearError)
        } message: {
            Text(session.errorMessage ?? "Please try again.")
        }
        .environment(onboarding)
    }

    private func dashboard(session: WorkoutSession) -> some View {
        TabView {
            NavigationStack {
                TodayView(session: session, showsPlan: $showsPlan)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Settings", systemImage: "gearshape", action: openSettings)
                        }
                    }
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
            .tabItem { Label("Today", systemImage: "figure.strengthtraining.traditional") }
            NavigationStack {
                ProgressViewScreen(session: session)
                    .navigationTitle("Progress")
            }
            .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { session.errorMessage != nil && !session.presentsWorkout }, set: { if !$0 { session.clearError() } })
    }

    private func openSettings() { showsSettings = true }
}

#Preview { AppRootView() }
