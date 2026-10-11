import SwiftUI
import GymAndAIKit

/// The set in progress: the companion's ring fills with each rep.
struct SetView: View {
    let session: WorkoutSession
    var mascotState = MascotState.idle

    var body: some View {
        VStack(spacing: GymTheme.Space.related) {
            ScrollView {
                setContent
                    .padding(.bottom, GymTheme.Space.related)
            }
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
                    Text("Set \(step.set) of \(step.sets)").font(.subheadline).foregroundStyle(GymTheme.muted)
                }
            }
            Button { session.display = .camera } label: {
                PiCameraPreview(url: session.previewURL)
                    .frame(height: 180)
                    .allowsHitTesting(false)
                    .overlay(alignment: .topLeading) {
                        Label("Pi camera", systemImage: "video.fill")
                            .font(.caption.bold()).padding(8)
                            .background(.black.opacity(0.6), in: .capsule).padding(8)
                    }
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .padding(8).background(.black.opacity(0.6), in: .circle).padding(8)
                    }
                    .clipShape(.rect(cornerRadius: 18))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open full screen Pi camera")
            .accessibilityIdentifier("open-pi-camera")
            CompanionStage(state: mascotState, progress: session.repProgress, ringWidth: 12)
                .frame(maxWidth: 160)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(session.repCount, format: .number)
                    .font(.system(size: 76, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: session.repCount)
                    .accessibilityIdentifier("rep-count")
                if let target = session.targetReps {
                    Text("/ \(target)").font(.title2.weight(.semibold)).foregroundStyle(GymTheme.muted)
                }
            }
            .monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(session.targetReps.map { "\(session.repCount) of \($0) reps" } ?? "\(session.repCount) reps")
            Text(session.coachingMessage)
                .font(.headline)
                .foregroundStyle(GymTheme.accentText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("coach-message")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: GymTheme.Space.page) {
                    Label(session.elapsed(at: context.date), systemImage: "timer")
                    if let bpm = session.bpm(at: context.date) {
                        Label("\(bpm)", systemImage: "heart.fill").accessibilityLabel("\(bpm) beats per minute")
                    }
                }
                .font(.headline.monospacedDigit())
                .foregroundStyle(GymTheme.muted)
            }
        }
        .frame(maxWidth: .infinity)
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
