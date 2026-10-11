import SwiftUI
import GymAndAIKit

struct CameraPreviewView: View {
    let session: WorkoutSession
    @State private var stream = CameraPreviewStream()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    CameraFrameView(stream: stream, date: context.date, isDemo: session.isDemo, hasURL: session.previewURL != nil)
                }
                Text(session.targetReps.map { "\(session.repCount) / \($0) reps" } ?? "\(session.repCount) reps")
                    .font(.headline).monospacedDigit()
                    .padding(12)
                    .background(GymTheme.background, in: .rect(cornerRadius: 12))
                    .padding(12)
            }
            .frame(maxWidth: .infinity)
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 300 : 220)
            .background(GymTheme.surface, in: .rect(cornerRadius: GymTheme.radius))
            .clipShape(.rect(cornerRadius: GymTheme.radius))
            Text(session.isDemo ? "Illustrative camera layout · No video captured" : "External webcam preview · Reps come from the analyzer")
                .font(.subheadline).foregroundStyle(GymTheme.muted)
        }
        .task(id: session.previewURL) { await connectPreview() }
    }

    private func connectPreview() async {
        guard !session.isDemo, let url = session.previewURL else { return }
        await stream.load(url)
    }
}
