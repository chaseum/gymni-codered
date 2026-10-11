import SwiftUI
import GymAndAIKit

/// The set in progress: the companion is the focus, and its ring fills with each rep.
struct SetView: View {
    let session: WorkoutSession
    var mascotState = MascotState.idle
    @AppStorage("userName") private var name = ""

    var body: some View {
        VStack(spacing: GymTheme.Space.related) {
            ScrollView {
                setContent.padding(.bottom, GymTheme.Space.related)
            }
            .scrollBounceBehavior(.basedOnSize)
            WorkoutControls(session: session)
        }
        .padding(.horizontal, GymTheme.Space.page)
        .padding(.bottom, GymTheme.Space.small)
        .gymPage()
    }

    private var setContent: some View {
        VStack(spacing: GymTheme.Space.section) {
            VStack(spacing: GymTheme.Space.tight) {
                Text((session.snapshot?.exercise ?? session.exercise).title)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                if let step = session.currentStep {
                    Text("Set \(step.set) of \(step.sets), \(step.exercise.muscles.lowercased())")
                        .font(.subheadline).foregroundStyle(GymTheme.muted)
                }
            }
            CompanionStage(state: mascotState, progress: session.repProgress, pulse: session.repCount)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(session.repCount, format: .number)
                    .font(.system(.largeTitle, design: .rounded).bold())
                    .contentTransition(.numericText())
                    .animation(.snappy, value: session.repCount)
                    .accessibilityIdentifier("rep-count")
                if let target = session.targetReps {
                    Text("of \(target) reps").font(.subheadline.weight(.semibold)).foregroundStyle(GymTheme.muted)
                }
            }
            .monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(session.targetReps.map { "\(session.repCount) of \($0) reps" } ?? "\(session.repCount) reps")
            if let exercise = session.currentStep?.exercise { WeightControl(session: session, exercise: exercise) }
            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.default, value: message)
                .accessibilityIdentifier("coach-message")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: GymTheme.Space.page) {
                    Label(session.elapsed(at: context.date), systemImage: "stopwatch.fill")
                    if let bpm = session.bpm(at: context.date) {
                        Label { Text("\(bpm)") } icon: { Image(systemName: "heart.fill").foregroundStyle(.red) }
                            .accessibilityLabel("\(bpm) beats per minute")
                    }
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(GymTheme.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.impact(weight: .light), trigger: session.repCount)
    }

    /// The coach's line; after a correction lands, it says so.
    private var message: String {
        if mascotState == .happy { return name.isEmpty ? "That’s it. Keep it like that." : "That’s it, \(name). Keep it like that." }
        return session.coachingMessage
    }
}

/// End · Pause · Next, like the Workout app.
struct WorkoutControls: View {
    let session: WorkoutSession
    var size: CGFloat = 64

    var body: some View {
        HStack(spacing: size * 0.6) {
            Button("End Workout", systemImage: "xmark") { Task { await session.end() } }
                .buttonStyle(RoundButtonStyle(size: size))
            Button("Pause", systemImage: "pause.fill") { Task { await session.pause() } }
                .buttonStyle(RoundButtonStyle(prominent: true, size: size * 1.25))
            Button(session.nextStep == nil ? "Finish" : "Next Set",
                   systemImage: session.nextStep == nil ? "checkmark" : "forward.end.fill") { Task { await session.finishSet() } }
                .buttonStyle(RoundButtonStyle(size: size))
        }
        .disabled(session.isSending)
    }
}
