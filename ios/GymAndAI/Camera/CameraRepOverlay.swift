import SwiftUI
import GymAndAIKit

struct CameraRepOverlay: View {
    let session: WorkoutSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .trailing, spacing: GymTheme.Space.tight) {
            Text((session.snapshot?.exercise ?? session.exercise).title).font(.headline)
            if !dynamicTypeSize.isAccessibilitySize {
                Text(session.isPhone ? "Reps unmeasured" : "Completed reps")
                    .font(.subheadline).foregroundStyle(GymTheme.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: GymTheme.Space.small) {
                Text(session.isPhone ? "—" : "\(session.repCount)").font(.largeTitle.bold())
                if let target = session.targetReps { Text("/ \(target)").font(.title2) }
            }
            .monospacedDigit()
            Text(source).font(.subheadline).foregroundStyle(GymTheme.accentText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(GymTheme.Space.related)
        .modifier(CameraGlassPanel())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.isPhone ? "Reps not measured. Awaiting trained model." : session.targetReps.map { "\(session.repCount) of \($0) completed reps. \(source)" } ?? "\(session.repCount) completed reps. \(source)")
        .accessibilityIdentifier("camera-rep-count")
    }

    private var source: String {
        if session.isDemo { return "Simulated" }
        if session.isPhone { return "Unmeasured" }
        return session.snapshot?.source == .recorded ? "Recorded" : "Laptop"
    }
}
