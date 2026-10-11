import SwiftUI
import GymAndAIKit

struct WorkoutFlowView: View {
    @Bindable var session: WorkoutSession
    let watch: WatchConnectionController
    @State private var camera = PhoneCameraController()
    @State private var audio = CoachAudioPlayer()
    @State private var audioRequest: Task<Void, Never>?
    @State private var showsFormImproved = false
    @State private var speakingFeedbackID: String?
    @State private var speakingCoachingCue: CoachingCue?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if session.isPositioning { PositioningView(session: session, camera: camera, watch: watch) }
                else {
                    switch session.snapshot?.state {
                    case .paused: RestViewScreen(session: session, mascotState: audio.isSpeaking ? .coaching : .rest)
                    case .complete: RecapView(session: session, mascotState: audio.isSpeaking ? .coaching : .celebrate)
                    default:
                        if showsCamera { CameraWorkoutView(session: session, camera: camera, toggleAudio: toggleAudio) }
                        else { ActiveWorkoutView(session: session, camera: camera, mascotState: activeMascotState) }
                    }
                }
            }
            .background(GymTheme.background)
            .foregroundStyle(GymTheme.text)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("Gym&I").font(.headline) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(session.audioEnabled ? "Mute coach" : "Unmute coach", systemImage: session.audioEnabled ? "speaker.wave.2" : "speaker.slash", action: toggleAudio)
                        .labelStyle(.iconOnly)
                        .accessibilityValue(audio.lastPlayedCue.map { "\(audio.isSpeaking ? "ElevenLabs voice playing" : "Last spoken cue"): \($0)" } ?? "Voice idle")
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(showsCamera ? .hidden : .visible, for: .navigationBar)
            .alert("Action not confirmed", isPresented: errorBinding) {
                Button("OK", action: session.clearError)
            } message: { Text(session.errorMessage ?? "Check your connection.") }
        }
        .statusBarHidden(showsCamera)
        .persistentSystemOverlays(showsCamera ? .hidden : .automatic)
        .background(WorkoutOrientationView(landscape: showsCamera).frame(width: 0, height: 0))
        .interactiveDismissDisabled()
        .onChange(of: session.snapshot?.state, initial: true, stateChanged)
        .onChange(of: session.store.lastFeedback?.utteranceId ?? session.store.lastFeedback?.feedbackId, feedbackChanged)
        .onChange(of: session.store.lastCoachingCue?.cueId, coachingCueChanged)
        .onChange(of: session.snapshot?.repCount) {
            if let cue = speakingCoachingCue, !cue.isCurrent(in: session.snapshot) { stopAudio() }
        }
        .onChange(of: session.snapshot?.activeIssues, issuesChanged)
        .onChange(of: session.snapshot?.trackingStatus, trackingChanged)
        .onChange(of: session.audioEnabled) {
            if !session.audioEnabled { stopAudio() }
        }
        .sensoryFeedback(.selection, trigger: session.display)
        .sensoryFeedback(.impact(weight: .light), trigger: session.snapshot?.state)
        .task(id: cameraShouldRun) {
            if cameraShouldRun { await camera.start() }
            else { camera.stop() }
        }
        .task(id: session.snapshot?.state) { await watch.synchronize(session) }
        .task(id: WorkoutLiveActivity.state(for: session)) {
            await WorkoutLiveActivity.update(WorkoutLiveActivity.state(for: session), exercise: session.exercise.rawValue.capitalized)
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            let finalState = WorkoutLiveActivity.state(for: session)
            Task { await WorkoutLiveActivity.end(finalState) }
            stopAudio()
            camera.stop()
            watch.stop()
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                stopAudio()
                if scenePhase == .background, session.isPhone || session.isHub, session.snapshot?.state == .active || session.snapshot?.state == .ready {
                    Task { await session.pause() }
                }
            }
        }
    }

    private var cameraShouldRun: Bool {
        session.isPhone && scenePhase != .background && (session.snapshot?.state == .ready || session.snapshot?.state == .active)
    }

    private var showsCamera: Bool {
        !session.isPositioning && session.display == .camera && session.snapshot?.state != .paused && session.snapshot?.state != .complete
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.clearError() } })
    }

    private func toggleAudio() {
        session.audioEnabled.toggle()
        if !session.audioEnabled { stopAudio() }
    }

    private func stateChanged() {
        stopAudio()
        guard session.audioEnabled else { return }
        switch session.snapshot?.state {
        case .paused: speakCoach(.paused)
        case .complete: speakCoach(.ended)
        case .active:
            if session.snapshot?.trackingStatus == .ready { speakCoach(.begin) }
            else { speakCoach(.positioning) }
        default:
            speakCoach(.waiting)
        }
    }

    private func stopAudio() {
        audioRequest?.cancel()
        audioRequest = nil
        speakingFeedbackID = nil
        speakingCoachingCue = nil
        audio.stop()
    }

    private func speakCoach(_ cue: CoachVoiceCue) {
        stopAudio()
        guard session.audioEnabled, scenePhase == .active else { return }
        guard session.isHub else { return }
        audioRequest = Task {
            defer { if !Task.isCancelled { audioRequest = nil } }
            do {
                let data = try await session.fetchHostedAudio(.prompt(cue))
                guard !Task.isCancelled, session.audioEnabled, scenePhase == .active else { return }
                if !audio.play(data, cue: cue.text) { session.reportVoicePlaybackFailure() }
            } catch {
                guard !Task.isCancelled, session.audioEnabled, scenePhase == .active else { return }
            }
        }
    }

    private func feedbackChanged() {
        guard session.audioEnabled, session.snapshot?.state == .active,
              session.snapshot?.trackingStatus == .ready,
              let feedback = session.store.lastFeedback,
              feedback.setId == session.snapshot?.setId,
              session.snapshot?.activeIssues.contains(feedback.issueCode) == true else { return }

        stopAudio()
        speakingFeedbackID = feedback.feedbackId

        guard session.isHub else { return }

        let requestedAt = ContinuousClock.now
        audioRequest = Task {
            defer { if !Task.isCancelled { audioRequest = nil } }
            do {
                let audioData = try await session.fetchHostedAudio(.form(feedback))
                guard feedbackIsStillActive(feedback), requestedAt.duration(to: .now) < .seconds(6) else { return }
                if !audio.play(audioData, cue: feedback.text) { session.reportVoicePlaybackFailure() }
            } catch {
                guard feedbackIsStillActive(feedback) else { return }
            }
        }
    }

    private func feedbackIsStillActive(_ feedback: FeedbackIssued) -> Bool {
        !Task.isCancelled && scenePhase == .active && session.audioEnabled && session.snapshot?.state == .active &&
            session.snapshot?.trackingStatus == .ready &&
            session.store.lastFeedback?.feedbackId == feedback.feedbackId &&
            session.store.lastFeedback?.utteranceId == feedback.utteranceId &&
            session.snapshot?.setId == feedback.setId &&
            session.snapshot?.activeIssues.contains(feedback.issueCode) == true
    }

    private var activeMascotState: MascotState {
        if showsFormImproved { return .happy }
        return audio.isSpeaking ? .coaching : .idle
    }

    private func coachingCueChanged() {
        guard session.audioEnabled, scenePhase == .active, !audio.isSpeaking,
              let cue = session.store.lastCoachingCue, cue.isCurrent(in: session.snapshot) else { return }
        stopAudio()
        speakingCoachingCue = cue
        let requestedAt = ContinuousClock.now
        audioRequest = Task {
            defer { if !Task.isCancelled { audioRequest = nil } }
            do {
                let data = try await session.fetchHostedAudio(.coaching(cue, target: session.targetReps))
                guard coachingCueIsCurrent(cue), requestedAt.duration(to: .now) < .seconds(6) else { return }
                if !audio.play(data, cue: cue.text) { session.reportVoicePlaybackFailure() }
            } catch {
                guard coachingCueIsCurrent(cue) else { return }
            }
        }
    }

    private func coachingCueIsCurrent(_ cue: CoachingCue) -> Bool {
        !Task.isCancelled && session.audioEnabled && scenePhase == .active &&
            session.store.lastCoachingCue?.cueId == cue.cueId && cue.isCurrent(in: session.snapshot)
    }

    private func issuesChanged(_ previous: [String]?, _ current: [String]?) {
        if let feedback = session.store.lastFeedback, speakingFeedbackID == feedback.feedbackId,
           current?.contains(feedback.issueCode) != true {
            stopAudio()
        }
        guard session.isHub, session.snapshot?.state == .active,
              previous?.isEmpty == false, current?.isEmpty == true else { return }
        showsFormImproved = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showsFormImproved = false
        }
    }

    private func trackingChanged() {
        guard session.isHub, session.audioEnabled, session.snapshot?.state == .active else { return }
        // Do not interrupt a correction with the initial tracking-ready announcement.
        if session.snapshot?.trackingStatus == .ready, speakingFeedbackID != nil || speakingCoachingCue != nil,
           audio.isSpeaking || audioRequest != nil { return }
        speakCoach(session.snapshot?.trackingStatus == .ready ? .trackingReady : .trackingLost)
    }
}
