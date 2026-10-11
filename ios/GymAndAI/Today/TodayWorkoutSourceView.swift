import SwiftUI
import GymAndAIKit

struct TodayWorkoutSourceView: View {
    let mode: WorkoutMode
    let openSettings: () -> Void

    var body: some View {
        Button(action: openSettings) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(GymTheme.accentText)
                    .frame(width: 28, height: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.bold())
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(GymTheme.muted)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Workout setup")
        .accessibilityValue("\(title). \(detail)")
        .accessibilityHint("Opens camera, audio, and Watch settings.")
    }

    private var symbol: String {
        switch mode {
        case .demo: "play.rectangle"
        case .phone: "iphone.gen3"
        case .backend: "web.camera"
        }
    }

    private var title: String {
        switch mode {
        case .demo: "Demo · Illustrative data"
        case .phone: "Your iPhone is your camera"
        case .backend: "Connected laptop workout"
        }
    }

    private var detail: String {
        switch mode {
        case .demo: "Explore the workout flow with simulated reps."
        case .phone: "Set your phone down and get in frame. Rep and form analysis are pending."
        case .backend: "Use your laptop camera or recorded footage."
        }
    }
}
