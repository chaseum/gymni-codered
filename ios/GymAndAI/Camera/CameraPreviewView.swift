import SwiftUI
import GymAndAIKit

struct CameraPreviewView: View {
    let session: WorkoutSession
    @State private var stream = CameraPreviewStream()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: GymTheme.Space.related) {
            ZStack(alignment: .bottomLeading) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    CameraFrameView(stream: stream, date: context.date, isDemo: session.isDemo, hasURL: session.previewURL != nil, isRecorded: session.snapshot?.source == .recorded)
                }
                Text(session.targetReps.map { "\(session.repCount) / \($0) reps" } ?? "\(session.repCount) reps")
                    .font(.headline).monospacedDigit()
                    .padding(GymTheme.Space.related)
                    .background(GymTheme.background, in: .rect(cornerRadius: 12))
                    .padding(GymTheme.Space.related)
            }
            .frame(maxWidth: .infinity)
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 300 : 220)
            .background(GymTheme.surface, in: .rect(cornerRadius: GymTheme.radius))
            .clipShape(.rect(cornerRadius: GymTheme.radius))
            Text(session.isDemo ? "Illustrative camera layout · No video captured" : session.snapshot?.source == .recorded ? "Recorded footage · Reps come from the analyzer" : "External webcam preview · Reps come from the analyzer")
                .font(.subheadline).foregroundStyle(GymTheme.muted)
        }
        .task(id: session.previewURL) { await connectPreview() }
    }

    private func connectPreview() async {
        guard !session.isDemo, let url = session.previewURL else { return }
        await stream.load(url)
    }
}
