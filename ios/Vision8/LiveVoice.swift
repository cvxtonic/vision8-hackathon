import AVFoundation
import Observation
import UIKit

/// One finished turn of the realtime transcript.
struct TranscriptEntry: Equatable {
    /** "agent" or "caller". */
    var speaker: String
    var text: String
}

/// G.711 mu-law, the telephone codec voice-kit speaks. Pure, so it is testable on its own.
enum MuLaw {
    private static let bias = 0x84
    private static let clip = 32635

    static func encode(_ sample: Int16) -> UInt8 {
        let sign = sample < 0 ? 0x80 : 0
        let s = min(abs(Int(sample)), clip) + bias
        var exponent = 7
        var mask = 0x4000
        while s & mask == 0, exponent > 0 {
            exponent -= 1
            mask >>= 1
        }
        let mantissa = (s >> (exponent + 3)) & 0x0F
        return UInt8(~(sign | (exponent << 4) | mantissa) & 0xFF)
    }

    static func decode(_ byte: UInt8) -> Int16 {
        let u = Int(~byte)
        let exponent = (u >> 4) & 0x07
        let magnitude = ((((u & 0x0F) << 3) + bias) << exponent) - bias
        return Int16(u & 0x80 != 0 ? -magnitude : magnitude)
    }
}

