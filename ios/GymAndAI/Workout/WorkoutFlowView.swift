import SwiftUI
import GymAndAIKit

struct WorkoutFlowView: View {
    @Bindable var session: WorkoutSession
    let watch: WatchConnectionController
    @State private var camera = PhoneCameraController()
    @State private var audio = CoachAudioPlayer()
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
                        else { ActiveWorkoutView(session: session, camera: camera, mascotState: audio.isSpeaking ? .coaching : .idle) }
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
        .onChange(of: session.store.lastFeedback?.feedbackId, feedbackChanged)
        .onChange(of: session.snapshot?.activeIssues, issuesChanged)
        .onChange(of: session.snapshot?.trackingStatus, trackingChanged)
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
            audio.stop()
            camera.stop()
            watch.stop()
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                audio.stop()
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
        if !session.audioEnabled { audio.stop() }
    }

    private func stateChanged() {
        audio.stop()
        guard session.audioEnabled else { return }
        switch session.snapshot?.state {
        case .paused: audio.speak("Paused. Take the time you need.")
        case .complete: audio.speak("Workout ended. Here is your recap.")
        case .active:
            if session.isPhone { audio.speak("Camera ready. Begin when you’re ready.") }
            else if session.isDemo { audio.speak("The simulated set is starting.") }
            else if session.snapshot?.trackingStatus == .ready { audio.speak("Let’s begin. I’ll count your reps.") }
            else { audio.speak("Step into view so I can follow your movement.") }
        default: audio.speak(session.isDemo ? "Demo workout. Step into view." : session.isPhone ? "Position your phone so you can see your movement." : "Waiting for camera tracking.")
        }
    }

    private func feedbackChanged() {
        guard session.audioEnabled, session.snapshot?.state == .active,
              let feedback = session.store.lastFeedback,
              feedback.setId == session.snapshot?.setId,
              session.snapshot?.activeIssues.contains(feedback.issueCode) == true else { return }

        guard let cueID = feedback.cueId else {
            audio.speak(feedback.text)
            return
        }

        let store = session.store
        Task {
            do {
                let audioData = try await store.fetchCueAudio(cueID: cueID)
                guard feedbackIsStillActive(feedback) else { return }
                if !audio.play(audioData) { audio.speak(feedback.text) }
            } catch {
                guard feedbackIsStillActive(feedback) else { return }
                audio.speak(feedback.text)
            }
        }
    }

    private func feedbackIsStillActive(_ feedback: FeedbackIssued) -> Bool {
        session.audioEnabled && session.snapshot?.state == .active &&
            session.store.lastFeedback?.feedbackId == feedback.feedbackId &&
            session.snapshot?.setId == feedback.setId &&
            session.snapshot?.activeIssues.contains(feedback.issueCode) == true
    }

    private func issuesChanged(_ previous: [String]?, _ current: [String]?) {
        guard session.isDemo, session.audioEnabled, session.snapshot?.state == .active,
              previous?.isEmpty == false, current?.isEmpty == true else { return }
        audio.speak("That is steadier now. Nice work.")
    }

    private func trackingChanged() {
        guard !session.isDemo, !session.isPhone, session.audioEnabled, session.snapshot?.state == .active else { return }
        audio.speak(session.snapshot?.trackingStatus == .ready ? "Tracking ready. I’m following your reps." : "Tracking interrupted. Adjust your position.")
    }
}
