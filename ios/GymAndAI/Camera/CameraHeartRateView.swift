import SwiftUI
import GymAndAIKit

struct CameraHeartRateView: View {
    let rate: HeartRateView?
    let date: Date
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: GymTheme.Space.tight) {
            Label(dynamicTypeSize.isAccessibilitySize ? "Watch" : "Apple Watch", systemImage: "heart.fill")
                .font(.subheadline).foregroundStyle(GymTheme.accentText)
            Text(isFresh ? reading : "Unavailable")
                .font(isFresh ? .largeTitle.bold() : .headline)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            if isFresh || !dynamicTypeSize.isAccessibilitySize {
                Text(freshness).font(.subheadline).foregroundStyle(GymTheme.muted)
            }
        }
        .padding(GymTheme.Space.related)
        .modifier(CameraGlassPanel())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Apple Watch. \(isFresh ? reading : "Heart rate unavailable"). \(freshness)")
        .accessibilityIdentifier("camera-heart-rate")
    }

    private var sampleAge: Double? {
        guard let timestamp = rate?.sampleTimestampMs else { return nil }
        return date.timeIntervalSince1970 - Double(timestamp) / 1_000
    }

    private var isFresh: Bool {
        guard rate?.source == "apple_watch", rate?.status == .live,
              let bpm = rate?.bpm, bpm.isFinite, (20...250).contains(bpm),
              let age = sampleAge else { return false }
        return age >= 0 && age <= 10
    }

    private var reading: String {
        guard isFresh, let bpm = rate?.bpm else { return "Unavailable" }
        return "\(Int(bpm.rounded())) bpm"
    }

    private var freshness: String {
        if isFresh, let age = sampleAge { return "Updated \(Int(age))s ago" }
        if rate?.source == "apple_watch", rate?.status != .unavailable { return "Waiting for a fresh sample" }
        return "No fresh Watch reading"
    }
}
