public enum WorkoutMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case demo = "Demo"
    case phone = "iPhone"
    case backend = "Laptop"
    case hub = "Camera device"

    public var id: String { rawValue }
}
