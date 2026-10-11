import SwiftUI
import GymAndAIKit

struct TodayView: View {
    let session: WorkoutSession
    @Binding var showsPlan: Bool
    @State private var mascotState = MascotState.idle
    @State private var celebration: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GymTheme.spacing) {
                Label(session.mode == .demo ? "Demo · Illustrative data" : "Laptop coach", systemImage: "sparkle")
                    .font(.subheadline).foregroundStyle(GymTheme.cyan)
                Text("Ready when\nyou are.").font(.largeTitle.bold())
                Button(action: celebrate) {
                    PipView(state: mascotState).frame(width: 160, height: 140)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .disabled(mascotState == .celebrate)
                .accessibilityLabel("Celebrate with Pip")
                .accessibilityHint("Plays a short celebration.")
                .accessibilityIdentifier("celebrate-pip")
                Text("Your next session starts here.").foregroundStyle(GymTheme.muted)
                VStack(alignment: .leading, spacing: 12) {
                    Text("RECOMMENDED WORKOUT").font(.subheadline).foregroundStyle(GymTheme.cyan)
                    Text("Strength foundations").font(.title2.bold())
                    Text(session.mode == .demo ? "One demo set · 8 simulated reps" : "One connected set · 8 target reps")
                    Text(session.exercise.title).foregroundStyle(GymTheme.muted)
                    Button("View plan", action: openPlan).frame(minHeight: 44)
                }
                .padding(GymTheme.spacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GymTheme.surface, in: .rect(cornerRadius: GymTheme.radius))
                Button(action: startWorkout) {
                    if session.isSending { ProgressView().tint(GymTheme.background) }
                    else { Text("Start workout") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(session.isSending)
                Text("Set up the camera once. Your coach takes it from there.")
                    .font(.subheadline).foregroundStyle(GymTheme.muted)
            }
            .padding(GymTheme.spacing)
        }
        .background(GymTheme.background)
        .foregroundStyle(GymTheme.text)
        .onDisappear {
            celebration?.cancel()
            mascotState = .idle
        }
    }

    private func celebrate() {
        celebration?.cancel()
        mascotState = .celebrate
        celebration = Task {
            do {
                try await Task.sleep(for: .seconds(1.6))
                mascotState = .idle
            } catch { }
        }
    }

    private func openPlan() { showsPlan = true }
    private func startWorkout() { Task { await session.start() } }
}
