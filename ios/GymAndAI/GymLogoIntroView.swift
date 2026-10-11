import SwiftUI

struct GymLogoIntroView: View {
    let onComplete: () -> Void

    var body: some View {
        Button(action: onComplete) {
            Image("GymAILogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 240)
                .padding(GymTheme.Space.inset)
                .padding(GymTheme.Space.page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(GymTheme.background)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .ignoresSafeArea()
        .accessibilityLabel("Gym&I. Continue to Today.")
        .task {
            do {
                try await Task.sleep(for: .milliseconds(650))
                onComplete()
            } catch { }
        }
    }
}

#Preview { GymLogoIntroView(onComplete: {}) }
