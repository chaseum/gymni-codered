import Foundation

/// Phone-owned history. Only committed reps are journaled; paused/untrusted observations never enter it.
@MainActor
final class WorkoutJournal {
    struct Rep: Codable, Sendable {
        var repCount: Int
        var receivedAtMs: Int64
        var observation: CameraObservation
        var baselineDurationMs: Double?
        var coachingText: String?
    }
    struct SetRecord: Codable, Sendable {
        var setId: String
        var exercise: Exercise
        var expectedReps: Int?
        var actualReps = 0
        var startedAtMs: Int64
        var endedAtMs: Int64?
        var activeDurationMs: Double = 0
        var repDurationMs: Double = 0
        var reps: [Rep] = []
    }
    struct Document: Codable, Sendable {
        var schemaVersion = 1
        var workoutId = UUID().uuidString
        var state: SessionState = .ready
        var sets: [SetRecord] = []
    }
    private var document = Document()
    private var activeSince: Double?
    private var pendingWrite: Task<Void, Never>?
    private let writer = WorkoutJournalWriter()
    let url: URL
    var onFailure: (@MainActor () -> Void)?

    init(url: URL) { self.url = url }

    func begin(setId: String, exercise: Exercise, expectedReps: Int?, at now: Int64) {
        document.sets.append(SetRecord(setId: setId, exercise: exercise, expectedReps: expectedReps, startedAtMs: now))
        activeSince = document.state == .active ? ProcessInfo.processInfo.systemUptime * 1000 : nil
        persist()
    }

    func transition(_ state: SessionState) {
        accumulateActiveTime()
        document.state = state
        activeSince = state == .active ? ProcessInfo.processInfo.systemUptime * 1000 : nil
        persist()
    }

    func append(_ observation: CameraObservation, count: Int, baseline: Double?, text: String?, at now: Int64) {
        guard !document.sets.isEmpty else { return }
        accumulateActiveTime()
        let index = document.sets.count - 1
        document.sets[index].actualReps = count
        document.sets[index].repDurationMs += observation.completedRep?.durationMs ?? 0
        document.sets[index].reps.append(Rep(repCount: count, receivedAtMs: now, observation: observation, baselineDurationMs: baseline, coachingText: text))
        persist()
    }

    func finish(at now: Int64) {
        guard !document.sets.isEmpty else { return }
        accumulateActiveTime()
        activeSince = nil
        document.sets[document.sets.count - 1].endedAtMs = now
        persist()
    }

    private func accumulateActiveTime() {
        let now = ProcessInfo.processInfo.systemUptime * 1000
        if let activeSince, !document.sets.isEmpty { document.sets[document.sets.count - 1].activeDurationMs += now - activeSince }
        if activeSince != nil { activeSince = now }
    }

    private func persist() {
        let previous = pendingWrite
        let snapshot = document
        pendingWrite = Task {
            await previous?.value
            do { try await writer.write(snapshot, to: url) }
            catch { onFailure?() }
        }
    }

    func flush() async { await pendingWrite?.value }
}
