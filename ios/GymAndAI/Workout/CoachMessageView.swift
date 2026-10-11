import SwiftUI
import GymAndAIKit

struct CoachMessageView: View {
    let session: WorkoutSession
    var mascotState = MascotState.idle

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PipView(state: mascotState).frame(width: 64, height: 60)
            VStack(alignment: .leading, spacing: 8) {
                Text("COACH").font(.subheadline).foregroundStyle(GymTheme.accentText)
                Text(session.coachingMessage).font(.headline).accessibilityIdentifier("coach-message")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(GymTheme.surface, in: .rect(cornerRadius: GymTheme.radius))
    }

}
