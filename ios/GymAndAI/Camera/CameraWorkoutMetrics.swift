import SwiftUI
import GymAndAIKit

struct CameraWorkoutMetrics: View {
    let session: WorkoutSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: GymTheme.Space.page) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                CameraHeartRateView(rate: session.heartRate, date: context.date)
            }
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
            Spacer(minLength: 0)
            CameraRepOverlay(session: session)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }
}
