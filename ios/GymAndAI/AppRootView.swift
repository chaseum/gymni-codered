import SwiftUI
import GymAndAIKit

struct AppRootView: View {
    @State private var session = WorkoutSession()
    @State private var healthAccess = HealthAccessController()
    @State private var showsSettings = false
    @State private var showsPlan = false

    var body: some View {
        @Bindable var session = session
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

    private var errorBinding: Binding<Bool> {
        Binding(get: { session.errorMessage != nil && !session.presentsWorkout }, set: { if !$0 { session.clearError() } })
    }

    private func openSettings() { showsSettings = true }
}

#Preview { AppRootView() }
