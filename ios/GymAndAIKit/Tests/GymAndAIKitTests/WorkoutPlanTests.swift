import Foundation
import Testing
@testable import GymAndAIKit

@Test func planFollowsGoalEquipmentExperienceAndTime() {
    let squatDay = WorkoutPlan.make(focus: .strength, answers: ["days": "4"])
    #expect(squatDay.title == "Strength · Squat Day")
    #expect(squatDay.items.map(\.exercise) == [.squat, .curl])
    #expect(squatDay.items[0].range == 4...6 && squatDay.items[0].sets == 4 && squatDay.items[0].restSeconds == 180)
    #expect(squatDay.weeklyGoal == 4)

    let oneDone = [CompletedWorkout(date: .now, title: "", sets: 1, reps: 5, durationSeconds: 60)]
    let deadliftDay = WorkoutPlan.make(focus: .strength, answers: [:], history: oneDone)
    #expect(deadliftDay.items.map(\.exercise) == [.deadlift, .squat, .curl])  // big lifts first, days alternate

    let muscle = WorkoutPlan.make(focus: .muscle, answers: [:])
    #expect(muscle.items[0].range == 8...12 && muscle.items[1].range == 10...15)

    let bodyweight = WorkoutPlan.make(focus: .muscle, answers: ["equipment": "bodyweight"])
    #expect(bodyweight.items.map(\.exercise) == [.squat] && bodyweight.items[0].range == 15...20)

    let beginner = WorkoutPlan.make(focus: .strength, answers: ["experience": "new", "duration": "20"])
    #expect(beginner.items.map(\.sets) == [3, 2])  // one set fewer, never below two
    #expect(beginner.items[0].range == 6...8)       // beginners stay at 6+ reps
    #expect(beginner.weeklyGoal == 3)               // unanswered schedule defaults to three days
}

private func workout(_ results: [ExerciseResult]) -> CompletedWorkout {
    CompletedWorkout(date: .now, title: "", sets: 3, reps: 30, durationSeconds: 600, results: results)
}

@Test func adjustmentsFollowDoubleProgressionAndFormFirst() {
    let history = [workout([
        ExerciseResult(exercise: .squat, reps: [12, 12, 12], low: 8, high: 12),
        ExerciseResult(exercise: .curl, reps: [15, 11], low: 10, high: 15, corrections: ["Keep your elbows pinned.": 3]),
        ExerciseResult(exercise: .deadlift, reps: [10, 8, 5], low: 6, high: 10),
    ])]
    let changes = Dictionary(uniqueKeysWithValues: Coach.adjustments(from: history).map { ($0.exercise, $0.kind) })
    #expect(changes == [.squat: .addLoad, .curl: .formFocus, .deadlift: .reduceLoad])
    let steady = Coach.adjustments(from: [workout([ExerciseResult(exercise: .squat, reps: [10, 9], low: 8, high: 12)])])
    #expect(steady.map(\.kind) == [.holdLoad])

    let plan = WorkoutPlan.make(focus: .muscle, answers: [:], adjustments: Coach.adjustments(from: history))
    let squat = plan.items.first { $0.exercise == .squat }!, curl = plan.items.first { $0.exercise == .curl }!
    #expect(squat.note == "Add weight" && squat.range == 8...12)
    #expect(curl.note == "Form first" && curl.range == 8...13)  // two fewer reps while form settles
}

@Test func suggestionsCarryARealWeightInThePersonsUnits() {
    let history = [workout([
        ExerciseResult(exercise: .squat, reps: [12, 12, 12], low: 8, high: 12, weights: [60, 60, 60]),
        ExerciseResult(exercise: .deadlift, reps: [10, 8, 5], low: 6, high: 10, weights: [100, 100, 100]),
    ])]
    let kg = Dictionary(uniqueKeysWithValues: Coach.adjustments(from: history).map { ($0.exercise, $0.load) })
    #expect(kg[.squat] == 62.5)    // +2.5 kg
    #expect(kg[.deadlift] == 92.5) // about 7.5% lighter, on the 2.5 kg grid
    let lb = Coach.adjustments(from: [workout([ExerciseResult(exercise: .squat, reps: [12], low: 8, high: 12,
                                                              weights: [135 * 0.45359237])])], imperial: true)
    #expect(TrainingLoad.text(lb[0].load!, imperial: true) == "140 lb")  // +5 lb
    let plan = WorkoutPlan.make(focus: .muscle, answers: [:], adjustments: Coach.adjustments(from: history),
                                loads: [.curl: 12])
    #expect(plan.items.first { $0.exercise == .squat }?.weight == 62.5)
    #expect(plan.items.first { $0.exercise == .curl }?.weight == 12)  // no change: keeps the last weight
}

