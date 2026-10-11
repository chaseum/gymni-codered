import SwiftUI
import GymAndAIKit

struct TodayWorkoutSourceView: View {
    let mode: WorkoutMode
    let openSettings: () -> Void

    var body: some View {
        Button(action: openSettings) {
            HStack(alignment: .top, spacing: GymTheme.Space.related) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(GymTheme.accentText)
                    .frame(width: 28, height: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: GymTheme.Space.tight) {
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
        case .phone: "iphone.gen3"
        case .hub: "camera.on.rectangle"
        }
    }

    private var title: String {
        switch mode {
        case .phone: "iPhone camera · Unmeasured"
        case .hub: "Pi camera · Live reps"
        }
    }

    private var detail: String {
        switch mode {
        case .phone: "Set your phone down and get in frame. Rep and form analysis are pending."
        case .hub: "Your Pi measures movement. This iPhone counts reps and saves your workout."
        }
    }
}
