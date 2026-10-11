import SwiftUI
import GymAndAIKit

struct TodayView: View {
    let session: WorkoutSession
    @Binding var showsPlan: Bool
    let openSettings: () -> Void
    @State private var mascotState = MascotState.idle
    @State private var celebration: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today")
                        .font(.largeTitle.bold())
                        .fontDesign(.rounded)
                        .accessibilityAddTraits(.isHeader)
                    Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.muted)
                }
                TodayWorkoutCard(
                    exercise: session.exercise,
                    mode: session.mode,
                    mascotState: mascotState,
                    celebrate: celebrate,
                    openPlan: openPlan
                )
                TodayWorkoutSourceView(mode: session.mode, openSettings: openSettings)
                TodayWelcomeView()
            }
            .padding(GymTheme.spacing)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TodayStartButton(isStarting: session.isSending, startWorkout: startWorkout)
                .padding(.horizontal, GymTheme.spacing)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
                .background(GymTheme.background)
        }
        .background(GymTheme.background.ignoresSafeArea())
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
