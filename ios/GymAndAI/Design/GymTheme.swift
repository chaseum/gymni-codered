import SwiftUI
import GymAndAIKit

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
/// The circle is flat. It glows briefly only when `pulse` changes (a rep, a celebration): effects mean something.
struct CompanionStage: View {
    enum Size {
        case large, medium, small
        var width: CGFloat { switch self { case .large: 320; case .medium: 240; case .small: 112 } }
        var ring: CGFloat { self == .small ? 7 : 12 }
        var inset: CGFloat { self == .small ? 0 : 18 }
    }

    var state = MascotState.idle
    var progress: Double? = nil
    var size = Size.large
    /// A specific companion (onboarding's match); otherwise the chosen one.
    var companion: CompanionKind? = nil
    /// Glows for a moment each time this changes (e.g. the rep count).
    var pulse: Int = 0
    @State private var glow = false

    var body: some View {
        let ring = size.ring
        ZStack {
            Circle()
                .fill(GymTheme.surface)
                .overlay(Circle().fill(GymTheme.accent.opacity(glow ? 0.28 : 0)))
                .padding(ring * 1.6)
            if let progress {
                Circle().stroke(GymTheme.ringTrack, lineWidth: ring)
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))  // empty ring shows only the track
                    .stroke(GymTheme.accent, style: StrokeStyle(lineWidth: ring, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.45, dampingFraction: 0.7), value: progress)
            }
            Group {
                if let companion { CompanionSceneView(state: state, companion: companion).id(companion) }
                else { PipView(state: state) }
            }
            .padding(ring * 1.6 + size.inset)
        }
        .padding(ring / 2)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: size.width)
        .onChange(of: pulse) {
            withAnimation(.easeOut(duration: 0.12)) { glow = true }
            withAnimation(.easeIn(duration: 0.6).delay(0.15)) { glow = false }
        }
    }
}

/// An exercise glyph in a tinted circle, the way Fitness shows workout types.
struct ExerciseIcon: View {
    let exercise: Exercise
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: exercise.symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(GymTheme.accent)
            .frame(width: size, height: size)
            .background(GymTheme.accent.opacity(0.18), in: .circle)
            .accessibilityHidden(true)
    }
}

/// A number with a smaller, quieter unit after it: "62.5 kg", "3 sets".
struct Metric: View {
    let value: String
    let unit: String
    var font: Font = .system(.title2, design: .rounded).bold()

    var body: some View {
        (Text(value).font(font) + Text(" " + unit).font(.subheadline.weight(.semibold)).foregroundStyle(GymTheme.muted))
            .monospacedDigit()
    }
}

extension Metric {
    init(kg: Double, imperial: Bool, font: Font = .system(.title2, design: .rounded).bold()) {
        let value = TrainingLoad.value(kg, imperial: imperial).formatted(.number.precision(.fractionLength(0...1)))
        self.init(value: value, unit: imperial ? "lb" : "kg", font: font)
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
