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
                    CameraFrameView(stream: stream, date: context.date, hasURL: session.previewURL != nil, isRecorded: session.snapshot?.source == .recorded)
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
            Text(session.snapshot?.source == .recorded ? "Recorded footage · Reps counted on this iPhone" : "Pi or laptop camera · Reps counted on this iPhone")
                .font(.subheadline).foregroundStyle(GymTheme.muted)
        }
        .task(id: session.previewURL) { await connectPreview() }
    }

    private func connectPreview() async {
        guard let url = session.previewURL else { return }
        await stream.load(url)
    }
}
