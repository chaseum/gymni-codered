import SwiftUI
import GymAndAIKit

/// Landscape camera view, like Fitness+: metrics top left, the companion's rep ring top right.
struct CameraWorkoutView: View {
    @Bindable var session: WorkoutSession
    var mascotState = MascotState.idle
    let toggleAudio: () -> Void

    var body: some View {
        overlay
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                PiCameraPreview(url: session.previewURL)
                    .ignoresSafeArea()
            }
            .background(GymTheme.background.ignoresSafeArea())
    }

    private var overlay: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.elapsed(at: context.date)).font(.system(.title, design: .rounded).bold())
                            if let bpm = session.bpm(at: context.date) {
                                Label("\(bpm)", systemImage: "heart.fill").font(.title3.bold())
                                    .labelStyle(TrailingIconLabelStyle())
                                    .accessibilityLabel("\(bpm) beats per minute")
                            }
                        }
                    }
                    Text(session.targetReps.map { "\(session.repCount)/\($0) REPS" } ?? "\(session.repCount) REPS")
                        .font(.title3.bold())
                        .accessibilityIdentifier("camera-rep-count")
                    if let step = session.currentStep {
                        Text(step.label).font(.subheadline).foregroundStyle(GymTheme.muted)
                    }
                }
                .monospacedDigit()
                .padding(GymTheme.Space.inset)
                .background(.black.opacity(0.45), in: .rect(cornerRadius: 18))
                .accessibilityElement(children: .combine)
                Spacer()
                CompanionStage(state: mascotState, progress: session.repProgress, ringWidth: 7, inset: 0)
                    .frame(width: 112)
            }
            Spacer()
            Text(session.coachingMessage)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, GymTheme.Space.section)
                .padding(.vertical, GymTheme.Space.related)
                .background(.black.opacity(0.45), in: .capsule)
                .accessibilityIdentifier("coach-message")
            HStack {
                Button("Show Reps", systemImage: "circle.circle") { session.display = .reps }
                    .buttonStyle(RoundButtonStyle(size: 48))
                    .accessibilityIdentifier("camera-back-to-reps")
                Button(session.audioEnabled ? "Mute Coach" : "Unmute Coach",
                       systemImage: session.audioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill", action: toggleAudio)
                    .buttonStyle(RoundButtonStyle(size: 48))
                Spacer()
                WorkoutControls(session: session, size: 48)
            }
        }
        .padding(.horizontal, GymTheme.Space.section)
        .padding(.vertical, GymTheme.Space.related)
        .foregroundStyle(GymTheme.text)
    }
}

/// The Pi's video. Its own view, so new frames redraw only the picture, not the companion's 3D scene.
struct PiCameraPreview: View {
    let url: URL?
    @State private var stream = CameraPreviewStream()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if url != nil, let image = stream.image, let frameDate = stream.frameDate, context.date.timeIntervalSince(frameDate) < 3 {
                GeometryReader { geometry in
                    Image(image, scale: 1, label: Text("Live Pi camera"))
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .accessibilityIdentifier("pi-camera-frame")
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "video").font(.title2)
                    Text(url == nil ? "Waiting for Pi camera" : stream.status == "Camera preview connected" ? "Reconnecting to Pi camera…" : stream.status)
                        .font(.subheadline.bold())
                    Text(url == nil ? "Turn on Personal Hotspot and power the Pi." : "Keep Personal Hotspot on and allow Gym&I Local Network access in Settings.")
                        .font(.caption).foregroundStyle(GymTheme.muted)
                }
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.black)
        .task(id: url) {
            if let url { await stream.load(url) }
        }
    }
}

/// "136 ♥", number first like Fitness+.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.foregroundStyle(.red)
        }
    }
}
