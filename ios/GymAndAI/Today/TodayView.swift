import SwiftUI
import GymAndAIKit

struct TodayView: View {
    let session: WorkoutSession
    @Binding var showsPlan: Bool
    let openSettings: () -> Void
    @Environment(OnboardingStore.self) private var onboarding
    @State private var mascotState = MascotState.idle
    @State private var celebration: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GymTheme.Space.page) {
                VStack(alignment: .leading, spacing: GymTheme.Space.small) {
                    Text("Today")
                        .font(.title2.bold())
                        .fontDesign(.rounded)
                        .accessibilityAddTraits(.isHeader)
                    Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.muted)
                }
                if let profile = onboarding.profile {
                    Text("Your focus · \(profile.focus.title)")
                        .font(.subheadline.bold())
                        .foregroundStyle(GymTheme.accentText)
                        .accessibilityIdentifier("training-focus-summary")
                }
                TodayWorkoutCard(
                    exercise: session.exercise,
                    mode: session.mode,
                    mascotState: mascotState,
                    celebrate: celebrate,
                    openPlan: openPlan
                )
                TodayWorkoutSourceView(mode: session.mode, openSettings: openSettings)
                TodayWelcomeView(exercise: session.exercise)
            }
            .padding(GymTheme.spacing)
            .frame(maxWidth: GymTheme.contentWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GymActionDock {
                TodayStartButton(isStarting: session.isSending, startWorkout: startWorkout)
            }
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
                try await Task.sleep(for: .seconds(2.4))
                mascotState = .idle
            } catch { }
        }
    }

    private func openPlan() { showsPlan = true }
    private func startWorkout() { Task { await session.start() } }
}
