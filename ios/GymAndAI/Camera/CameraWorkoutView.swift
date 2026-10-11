import SwiftUI
import GymAndAIKit

struct CameraWorkoutView: View {
    @Bindable var session: WorkoutSession
    let toggleAudio: () -> Void
    @State private var stream = CameraPreviewStream()

    var body: some View {
        ZStack {
            GymTheme.background.ignoresSafeArea()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                CameraFrameView(stream: stream, date: context.date, isDemo: session.isDemo, hasURL: session.previewURL != nil)
            }
            .ignoresSafeArea()

            GymGlassContainer {
              VStack(spacing: 12) {
                HStack(alignment: .top) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        CameraHeartRateView(rate: session.snapshot?.heartRate, date: context.date)
                    }
                    Spacer(minLength: 24)
                    CameraRepOverlay(session: session)
                }
                Spacer(minLength: 12)
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.coachingMessage).font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .modifier(GymGlassSurface(cornerRadius: 16))
                        .accessibilityIdentifier("coach-message")
                    HStack(spacing: 12) {
                        Button("Reps", systemImage: "arrow.left") { session.display = .reps }
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityIdentifier("camera-back-to-reps")
                        Button(session.audioEnabled ? "Mute coach" : "Unmute coach", systemImage: session.audioEnabled ? "speaker.wave.2" : "speaker.slash", action: toggleAudio)
                            .labelStyle(.iconOnly)
                            .buttonStyle(CameraAudioButtonStyle())
                        Spacer(minLength: 0)
                        Button("Pause") { Task { await session.pause() } }
                            .buttonStyle(PrimaryButtonStyle())
                        Button("End", action: { Task { await session.end() } })
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityLabel("End workout")
                    }
                    .disabled(session.isSending)
                }
              }
              .padding(16)
            }
        }
        .task(id: session.previewURL) {
            if !session.isDemo, let url = session.previewURL { await stream.load(url) }
        }
    }
}
