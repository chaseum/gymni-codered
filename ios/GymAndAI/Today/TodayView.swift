import SwiftUI
import GymAndAIKit

struct TodayView: View {
    let session: WorkoutSession
    @Binding var showsPlan: Bool
    @State private var mascotState = MascotState.idle
    @AppStorage("companion") private var companion = CompanionKind.pip
    @State private var celebration: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: GymTheme.Space.page) {
                VStack(alignment: .leading, spacing: GymTheme.Space.tight) {
                    Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.subheadline.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(GymTheme.muted)
                    Text(session.history.isEmpty ? "Welcome" : "Welcome back")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: celebrate) {
                    CompanionStage(state: mascotState, progress: weekProgress)
                        .frame(maxWidth: 340)
                }
                .buttonStyle(.plain)
                .disabled(mascotState == .celebrate)
                .accessibilityLabel("Celebrate with \(companion.name)")
                .accessibilityHint("Plays a short celebration.")
                .accessibilityIdentifier("celebrate-pip")

                Text(weekText)
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.muted)

                Button { showsPlan = true } label: {
                    HStack(spacing: GymTheme.Space.related) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.plan.title).font(.headline)
                            Text("\(session.plan.items.count) exercises · \(session.plan.minutes) min")
                                .font(.subheadline).foregroundStyle(GymTheme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GymTheme.muted)
                    }
                    .padding(GymTheme.Space.inset)
                    .background(GymTheme.surface, in: .rect(cornerRadius: GymTheme.radius))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows today’s workout.")
                .accessibilityIdentifier("open-plan")
            }
            .padding(.horizontal, GymTheme.Space.page)
            .padding(.bottom, GymTheme.Space.page)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: startWorkout) {
                Label(session.isSending ? "Starting…" : "Start", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(session.isSending)
            .padding(.horizontal, GymTheme.Space.page)
            .padding(.vertical, GymTheme.Space.related)
            .frame(maxWidth: GymTheme.contentWidth)
            .accessibilityLabel("Start workout")
        }
        .gymPage()
        .onDisappear {
            celebration?.cancel()
            mascotState = .idle
        }
    }

    private var weekProgress: Double {
        Double(session.workoutsThisWeek()) / Double(session.plan.weeklyGoal)
    }

    private var weekText: String {
        "\(min(session.workoutsThisWeek(), session.plan.weeklyGoal)) of \(session.plan.weeklyGoal) workouts this week"
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

    private func startWorkout() { Task { await session.start() } }
}
