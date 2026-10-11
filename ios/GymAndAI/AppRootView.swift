import SwiftUI
import GymAndAIKit

struct AppRootView: View {
    @State private var session: WorkoutSession
    @State private var watch = WatchConnectionController()
    @State private var healthAccess = HealthAccessController()
    @State private var showsSettings = false
    @State private var showsPlan = false
    @State private var showsIntro = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        #if targetEnvironment(simulator)
        let defaultMode: WorkoutMode = .hub  // the simulator has no camera; the Pi / laptop session runs without one
        #else
        let defaultMode: WorkoutMode = .phone
        #endif
        let preferences: UserDefaults?
        if let flag = arguments.firstIndex(of: "--gymni-preferences-suite"), arguments.indices.contains(flag + 1) {
            preferences = UserDefaults(suiteName: arguments[flag + 1])
        } else {
            preferences = arguments.contains("--gymni-ui-testing") ? nil : .standard
        }
        let workout = WorkoutSession(defaultMode: defaultMode, preferences: preferences)
        #if targetEnvironment(simulator)
        workout.configureSimulatorLaunch(arguments: arguments)
        #endif
        _session = State(initialValue: workout)
        _showsIntro = State(initialValue: !workout.shouldAutoStartSimulatorSession)
    }

    var body: some View {
        @Bindable var session = session
        ZStack {
            dashboard(session: session)

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
        .task {
            guard session.consumeSimulatorAutoStartRequest() else { return }
            await session.start()
        }
        .tint(GymTheme.accent)
        .sheet(isPresented: $showsSettings) { SettingsView(session: session, healthAccess: healthAccess, watch: watch) }
        .sheet(isPresented: $showsPlan) { PlanView(session: session) }
        .fullScreenCover(isPresented: $session.presentsWorkout) { WorkoutFlowView(session: session, watch: watch) }
        .alert("Couldn’t complete that action", isPresented: errorBinding) {
            Button("OK", action: session.clearError)
        } message: {
            Text(session.errorMessage ?? "Please try again.")
        }
    }

    private func dashboard(session: WorkoutSession) -> some View {
        TabView {
            NavigationStack {
                TodayView(session: session, showsPlan: $showsPlan, openSettings: openSettings)
                    .toolbar {
                        if #available(iOS 26, *) {
                            ToolbarItem(placement: .topBarLeading) { BrandLogoView() }
                                .sharedBackgroundVisibility(.hidden)
                        } else {
                            ToolbarItem(placement: .topBarLeading) { BrandLogoView() }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Settings", systemImage: "gearshape", action: openSettings)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                    }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            NavigationStack {
                ProgressViewScreen(session: session)
                    .navigationTitle("Progress")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Progress", systemImage: "chart.bar") }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { session.errorMessage != nil && !session.presentsWorkout }, set: { if !$0 { session.clearError() } })
    }

    private func openSettings() { showsSettings = true }
}

#Preview { AppRootView() }
