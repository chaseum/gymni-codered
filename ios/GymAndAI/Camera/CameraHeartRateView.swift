import SwiftUI
import GymAndAIKit

struct CameraHeartRateView: View {
    let rate: HeartRateView?
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Apple Watch", systemImage: "heart.fill")
                .font(.caption).foregroundStyle(GymTheme.cyan)
            Text(reading).font(.title2.bold()).monospacedDigit()
            Text(freshness).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .modifier(GymGlassSurface(cornerRadius: 16))
        .accessibilityElement(children: .combine)
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
        return "No Watch data connected"
    }
}