/// Microphone bytes -> exact 160-byte frames (20 ms) -> socket, on a serial queue off the audio thread.
private final class Uplink: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ai.innofy.vision8.uplink")
    private let socket: URLSessionWebSocketTask
    private var pending: [UInt8] = []
    private var open = true

    init(socket: URLSessionWebSocketTask) { self.socket = socket }

    func send(_ text: String, done: @escaping @Sendable (Error?) -> Void = { _ in }) {
        queue.async {
            guard self.open else { return }
            self.socket.send(.string(text), completionHandler: done)
        }
    }

    func push(_ bytes: [UInt8]) {
        queue.async {
            guard self.open else { return }
            self.pending += bytes
            var start = 0
            while self.pending.count - start >= 160 {
                let frame = Data(self.pending[start..<start + 160]).base64EncodedString()
                self.socket.send(.string(#"{"event":"media","media":{"payload":"\#(frame)"}}"#)) { _ in }
                start += 160
            }
            self.pending.removeFirst(start) // the remainder waits for the next buffer
        }
    }

    /// Says goodbye and closes the socket. Nothing is sent afterwards.
    func close() {
        queue.async {
            guard self.open else { return }
            self.open = false
            self.pending = []
            let socket = self.socket
            socket.send(.string(#"{"event":"stop"}"#)) { _ in socket.cancel(with: .normalClosure, reason: nil) }
        }
    }
}

private struct ServerEvent: Decodable {
    struct Media: Decodable { var payload: String }
    var event: String
    var media: Media?
    var speaker: String?
    var text: String?
}

/// Realtime interview: streams the microphone to voice-kit (Twilio Media Streams wire format, mu-law 8 kHz)
/// and plays the coach's audio. The coach leads and ends the conversation; the transcript arrives turn by turn.
/// ponytail: an audio route change ends the stream and the person reconnects; restarting the engine in place
/// would be smoother.
@MainActor
@Observable
final class LiveVoice {
    enum State: Equatable { case idle, connecting, live, finished, failed(String) }

    private(set) var state: State = .idle
    private(set) var agentText = ""
    private(set) var callerText = ""
    private(set) var entries: [TranscriptEntry] = []

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var framesPlayed = 0
    @ObservationIgnored private var rewires = 0
    @ObservationIgnored private var inputHz = 0
    /** When the last piece of the coach's audio arrived; drives "Der Coach spricht". */
    @ObservationIgnored private(set) var lastAgentAudio = Date.distantPast // read by a TimelineView, not observed: it changes 50 times a second
    @ObservationIgnored private var player: AVAudioPlayerNode?
    @ObservationIgnored private var uplink: Uplink?
    @ObservationIgnored private var receiver: Task<Void, Never>?
    /** Bumped by every connect and stop; callbacks of an older session see a different value and do nothing. */
    @ObservationIgnored private var generation = 0

    private static let playback = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1)!

    init() {
        let center = NotificationCenter.default
        // A phone call, Siri or an alarm takes the microphone; leaving the app ends the stream too.
        _ = center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            Task { @MainActor in if began { self?.interrupt("Ein Anruf oder eine andere App hat das Gespräch unterbrochen.") } }
        }
        // Headphones plugged in or a Bluetooth route change stops the engine without any other signal.
        // The notification also fires while the engine starts up (voice processing switches the route), so it
        // is only a failure if the engine has really stopped and cannot be started again.
        _ = center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard let self, let engine = self.engine, let player = self.player, let uplink = self.uplink, !engine.isRunning else { return }
                self.rewires += 1
                let ok = (try? self.wire(engine, player, uplink)) ?? false
                if !ok { self.interrupt("Das Audiogerät hat gewechselt. Verbinde dich noch einmal, dann geht es weiter.") }
            }
        }
        _ = center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.interrupt("Das Gespräch wurde unterbrochen, weil du die App verlassen hast.") }
        }
    }

    /// Realtime needs only the microphone; the transcript comes from the server.
    static func authorize() async -> Bool { await AVAudioApplication.requestRecordPermission() }

    /// Transcript -> interview turns: each caller entry answers the agent text since the previous caller entry
    /// (consecutive agent entries are joined). Same rule as pairTranscript in worker/src/rules.ts.
    nonisolated static func pair(_ entries: [TranscriptEntry]) -> [Turn] {
        var turns: [Turn] = []
        var question = ""
        for entry in entries {
            let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            if entry.speaker == "agent" {
                question = question.isEmpty ? text : "\(question) \(text)"
            } else {
                turns.append(Turn(question: String(question.prefix(600)), answer: String(text.prefix(2000))))
                question = ""
            }
        }
        return Array(turns.suffix(60))
    }

    /// The turns of this session, handed over once: the transcript is emptied (captions stay).
    func takeTurns() -> [Turn] {
        defer { entries = [] }
        return Self.pair(entries)
    }

    func connect(url: URL, token: String, callSid: String) {
        stop()
        // Nobody touches the screen while talking: without this the phone locks and the talk ends.
        UIApplication.shared.isIdleTimerDisabled = true
        let generation = self.generation
        entries = []
        agentText = ""
        callerText = ""
        state = .connecting

        let socket = URLSession.shared.webSocketTask(with: url)
        let uplink = Uplink(socket: socket)
        self.uplink = uplink
        socket.resume()
        // The start message goes out before any audio: the uplink queue keeps the order.
        let start: [String: Any] = ["event": "start", "streamSid": "app", "start": ["callSid": callSid, "customParameters": ["token": token]]]
        guard let data = try? JSONSerialization.data(withJSONObject: start), let text = String(data: data, encoding: .utf8) else { return fail("Das Gespräch konnte nicht gestartet werden.") }
        uplink.send(text) { [weak self] error in
            Task { @MainActor in
                guard let self, self.generation == generation, self.state == .connecting, error == nil else { return }
                self.state = .live
            }
        }

        do {
            let session = AVAudioSession.sharedInstance()
            // .videoChat keeps echo cancellation and plays through the loudspeaker; .voiceChat sent the coach's
            // voice to the quiet earpiece on a real iPhone (first device test: audio arrived, nothing was heard).
            try session.setCategory(.playAndRecord, mode: .videoChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            if session.currentRoute.outputs.contains(where: { $0.portType == .builtInReceiver }) {
                try session.overrideOutputAudioPort(.speaker)
            }
            let engine = AVAudioEngine()
            self.engine = engine
            // Echo cancellation: the coach's voice from the loudspeaker must not go back to the coach.
            // Must happen before formats are read and before the engine starts.
            try engine.inputNode.setVoiceProcessingEnabled(true)
            let player = AVAudioPlayerNode()
            self.player = player
            engine.attach(player)
            guard try wire(engine, player, uplink) else { return fail("Kein Mikrofon gefunden.") }
            startDiagnostics(uplink: uplink, generation: generation)
        } catch {
            return fail("Mikrofon oder Lautsprecher lassen sich gerade nicht starten.")
        }

        receiver = Task { [weak self] in
            while true {
                let message: URLSessionWebSocketTask.Message
                do {
                    message = try await socket.receive()
                } catch {
                    self?.closed(socket, generation: generation)
                    return
                }
                guard let self, self.generation == generation else { return }
                if case .string(let text) = message { self.handle(text) }
            }
        }
    }

    /// Ends the stream now. Safe to call at any time and more than once; nothing fires afterwards.
    func stop() {
        UIApplication.shared.isIdleTimerDisabled = false
        generation += 1
        receiver?.cancel()
        receiver = nil
        let running = engine != nil || uplink != nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        player?.stop()
        engine = nil
        player = nil
        uplink?.close()
        uplink = nil
        if running { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    /// Stops a running stream and reports why, so the screen can offer to continue.
    func interrupt(_ message: String) {
        guard state == .connecting || state == .live else { return }
        fail(message)
    }

    private func fail(_ message: String) {
        stop()
        state = .failed(message)
    }

    private func closed(_ socket: URLSessionWebSocketTask, generation: Int) {
        guard generation == self.generation else { return }
        switch socket.closeCode {
        case .normalClosure:
            stop()
            state = .finished
        case .policyViolation:
            fail("Die Sitzung ist abgelaufen. Verbinde dich noch einmal.")
        default:
            fail("Die Verbindung zum Coach ist abgebrochen.")
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8), let event = try? JSONDecoder().decode(ServerEvent.self, from: data) else { return }
        switch event.event {
        case "media":
            if let payload = event.media?.payload { play(payload) }
        case "clear":
            // Barge-in: drop what is queued for playback.
            player?.stop()
            player?.play()
        case "transcript":
            guard let speaker = event.speaker, speaker == "agent" || speaker == "caller",
                  let text = event.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            entries.append(TranscriptEntry(speaker: speaker, text: text))
            if speaker == "agent" { agentText = text } else { callerText = text }
        default:
            break
        }
    }

    /// Connects microphone tap and player with the formats the hardware has right now and starts the engine.
    /// Used at the start and again after an audio configuration change, when those formats may have changed.
    /// Returns false when there is no usable microphone.
    private func wire(_ engine: AVAudioEngine, _ player: AVAudioPlayerNode, _ uplink: Uplink) throws -> Bool {
        engine.inputNode.removeTap(onBus: 0)
        engine.disconnectNodeOutput(player)
        let input = engine.inputNode.outputFormat(forBus: 0)
        guard input.sampleRate > 0, input.channelCount > 0, let tap = Self.capture(from: input, into: uplink) else { return false }
        engine.connect(player, to: engine.mainMixerNode, format: Self.playback)
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: input, block: tap)
        engine.prepare()
        try engine.start()
        player.play()
        inputHz = Int(input.sampleRate)
        return true
    }

    /// Every few seconds the app tells the server what its audio is doing (route, volume, engine, frames).
    /// The server only logs it. Without this a silent phone cannot be diagnosed from afar.
    private func startDiagnostics(uplink: Uplink, generation: Int) {
        Task { [weak self] in
            while let self, self.generation == generation {
                let session = AVAudioSession.sharedInstance()
                let route = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: "+")
                let mixer = self.engine?.mainMixerNode.outputFormat(forBus: 0).sampleRate ?? 0
                let line = "diag route=\(route) vol=\(session.outputVolume) engine=\(self.engine?.isRunning == true) player=\(self.player?.isPlaying == true) mixerHz=\(Int(mixer)) framesIn=\(self.framesPlayed) inputHz=\(self.inputHz) rewires=\(self.rewires)"
                uplink.send(#"{"event":"mark","mark":{"name":"\#(line)"}}"#)
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func play(_ payload: String) {
        framesPlayed += 1
        lastAgentAudio = Date()
        guard let player, let data = Data(base64Encoded: payload), !data.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: Self.playback, frameCapacity: AVAudioFrameCount(data.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        for (i, byte) in data.enumerated() { channel[i] = Float(MuLaw.decode(byte)) / 32768 }
        buffer.frameLength = AVAudioFrameCount(data.count)
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    /// The tap block runs on an audio thread: convert to 8 kHz mono Int16, encode, hand off. Never touches self.
    nonisolated private static func capture(from input: AVAudioFormat, into uplink: Uplink) -> AVAudioNodeTapBlock? {
        guard let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 8000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: input, to: output) else { return nil }
        return { buffer, _ in
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 8000 / input.sampleRate) + 32
            guard let out = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return }
            var fed = false
            var error: NSError?
            let status = converter.convert(to: out, error: &error) { _, inputStatus in
                if fed {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                fed = true
                inputStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, let samples = out.int16ChannelData?[0] else { return }
            uplink.push((0..<Int(out.frameLength)).map { MuLaw.encode(samples[$0]) })
        }
    }
}
