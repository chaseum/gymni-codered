import Testing
@testable import GymAndAIKit

@Test func trackingCoachWaitsForContinuousReadinessAndIgnoresBriefLoss() {
    var coach = TrackingCoach()
    #expect(coach.update(.ready, at: 0) == nil)
    #expect(coach.update(.ready, at: 1.9) == nil)
    #expect(coach.isReady == nil)
    #expect(coach.update(.lost, at: 2) == nil)
    #expect(coach.update(.ready, at: 2.5) == nil)
    #expect(coach.update(.ready, at: 4.5) == .trackingReady)
    coach.didSpeak(.trackingReady, at: 4.5)
    #expect(coach.update(.lost, at: 20) == nil)
    #expect(coach.update(.lost, at: 22.9) == nil)
    #expect(coach.isReady == true)
    #expect(coach.update(.ready, at: 23) == nil)
    #expect(coach.update(.ready, at: 25) == nil)
    #expect(coach.isReady == true)
}

@Test func trackingCoachCooldownSuppressesUnannouncedLossAndRedundantRecovery() {
    var coach = TrackingCoach()
    _ = coach.update(.ready, at: 0)
    #expect(coach.update(.ready, at: 2) == .trackingReady)
    coach.didSpeak(.trackingReady, at: 2)
    _ = coach.update(.lost, at: 3)
    #expect(coach.update(.lost, at: 6) == nil)
    #expect(coach.isReady == false)
    _ = coach.update(.ready, at: 7)
    #expect(coach.update(.ready, at: 9) == nil)
    #expect(coach.update(.ready, at: 14) == nil)
}

@Test func trackingCoachAnnouncesSustainedLossAndRecoveryWithTwelveSecondSpacing() {
    var coach = TrackingCoach()
    _ = coach.update(.ready, at: 0)
    _ = coach.update(.ready, at: 2)
    coach.didSpeak(.trackingReady, at: 2)
    _ = coach.update(.lost, at: 3)
    #expect(coach.update(.lost, at: 13.9) == nil)
    #expect(coach.update(.lost, at: 14) == .trackingLost)
    coach.didSpeak(.trackingLost, at: 14)
    _ = coach.update(.ready, at: 15)
    #expect(coach.update(.ready, at: 17) == nil)
    #expect(coach.isReady == true)
    #expect(coach.update(.ready, at: 26) == .trackingReady)
    coach.didSpeak(.trackingReady, at: 26)
    #expect(coach.update(.ready, at: 40) == nil)
}

@Test func trackingCoachDefersUntilAudioActuallyPlaysAndDropsStaleCandidates() {
    var coach = TrackingCoach()
    _ = coach.update(.ready, at: 0)
    #expect(coach.update(.ready, at: 2) == .trackingReady)
    // Another clip is still playing: a request alone must not consume the cue or cooldown.
    #expect(coach.update(.ready, at: 4) == .trackingReady)
    _ = coach.update(.lost, at: 5)
    #expect(coach.update(.lost, at: 8) == nil)
    #expect(coach.isReady == false)
    _ = coach.update(.ready, at: 10)
    #expect(coach.update(.ready, at: 12) == .trackingReady)
    coach.didSpeak(.trackingReady, at: 12)
    #expect(coach.update(.ready, at: 13) == nil)
}

@Test func trackingCoachInitialMissingCameraNeverSaysInterrupted() {
    var coach = TrackingCoach()
    #expect(coach.update(nil, at: 0) == nil)
    #expect(coach.update(.lost, at: 3) == nil)
    #expect(coach.isReady == false)
    #expect(coach.update(.lost, at: 100) == nil)
}
