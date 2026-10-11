import SwiftUI
import GymAndAIKit

struct WorkoutFlowView: View {
    @Bindable var session: WorkoutSession
    let watch: WatchConnectionController
    @State private var camera = PhoneCameraController()
    @State private var audio = CoachAudioPlayer()
    @State private var speakingFeedbackID: String?
    @State private var speakingCoachingCue: CoachingCue?
    @State private var showsFormImproved = false
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
                if scenePhase == .background, session.isPhone, session.snapshot?.state == .active || session.snapshot?.state == .ready {
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
            if session.isPhone { audio.speak("Camera ready. Begin when you’re ready.") }
            else if session.snapshot?.trackingStatus == .ready { speakCoach(.begin) }
            else { speakCoach(.positioning) }
        default:
            if session.isPhone { audio.speak("Position your phone so you can see your movement.") }
            else { speakCoach(.waiting) }
        }
    }

    private func stopAudio() {
        speakingFeedbackID = nil
        speakingCoachingCue = nil
        audio.stop()
    }

    // ponytail: iPhone voice only; voiced (ElevenLabs) audio returns once the coach API is hosted (Vercel plan).
    private func speakCoach(_ cue: CoachVoiceCue) {
        stopAudio()
        guard session.audioEnabled, scenePhase == .active else { return }
        audio.speak(cue.text)
    }

    private func feedbackChanged() {
        guard session.audioEnabled, session.snapshot?.state == .active,
              session.snapshot?.trackingStatus == .ready,
              let feedback = session.store.lastFeedback,
              feedback.setId == session.snapshot?.setId,
              session.snapshot?.activeIssues.contains(feedback.issueCode) == true else { return }
        stopAudio()
        speakingFeedbackID = feedback.feedbackId
        audio.speak(feedback.text)
    }

    private var activeMascotState: MascotState {
        if showsFormImproved { return .happy }  // wins over .coaching: the praise is spoken at the same moment
        return audio.isSpeaking ? .coaching : .idle
    }

    private func coachingCueChanged() {
        guard session.audioEnabled, scenePhase == .active, !audio.isSpeaking,
              let cue = session.store.lastCoachingCue, cue.isCurrent(in: session.snapshot) else { return }
        speakingCoachingCue = cue
        audio.speak(cue.text)
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
            try? await Task.sleep(for: .seconds(2))  // length of the happy clip
            showsFormImproved = false
        }
        if session.audioEnabled { audio.speak("That is steadier now. Nice work.") }
    }

    private func trackingChanged() {
        guard session.isHub, session.audioEnabled, session.snapshot?.state == .active else { return }
        // Do not interrupt a correction with the initial tracking-ready announcement.
        if session.snapshot?.trackingStatus == .ready, speakingFeedbackID != nil, audio.isSpeaking { return }
        speakCoach(session.snapshot?.trackingStatus == .ready ? .trackingReady : .trackingLost)
    }
}
