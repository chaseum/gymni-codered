public enum WorkoutMode: String, CaseIterable, Sendable, Identifiable {
    case demo = "Demo"
    case backend = "Laptop"

    public var id: String { rawValue }
}
