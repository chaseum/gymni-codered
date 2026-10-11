public enum WorkoutMode: String, CaseIterable, Sendable, Identifiable {
    case demo = "Demo"
    case phone = "iPhone"
    case backend = "Laptop"

    public var id: String { rawValue }
}
