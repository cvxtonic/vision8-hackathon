import AVFoundation
import Observation
import Speech

/// Turn-based voice for the interview: the coach's question is spoken, then the microphone
/// listens until the person pauses, and the transcript becomes the answer.
/// ponytail: system speech synthesis and speech recognition, one speaker at a time (no barge-in).
/// Upgrade path: a realtime voice model like the phone coach uses.
@MainActor
@Observable
final class VoiceCoach: NSObject, AVSpeechSynthesizerDelegate {
    enum State { case idle, speaking, listening }

    private(set) var state: State = .idle
    /** Live transcript of what the person is saying. */
    private(set) var transcript = ""

    /** Pause after speech that ends the answer. */
    private let pauseSeconds = 2.0
    /** How long to wait for the first word. */
    private let waitSeconds = 12.0

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognition: SFSpeechRecognitionTask?
    @ObservationIgnored private var spoken: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var heard: CheckedContinuation<String, Never>?
    @ObservationIgnored private var timeout: Task<Void, Never>?
    /** The utterance whose end resumes `spoken`; callbacks of older ones are ignored. */
    @ObservationIgnored private var current: AVSpeechUtterance?
    /** Audio has ended and we are waiting for the recogniser's final words. */
    @ObservationIgnored private var closing = false
    @ObservationIgnored private var interruption: NSObjectProtocol?

    override init() {
        super.init()
        synthesizer.delegate = self
        // A phone call, Siri or an alarm pauses speech and kills the microphone: end the round cleanly.
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            Task { @MainActor in if began { self?.stop() } }
        }
    }

    /// False when speech recognition cannot work right now (permission withdrawn, recogniser offline).
    var available: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized && AVAudioApplication.shared.recordPermission == .granted && recognizer?.isAvailable == true
    }

    /// Asks for speech recognition and microphone access. False if either is refused or unavailable.
    static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speech, SFSpeechRecognizer(locale: Locale(identifier: "de-DE")) != nil else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    private static let voice: AVSpeechSynthesisVoice? = AVSpeechSynthesisVoice.speechVoices()
        .filter { $0.language == "de-DE" }
        .max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "de-DE")

    private func activateSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            return true
        } catch {
            return false
        }
    }

    /// Speaks the text and returns when it has finished (or was stopped).
    func speak(_ text: String) async {
        deliver()
        // A new question replaces one that is still being spoken; its late callbacks are ignored below.
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        finishSpeaking()
        guard !text.isEmpty, activateSession() else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice
        current = utterance
        state = .speaking
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            spoken = c
            synthesizer.speak(utterance)
        }
        if current === utterance, state == .speaking { state = .idle }
    }

    /// Listens until the person pauses and returns what was understood ("" if nothing).
    func listen() async -> String {
        deliver()
        transcript = ""
        guard let recognizer, recognizer.isAvailable, activateSession() else { return "" }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Audio stays on the phone where the device supports it.
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return "" } // no microphone (e.g. simulator)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            return ""
        }
        self.request = request
        closing = false
        state = .listening
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let ended = (result?.isFinal ?? false) || error != nil
            Task { @MainActor in
                guard let self, self.request === request else { return } // a newer round owns the microphone
                if let text, !text.isEmpty {
                    self.transcript = text
                    if !self.closing { self.arm(self.pauseSeconds) { $0.finishListening() } }
                }
                if ended { self.deliver() }
            }
        }
        arm(waitSeconds) { $0.finishListening() }
        return await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in heard = c }
    }

    private func arm(_ seconds: Double, then action: @escaping @MainActor (VoiceCoach) -> Void) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled, let self { action(self) }
        }
    }

    /// The person is done: stop the microphone, let the recogniser finish its last words, then deliver.
    func finishListening() {
        guard request != nil, !closing else { return }
        closing = true
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        recognition?.finish()
        state = .idle
        arm(1.5) { $0.deliver() } // the final result normally arrives sooner
    }

    /// Ends the listening round now and hands the transcript to the waiting caller. Safe at any time.
    private func deliver() {
        timeout?.cancel()
        timeout = nil
        if request != nil {
            if !closing {
                engine.stop()
                engine.inputNode.removeTap(onBus: 0)
                request?.endAudio()
            }
            recognition?.cancel()
            request = nil
            recognition = nil
        }
        closing = false
        if state == .listening { state = .idle }
        if let heard {
            self.heard = nil
            heard.resume(returning: transcript)
        }
    }

    /// Stops speaking and listening (leaving the screen, switching to typing).
    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        finishSpeaking()
        deliver()
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func finishSpeaking() {
        if let spoken {
            self.spoken = nil
            spoken.resume()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in if utterance === self.current { self.finishSpeaking() } }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in if utterance === self.current { self.finishSpeaking() } }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in if utterance === self.current { self.stop() } }
    }
}
