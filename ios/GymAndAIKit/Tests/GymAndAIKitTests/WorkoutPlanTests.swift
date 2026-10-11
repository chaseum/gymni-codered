import Foundation
import Testing
@testable import GymAndAIKit

@Test func planFollowsFocusEquipmentExperienceAndTime() {
    let strength = WorkoutPlan.make(focus: .strength, answers: ["days": "4"])
    #expect(strength.items.map(\.exercise) == [.squat, .deadlift, .curl])
    #expect(strength.items[0].sets == 4 && strength.items[0].reps == 5)
    #expect(strength.weeklyGoal == 4)
    #expect(strength.steps.count == 10)
    #expect(strength.steps[4] == WorkoutPlan.Step(exercise: .deadlift, set: 1, sets: 3, reps: 5, restSeconds: 150))

    let bodyweight = WorkoutPlan.make(focus: .muscle, answers: ["equipment": "bodyweight"])
    #expect(bodyweight.items.map(\.exercise) == [.squat])

    let beginner = WorkoutPlan.make(focus: .fitness, answers: ["experience": "new", "duration": "20"])
    #expect(beginner.items.map(\.sets) == [2, 2])  // one set fewer, never below two; two exercises in 20 minutes
    #expect(beginner.weeklyGoal == 3)  // unanswered schedule defaults to three days
    #expect(beginner.minutes > 5)
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
