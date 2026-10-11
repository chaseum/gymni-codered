import SwiftUI
import GymAndAIKit

/// Rest between sets (or a pause): the ring drains as the timer counts down.
struct RestView: View {
    let session: WorkoutSession
    var mascotState = MascotState.rest
    @State private var total = 1
    @State private var note: String?
    @AppStorage("userName") private var name = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = session.restRemaining(at: context.date)
            VStack(spacing: GymTheme.Space.section) {
                Text(session.setFinished ? "Rest" : "Paused")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                CompanionStage(state: mascotState, progress: Double(remaining) / Double(max(total, 1)), ringWidth: 12)
                    .frame(maxWidth: 320)
                Text(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .accessibilityIdentifier("rest-countdown")
                if let note {
                    Text(note)
                        .font(.headline)
                        .foregroundStyle(GymTheme.accentText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("rest-note")
                }
                if session.setFinished, let next = session.nextStep {
                    VStack(spacing: 2) {
                        Text("Up Next").font(.subheadline).foregroundStyle(GymTheme.muted)
                        Text("\(next.exercise.title) · Set \(next.set) of \(next.sets)").font(.headline)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let exercise = (session.setFinished ? session.nextStep : session.currentStep)?.exercise {
                    WeightControl(session: session, exercise: exercise)
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
        .task(id: session.stepIndex) { await writeNote() }
    }

    /// A rule-based line right away, then a written one about this set if the hosted coach answers in time.
    private func writeNote() async {
        guard session.setFinished, let step = session.currentStep else { note = nil; return }
        let result = session.results.first { $0.exercise == step.exercise }
        let person = name.isEmpty ? nil : name
        note = Coach.restLine(name: person, result: result, set: step.set, next: session.nextStep)
        guard let result else { return }
        let next = session.nextStep.map { "Next: \($0.exercise.displayName), set \($0.set) of \($0.sets)." } ?? ""
        let prompt = Coach.prompt(task: "One or two short sentences for the rest screen after set \(step.set) of \(step.exercise.displayName). Mention how the set went and one thing to do on the next set. \(next)",
                                  name: person, profile: nil, results: [result])
        if let written = await CoachWriter.write(prompt), !Task.isCancelled, session.setFinished { note = written }
    }
}
