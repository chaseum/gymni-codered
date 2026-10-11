public enum WorkoutMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case phone = "iPhone camera"
    case hub = "Pi / laptop camera"

    public var id: String { rawValue }
}
