import SwiftUI

struct GymFormStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(GymTheme.background.ignoresSafeArea())
            .foregroundStyle(GymTheme.text)
            .listRowBackground(GymTheme.surface)
            .tint(GymTheme.accentText)
    }
}
