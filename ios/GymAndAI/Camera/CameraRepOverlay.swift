import SwiftUI
import GymAndAIKit

struct CameraRepOverlay: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("COMPLETED REPS").font(.caption).foregroundStyle(GymTheme.cyan)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(session.repCount, format: .number).font(.largeTitle.bold())
                if let target = session.targetReps { Text("/ \(target)").font(.title2) }
            }
            .monospacedDigit()
            Text(session.isDemo ? "Illustrative data" : "Analyzer count")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .modifier(GymGlassSurface(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.targetReps.map { "\(session.repCount) of \($0) completed reps" } ?? "\(session.repCount) completed reps")
        .accessibilityIdentifier("camera-rep-count")
    }
}
