import SwiftUI

struct GymLogoIntroView: View {
    let onComplete: () -> Void

    @State private var liftProgress: CGFloat = 0
    @State private var isLeaving = false

    var body: some View {
        GeometryReader { geometry in
            let logoSize = min(geometry.size.width * 0.78, geometry.size.height * 0.68)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.13, green: 0.145, blue: 0.17),
                        Color(red: 0.08, green: 0.095, blue: 0.12)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                Image("GymLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: logoSize, height: logoSize)
                    .scaleEffect(x: 1, y: 1 + 0.035 * liftProgress, anchor: .bottom)
                    .offset(y: -12 * liftProgress)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .offset(y: isLeaving ? -geometry.size.height * 1.15 : 0)
            .contentShape(Rectangle())
            .onTapGesture(perform: onComplete)
            .task {
                try? await Task.sleep(for: .milliseconds(500))
                withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
                    liftProgress = 1
                }

                try? await Task.sleep(for: .milliseconds(520))
                withAnimation(.easeInOut(duration: 0.58)) {
                    isLeaving = true
                }

                try? await Task.sleep(for: .milliseconds(600))
                onComplete()
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gym and AI logo intro. Tap to continue.")
    }
}

#Preview {
    GymLogoIntroView(onComplete: {})
}
