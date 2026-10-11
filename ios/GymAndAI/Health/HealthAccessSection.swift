import SwiftUI

struct HealthAccessSection: View {
    let healthAccess: HealthAccessController

    var body: some View {
        Section {
            Text(healthAccess.state.message)
                .accessibilityIdentifier("health-access-status")
            Button("Connect Apple Health", systemImage: "heart.fill", action: connectHealth)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(healthAccess.state == .requesting || healthAccess.state == .unavailable)
                .accessibilityIdentifier("connect-apple-health")
            if healthAccess.state == .requesting {
                ProgressView("Requesting permission…")
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text("This button requests heart-rate read access on iPhone. Live readings require the Gym&AI Watch companion and Health access on your Watch.")
        }
    }

    private func connectHealth() {
        Task { await healthAccess.requestHeartRateAccess() }
    }
}
