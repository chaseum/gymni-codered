import SwiftUI
import GymAndAIKit

/// Rest between sets (or a pause): the ring drains as the timer counts down.
struct RestView: View {
    let session: WorkoutSession
    var mascotState = MascotState.rest
    @State private var total = 1

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = session.restRemaining(at: context.date)
            VStack(spacing: GymTheme.Space.section) {
                Text(session.setFinished ? "Rest" : "Paused")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                CompanionStage(state: mascotState, progress: Double(remaining) / Double(max(total, 1)), ringWidth: 12)
                    .frame(maxWidth: 280)
                Text(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .accessibilityIdentifier("rest-countdown")
                if session.setFinished, let next = session.nextStep {
                    VStack(spacing: 2) {
                        Text("Up Next").font(.subheadline).foregroundStyle(GymTheme.muted)
                        Text("\(next.exercise.title) · Set \(next.set) of \(next.sets)").font(.headline)
                    }
                    .accessibilityElement(children: .combine)
                }
                Spacer(minLength: 0)
                VStack(spacing: GymTheme.Space.related) {
                    Button(session.setFinished ? "Start Next Set" : "Resume", systemImage: "play.fill") {
                        Task { await session.resume() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    HStack(spacing: GymTheme.Space.related) {
                        Button("+30 sec") { Task { await session.extendRest() } }
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityLabel("Add 30 seconds")
                        Button("End Workout") { Task { await session.end() } }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .disabled(session.isSending)
            }
            .onChange(of: remaining, initial: true) { total = max(total, remaining) }
            .sensoryFeedback(.success, trigger: remaining == 0) { _, done in done }
        }
        .padding(.horizontal, GymTheme.Space.page)
        .padding(.bottom, GymTheme.Space.small)
        .gymPage()
    }
}
