import SwiftUI
import GymAndAIKit

struct WorkoutFlowView: View {
    @Bindable var session: WorkoutSession
    @State private var audio = CoachAudioPlayer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if session.isPositioning { PositioningView(session: session) }
                else {
                    switch session.snapshot?.state {
                    case .paused: RestViewScreen(session: session, mascotState: audio.isSpeaking ? .coaching : .rest)
                    case .complete: RecapView(session: session, mascotState: audio.isSpeaking ? .coaching : .celebrate)
                    default:
                        if showsCamera { CameraWorkoutView(session: session, toggleAudio: toggleAudio) }
                        else { ActiveWorkoutView(session: session, mascotState: audio.isSpeaking ? .coaching : .idle) }
                    }
                }
            }
            .background(GymTheme.background)
            .foregroundStyle(GymTheme.text)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("Gym&AI").font(.headline) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(session.audioEnabled ? "Mute coach" : "Unmute coach", systemImage: session.audioEnabled ? "speaker.wave.2" : "speaker.slash", action: toggleAudio)
                        .labelStyle(.iconOnly)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(showsCamera ? .hidden : .visible, for: .navigationBar)
            .alert("Action not confirmed", isPresented: errorBinding) {
                Button("OK", action: session.clearError)
            } message: { Text(session.errorMessage ?? "Check your connection.") }
        }
        .statusBarHidden(showsCamera)
        .background(WorkoutOrientationView(landscape: showsCamera).frame(width: 0, height: 0))
        .interactiveDismissDisabled()
        .onChange(of: session.snapshot?.state, initial: true, stateChanged)
        .onChange(of: session.store.lastFeedback?.feedbackId, feedbackChanged)
        .onChange(of: session.snapshot?.activeIssues, issuesChanged)
        .onChange(of: session.snapshot?.trackingStatus, trackingChanged)
        .onDisappear(perform: audio.stop)
        .onChange(of: scenePhase) {
            if scenePhase != .active { audio.stop() }
        }
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
            if session.snapshot?.trackingStatus == .ready { audio.speak("Let’s begin. I’ll count your reps.") }
            else { audio.speak("Step into view so I can follow your movement.") }
        default: audio.speak(session.isDemo ? "Demo workout. Step into view." : "Waiting for camera tracking.")
        }
    }

    private func feedbackChanged() {
        guard session.audioEnabled, session.snapshot?.state == .active,
              let text = session.store.lastFeedback?.text else { return }
        audio.speak(text)
    }

    private func issuesChanged(_ previous: [String]?, _ current: [String]?) {
        guard session.isDemo, session.audioEnabled, session.snapshot?.state == .active,
              previous?.isEmpty == false, current?.isEmpty == true else { return }
        audio.speak("That is steadier now. Nice work.")
    }

    private func trackingChanged() {
        guard !session.isDemo, session.audioEnabled, session.snapshot?.state == .active else { return }
        audio.speak(session.snapshot?.trackingStatus == .ready ? "Tracking ready. I’m following your reps." : "Tracking interrupted. Adjust your position.")
    }
}
