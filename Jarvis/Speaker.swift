import AVFoundation

/// Sentence-by-sentence TTS. AVSpeechSynthesizer.write() renders PCM that we play through our own engine,
/// so the orb can run an FFT on the real voice.
@MainActor final class Speaker {
    var onIdle: (() -> Void)?
    var onStart: (() -> Void)?
    let levels = Levels()

    private let synth = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var connectedFormat: AVAudioFormat?
    private var queue: [String] = []
    private var rendering = false
    private var pendingBuffers = 0
    private var generation = 0   // bumps on stop() so late callbacks are ignored

    /// Streaming state for the current answer: only the part before the first blank line is spoken.
    private var spokenBuffer = ""
    private var spokenDone = false
    private var streamed = false

    var isSpeaking: Bool { rendering || pendingBuffers > 0 || !queue.isEmpty }

    init() {
        engine.attach(player)
        let spectrum = Spectrum(), levels = levels
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            if let ch = buffer.floatChannelData?[0] { levels.set(spectrum.analyze(ch, count: Int(buffer.frameLength))) }
        }
    }

    // MARK: streaming from the agent

    func beginAnswer() { spokenBuffer = ""; spokenDone = false; streamed = false }

    /// Feed partial_text deltas; complete sentences are queued as they arrive.
    func feed(_ delta: String) {
        guard !spokenDone else { return }
        streamed = true
        spokenBuffer += delta
        if let blank = spokenBuffer.range(of: "\n\n") {
            enqueue(String(spokenBuffer[..<blank.lowerBound]))
            spokenBuffer = ""; spokenDone = true
            return
        }
        while let end = spokenBuffer.firstMatch(of: /[.!?…](\s|$)/)?.range.upperBound, end < spokenBuffer.endIndex {
            enqueue(String(spokenBuffer[..<end]))
            spokenBuffer.removeSubrange(..<end)
        }
    }

    /// Answer finished: speak what's left (or the whole text if nothing streamed).
    func finishAnswer(fullText: String) {
        if !spokenDone {
            enqueue(streamed ? spokenBuffer : Self.spokenPart(of: fullText))
        }
        spokenBuffer = ""; spokenDone = true
        if !isSpeaking { onIdle?() }
    }

    func say(_ text: String) { enqueue(text) }

    func stop() {
        generation += 1
        queue.removeAll()
        synth.stopSpeaking(at: .immediate)
        player.stop()
        rendering = false; pendingBuffers = 0
        spokenDone = true
        levels.set(.zero)
    }

    static func spokenPart(of text: String) -> String {
        String(text.components(separatedBy: "\n\n").first ?? text)
    }

    // MARK: rendering

    private func enqueue(_ raw: String) {
        let text = Self.plain(raw)
        guard !text.isEmpty else { return }
        queue.append(text)
        renderNext()
    }

    private func renderNext() {
        guard !rendering, !queue.isEmpty else { return }
        rendering = true
        let utterance = AVSpeechUtterance(string: queue.removeFirst())
        utterance.voice = Self.voice()
        utterance.rate = Float(Prefs.speechRate) * (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate) + AVSpeechUtteranceMinimumSpeechRate
        let gen = generation
        synth.write(utterance) { [weak self] buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            Task { @MainActor in self?.received(pcm, generation: gen) }
        }
    }

    private func received(_ pcm: AVAudioPCMBuffer, generation gen: Int) {
        guard gen == generation else { return }
        if pcm.frameLength == 0 {  // end of this utterance
            rendering = false
            renderNext()
            if !isSpeaking { onIdle?() }
            return
        }
        guard let buffer = Self.float(pcm) else { return }
        if connectedFormat != buffer.format {
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            connectedFormat = buffer.format
        }
        if !engine.isRunning { try? engine.start() }
        if !player.isPlaying { player.play(); onStart?() }
        pendingBuffers += 1
        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                self.pendingBuffers -= 1
                if !self.isSpeaking { self.levels.set(.zero); self.onIdle?() }
            }
        }
    }

    /// Some voices render Int16; the player needs Float32.
    private static func float(_ pcm: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if pcm.format.commonFormat == .pcmFormatFloat32 { return pcm }
        guard let f = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: pcm.format.sampleRate, channels: pcm.format.channelCount, interleaved: false),
              let conv = AVAudioConverter(from: pcm.format, to: f),
              let out = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: pcm.frameLength) else { return nil }
        try? conv.convert(to: out, from: pcm)
        return out
    }

    /// Chosen voice, else best Italian "Luca", else best Italian voice.
    static func voice() -> AVSpeechSynthesisVoice? {
        if let id = Prefs.voiceID, let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        let italian = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "it-IT" }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
        return italian.first { $0.name.hasPrefix("Luca") } ?? italian.first
    }

    /// Strip markdown so it isn't read aloud.
    static func plain(_ s: String) -> String {
        s.replacing(/\[\[([^\]|]+)(\|[^\]]+)?\]\]/) { String($0.1) }
            .replacing(/\[([^\]]+)\]\([^)]+\)/) { String($0.1) }
            .replacing(/[*_`#>]/, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
