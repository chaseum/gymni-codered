import SwiftUI
import GymAndAIKit

struct CameraRepOverlay: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("COMPLETED REPS").font(.caption).foregroundStyle(GymTheme.accentText)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(session.isPhone ? "—" : "\(session.repCount)").font(.largeTitle.bold())
                if let target = session.targetReps { Text("/ \(target)").font(.title2) }
            }
            .monospacedDigit()
            Text(session.isDemo ? "Illustrative data" : session.isPhone ? "Awaiting model" : "Analyzer count")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .modifier(CameraGlassPanel())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.isPhone ? "Reps not measured. Awaiting trained model." : session.targetReps.map { "\(session.repCount) of \($0) completed reps" } ?? "\(session.repCount) completed reps")
        .accessibilityIdentifier("camera-rep-count")
    }
}
