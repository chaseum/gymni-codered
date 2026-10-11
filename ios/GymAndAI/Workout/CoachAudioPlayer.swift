import AVFoundation
import Observation

@MainActor
@Observable
final class CoachAudioPlayer: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isSpeaking = false
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var currentUtterance: ObjectIdentifier?

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

    func stop() {
        currentUtterance = nil
        isSpeaking = false
        synthesizer.stopSpeaking(at: .immediate)
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
