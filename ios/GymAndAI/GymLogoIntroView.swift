import SwiftUI

/// Boot animation: the lifter raises the bar, then moves up to reveal onboarding or Today.
struct GymLogoIntroView: View {
    let onComplete: () -> Void

    @State private var liftProgress: CGFloat = 0
    @State private var isLeaving = false

    var body: some View {
        GeometryReader { geometry in
            let logoSize = min(geometry.size.width * 0.78, geometry.size.height * 0.68)

            ZStack {
                GymTheme.background.ignoresSafeArea()

                Image("GymLogoLight")
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
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
                    liftProgress = 1
                }

                do { try await Task.sleep(for: .milliseconds(520)) } catch { return }
                withAnimation(.easeInOut(duration: 0.58)) {
                    isLeaving = true
                }

                do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
                onComplete()
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gym&I. Tap to continue.")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview { GymLogoIntroView(onComplete: {}) }
