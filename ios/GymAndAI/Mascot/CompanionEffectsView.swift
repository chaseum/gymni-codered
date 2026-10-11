import SwiftUI

/// Shared screen-space decoration; no extra geometry or textures in the USDZ.
struct CompanionEffectsView: View {
    let state: MascotState
    @State private var startedAt = Date()
    @State private var finished = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: finished)) { timeline in
            Canvas { context, size in
                let elapsed = max(0, timeline.date.timeIntervalSince(startedAt))
                if state == .celebrate && !finished {
                    confetti(context: context, size: size, progress: min(1, elapsed / 2.4))
                } else if state == .rest {
                    sleepLetters(context: context, size: size, elapsed: elapsed)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: state) {
            startedAt = Date()
            finished = false
            if state == .celebrate {
                do {
                    try await Task.sleep(for: .seconds(2.4))
                    finished = true
                } catch { return } // Disappearing or changing state cancels the burst.
            }
        }
    }

    private func confetti(context: GraphicsContext, size: CGSize, progress: Double) {
        let colors = [GymTheme.accentText, GymTheme.accent, GymTheme.text]
        for index in 0..<18 {
            let angle = Double(index) * .pi * 2 / 18
            let speed = 0.7 + Double(index % 4) * 0.1
            let x = 0.5 + cos(angle) * 0.38 * speed * progress
            let y = 0.48 - sin(angle) * 0.4 * speed * progress + 0.6 * progress * progress
            var piece = context
            piece.opacity = min(1, progress * 10) * max(0, 1 - progress * progress)
            piece.translateBy(x: size.width * x, y: size.height * y)
            piece.rotate(by: .radians(angle + progress * 5))
            let width = max(2, size.width * 0.015)
            piece.fill(Path(CGRect(x: -width / 2, y: -width, width: width, height: width * 2)),
                       with: .color(colors[index % colors.count]))
        }
    }

    private func sleepLetters(context: GraphicsContext, size: CGSize, elapsed: Double) {
        for index in 0..<3 {
            let progress = (elapsed / 3 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
            var letter = context
            letter.opacity = sin(.pi * progress)
            let text = Text("Z")
                .font(.system(size: max(8, size.width * 0.1), weight: .semibold, design: .rounded))
                .foregroundColor(GymTheme.accentText)
            letter.draw(text, at: CGPoint(x: size.width * (0.63 + progress * 0.19),
                                         y: size.height * (0.32 - progress * 0.22)))
        }
    }
}
