import SwiftUI
import GymAndAIKit

struct AppRootView: View {
    @State private var session = WorkoutSession()
    @State private var healthAccess = HealthAccessController()
    @State private var showsSettings = false
    @State private var showsPlan = false
    @State private var showsIntro = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .tint(GymTheme.lime)
        .sheet(isPresented: $showsSettings) { SettingsView(session: session, healthAccess: healthAccess) }
        .sheet(isPresented: $showsPlan) { PlanView(session: session) }
        .fullScreenCover(isPresented: $session.presentsWorkout) { WorkoutFlowView(session: session) }
        .alert("Couldn’t complete that action", isPresented: errorBinding) {
            Button("OK", action: session.clearError)
        } message: {
            Text(session.errorMessage ?? "Please try again.")
        }
    }

    private func dashboard(session: WorkoutSession) -> some View {
        TabView {
            NavigationStack {
                TodayView(session: session, showsPlan: $showsPlan)
                    .toolbar {
                        ToolbarItem(placement: .principal) { Text("Gym&AI").font(.headline) }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Settings", systemImage: "gearshape", action: openSettings)
                        }
                    }
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            NavigationStack {
                ProgressViewScreen(session: session)
                    .navigationTitle("Progress")
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
