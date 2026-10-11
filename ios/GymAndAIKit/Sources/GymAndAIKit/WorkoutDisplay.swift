public enum WorkoutDisplay: String, CaseIterable, Sendable, Identifiable {
    case reps = "Reps"
    case camera = "Camera"

    public var id: String { rawValue }
}
