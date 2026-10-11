import AVFoundation
import Observation

@MainActor
@Observable
final class CoachAudioPlayer {
    private(set) var isSpeaking = false
    private(set) var lastPlayedCue: String?
    @ObservationIgnored private var audioPlayer: AVAudioPlayer?
    @ObservationIgnored private var audioCompletionTask: Task<Void, Never>?

    @discardableResult
    func play(_ data: Data, cue: String) -> Bool {
        stop()
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
            try audioSession.setActive(true)
            let player = try AVAudioPlayer(data: data)
            player.prepareToPlay()
            guard player.play() else {
                try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                return false
            }

            audioPlayer = player
            isSpeaking = true
            lastPlayedCue = cue
            audioCompletionTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(player.duration, 0.1) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finishAudioPlayback()
            }
            return true
        } catch {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return false
        }
    }

    func stop() {
        audioCompletionTask?.cancel()
        audioCompletionTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isSpeaking = false
    }

    private func finishAudioPlayback() {
        audioCompletionTask = nil
        audioPlayer = nil
        isSpeaking = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

}
