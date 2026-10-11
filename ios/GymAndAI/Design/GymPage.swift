import SwiftUI

struct GymPage<Content: View>: View {
    var accessibilityIdentifier = "gym-page-content"
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GymTheme.Space.page) { content }
                .padding(GymTheme.Space.page)
                .frame(maxWidth: GymTheme.contentWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .scrollIndicators(.hidden)
        .background(GymTheme.background.ignoresSafeArea())
        .foregroundStyle(GymTheme.text)
    }
}
