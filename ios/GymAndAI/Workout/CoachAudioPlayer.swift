import AVFoundation
import Observation

@MainActor
@Observable
final class CoachAudioPlayer: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isSpeaking = false
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var currentUtterance: ObjectIdentifier?
    @ObservationIgnored private var audioPlayer: AVAudioPlayer?
    @ObservationIgnored private var audioCompletionTask: Task<Void, Never>?

    override init() {
        super.init()
        // Let iOS manage temporary ducking and interruptions for each spoken cue.
        synthesizer.usesApplicationAudioSession = false
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        currentUtterance = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }

    @discardableResult
    func play(_ data: Data) -> Bool {
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
        currentUtterance = nil
        isSpeaking = false
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func finishAudioPlayback() {
        audioCompletionTask = nil
        audioPlayer = nil
        isSpeaking = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        updateSpeech(utterance, speaking: true)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        updateSpeech(utterance, speaking: false)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        updateSpeech(utterance, speaking: false)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        updateSpeech(utterance, speaking: false)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        updateSpeech(utterance, speaking: true)
    }

    private nonisolated func updateSpeech(_ utterance: AVSpeechUtterance, speaking: Bool) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, currentUtterance == identifier else { return }
            isSpeaking = speaking
        }
    }
}
