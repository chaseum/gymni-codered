import SwiftUI

struct GymActionDock<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: GymTheme.Space.small) { content }
            .padding(.horizontal, GymTheme.Space.page)
            .padding(.vertical, GymTheme.Space.related)
            .frame(maxWidth: GymTheme.contentWidth)
            .frame(maxWidth: .infinity)
            .background(GymTheme.background)
            .overlay(alignment: .top) {
                Rectangle().fill(GymTheme.divider).frame(height: 1)
                    .accessibilityHidden(true)
            }
    }
}
