import SwiftUI

enum GymTheme {
    static let background = Color.black
    static let surface = Color(white: 0.11)
    static let charcoal = Color(red: 14 / 255, green: 20 / 255, blue: 24 / 255)
    static let accent = Color(red: 0, green: 0.74, blue: 0.86)
    static let accentText = Color(red: 0.43, green: 0.84, blue: 0.92)
    static let text = Color.white
    static let muted = Color(white: 0.62)
    static let ringTrack = Color.white.opacity(0.1)

    enum Space {
        static let tight: CGFloat = 4
        static let small: CGFloat = 8
        static let related: CGFloat = 12
        static let inset: CGFloat = 16
        static let section: CGFloat = 20
        static let page: CGFloat = 24
        static let generous: CGFloat = 32
    }

    static let radius: CGFloat = 22
    static let contentWidth: CGFloat = 560
    static let controlHeight: CGFloat = 54
}

/// The companion in its circle; the ring shows progress (week, set, or rest) when given.
struct CompanionStage: View {
    var state = MascotState.idle
    var progress: Double? = nil
    var ringWidth: CGFloat = 10
    /// Space between the ring and the companion; smaller for small stages.
    var inset: CGFloat = 18
    /// A specific companion (onboarding's match); otherwise the chosen one.
    var companion: CompanionKind? = nil

    var body: some View {
        ZStack {
            Circle()
                .fill(EllipticalGradient(colors: [GymTheme.accent.opacity(0.42), GymTheme.accent.opacity(0.1), GymTheme.surface],
                                         center: .center, startRadiusFraction: 0, endRadiusFraction: 0.62))
                .shadow(color: GymTheme.accent.opacity(0.3), radius: 36)
                .padding(ringWidth * 1.6)
            if let progress {
                Circle().stroke(GymTheme.ringTrack, lineWidth: ringWidth)
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))  // empty ring shows only the track
                    .stroke(GymTheme.accent, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: progress)
            }
            Group {
                if let companion { CompanionSceneView(state: state, companion: companion).id(companion) }
                else { PipView(state: state) }
            }
            .padding(ringWidth * 1.6 + inset)
        }
        .padding(ringWidth / 2)
        .aspectRatio(1, contentMode: .fit)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, GymTheme.Space.page)
            .frame(maxWidth: .infinity, minHeight: GymTheme.controlHeight)
            .foregroundStyle(.black)
            .background(GymTheme.accent, in: .capsule)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(.capsule)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, GymTheme.Space.page)
            .frame(maxWidth: .infinity, minHeight: GymTheme.controlHeight)
            .foregroundStyle(GymTheme.text)
            .background(GymTheme.surface, in: .capsule)
            .opacity(isEnabled ? configuration.isPressed ? 0.7 : 1 : 0.4)
            .contentShape(.capsule)
    }
}

/// Round icon button, like the Workout app's End / Pause / Next.
struct RoundButtonStyle: ButtonStyle {
    var prominent = false
    var size: CGFloat = 64
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: size * 0.36, weight: .semibold))
            .frame(width: size, height: size)
            .foregroundStyle(prominent ? .black : GymTheme.text)
            .background(prominent ? GymTheme.accent : GymTheme.surface, in: .circle)
            .opacity(isEnabled ? configuration.isPressed ? 0.75 : 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(.circle)
    }
}

extension View {
    /// Black page with the readable content width.
    func gymPage() -> some View {
        frame(maxWidth: GymTheme.contentWidth)
            .frame(maxWidth: .infinity)
            .background(GymTheme.background.ignoresSafeArea())
            .foregroundStyle(GymTheme.text)
    }
}