@Test func memoriesAndWrittenLinesStayShortAndFactual() {
    let history = [workout([ExerciseResult(exercise: .curl, reps: [12, 14], low: 10, high: 15, corrections: ["Keep your elbows pinned.": 2])])]
    let facts = Coach.memories(profile: nil, history: history).map(\.text)
    #expect(facts.contains("Most common cue: keep your elbows pinned (2×)"))
    #expect(facts.contains("Best biceps curl set: 14 reps"))
    #expect(Coach.clean("**Great work, Chase.** Add weight next time. What days do you train?") == "Great work, Chase.")
    #expect(Coach.clean("How was it?") == nil)
    let line = Coach.restLine(name: "Chase", result: history[0].results![0], set: 2, next: nil)
    #expect(line == "14 reps, Chase. Next set, think: keep your elbows pinned.")
}

@MainActor @Test func sessionWalksThePlanSetBySet() async throws {
    let session = WorkoutSession(defaultMode: .hub)
    session.hubPort = UInt16.random(in: 20_000...40_000)
    session.usePlan(WorkoutPlan(title: "Test", items: [
        .init(exercise: .squat, sets: 2, reps: 5, restSeconds: 30),
        .init(exercise: .curl, sets: 1, reps: 8, restSeconds: 30)], weeklyGoal: 3))
    await session.start()
    #expect(session.snapshot?.state == .active)
    #expect(session.snapshot?.exercise == .squat && session.targetReps == 5)

    await session.finishSet()  // squat 1 → rest
    #expect(session.snapshot?.state == .paused && session.setFinished)
    #expect(session.nextStep?.set == 2)
    await session.resume()     // squat 2
    #expect(session.snapshot?.state == .active && !session.setFinished)
    #expect(session.currentStep?.set == 2 && session.snapshot?.exercise == .squat)

    await session.finishSet()
    await session.resume()     // curl 1
    #expect(session.snapshot?.exercise == .curl && session.targetReps == 8)

    await session.pause()      // a manual pause resumes the same set
    await session.resume()
    #expect(session.currentStep?.exercise == .curl && session.snapshot?.state == .active)

    await session.finishSet()  // last set ends the workout
    #expect(session.snapshot?.state == .complete)
    session.returnToday()
}

@MainActor @Test func previewStaysWithOneCameraUntilItGoesQuiet() {
    let session = WorkoutSession()
    let t0 = Date(timeIntervalSince1970: 1_000)
    session.cameraDidConnect("172.20.10.2", now: t0)
    session.cameraDidConnect("192.168.2.2", now: t0.addingTimeInterval(1))   // another camera: ignored
    #expect(session.cameraHost == "172.20.10.2")
    session.cameraDidConnect("172.20.10.2", now: t0.addingTimeInterval(2))
    session.cameraDidConnect("192.168.2.2", now: t0.addingTimeInterval(7))   // first one quiet for 5 s
    #expect(session.cameraHost == "192.168.2.2")
}

@MainActor @Test func setRepsAndCorrectionsAreRecordedWhenEachSetEnds() async throws {
    let session = WorkoutSession(defaultMode: .hub)
    session.hubPort = UInt16.random(in: 20_000...40_000)
    session.usePlan(WorkoutPlan(title: "Test", items: [.init(exercise: .squat, sets: 2, reps: 3, restSeconds: 30, low: 2)], weeklyGoal: 3))
    await session.start()
    session.setLoad(60, for: .squat)
    let url = URL(string: "http://127.0.0.1:\(session.hubPort)/api/sessions/phone/observations")!
    try await Task.sleep(for: .milliseconds(200))
    for index in 1...3 {  // three reps → target → rest on its own
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = observationJSON("rec-\(index)", rep: index, exercise: "squat")
        _ = try await URLSession.shared.data(for: request)
    }
    for _ in 0..<50 where !session.setFinished { try await Task.sleep(for: .milliseconds(20)) }
    #expect(session.setFinished)
    #expect(session.results == [ExerciseResult(exercise: .squat, reps: [3], low: 2, high: 3, weights: [60])])
    await session.end()  // ending from rest doesn't count the finished set twice
    #expect(session.results.first?.reps == [3])
}
