import SwiftUI
import GymAndAIKit

struct CoachMessageView: View {
    let session: WorkoutSession
    var mascotState = MascotState.idle
    var message: String? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: GymTheme.Space.related))
            : AnyLayout(HStackLayout(alignment: .center, spacing: GymTheme.Space.related))
        layout {
            PipView(state: mascotState).frame(width: 64, height: 60)
            VStack(alignment: .leading, spacing: GymTheme.Space.small) {
                Text("Pip · Coach").font(GymTheme.TypeStyle.label).foregroundStyle(GymTheme.accentText)
                Text(message ?? session.coachingMessage).font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("coach-message")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(GymTheme.Space.inset)
        .modifier(GymSurface())
    }
}
