import AVFoundation
import TTSKit

/// Lock-protected flag readable from TTSKit's background callback.
private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _on = false
    var on: Bool { lock.withLock { _on } }
    func set() { lock.withLock { _on = true } }
}

/// Buffers scheduled on the player but not yet played. Touched from TTSKit's thread and the audio thread.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var value: Int { lock.withLock { n } }
    func add(_ d: Int) { lock.withLock { n = max(0, n + d) } }
    func reset() { lock.withLock { n = 0 } }
}

/// Sentence-by-sentence TTS through our own AVAudioEngine, so the orb can run an FFT on the real voice.
/// Neural voice: TTSKit (Qwen3-TTS 1.7B, local). Fallback while it loads, or by choice: AVSpeechSynthesizer.write().
@MainActor final class Speaker {
    var onIdle: (() -> Void)?
    var onStart: (() -> Void)?
    let levels = Levels()

    private let synth = AVSpeechSynthesizer()
    private var tts: TTSKit?
    private var cancel = CancelFlag()
    private let scheduled = Counter()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var connectedFormat: AVAudioFormat?
    private var queue: [String] = []
    private var rendering = false
    private var generation = 0   // bumps on stop() so late callbacks are ignored

    /// Streaming state for the current answer: only the part before the first blank line is spoken.
    private var spokenBuffer = ""
    private var spokenDone = false
    private var streamed = false

    var isSpeaking: Bool { rendering || scheduled.value > 0 || !queue.isEmpty }

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

    /// Loads the neural voice (first run: ~2 GB download + Neural Engine compile, a few minutes).
    func loadNeuralVoice() async {
        let base = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Jarvis/models")
        do {
            let kit = try await TTSKit(TTSKitConfig(model: .qwen3TTS_1_7b, downloadBase: base, verbose: false))
            try await kit.loadModels()
            tts = kit
            Log.write("TTSKit pronto")
        } catch {
            Log.write("TTSKit non disponibile, uso la voce di sistema: \(error)")
        }
    }

    func stop() {
        generation += 1
        cancel.set(); cancel = CancelFlag()
        queue.removeAll()
        synth.stopSpeaking(at: .immediate)
        player.stop()
        rendering = false; scheduled.reset()
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
        let text = queue.removeFirst()
        if let tts, let speaker = Self.neuralSpeaker() { return renderNeural(text, tts: tts, speaker: speaker) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice()
        utterance.rate = Float(Prefs.speechRate) * (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate) + AVSpeechUtteranceMinimumSpeechRate
        let gen = generation
        synth.write(utterance) { [weak self] buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            Task { @MainActor in self?.received(pcm, generation: gen) }
        }
    }

    /// Chunks go straight from TTSKit's callback thread to the player, in order: no main-actor hop,
    /// so "done speaking" can't be observed while audio is still on its way.
    private func renderNeural(_ text: String, tts: TTSKit, speaker: Qwen3Speaker) {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1) else { rendering = false; return }
        prepare(format)
        let gen = generation, flag = cancel, player = player, scheduled = scheduled
        let played: @Sendable () -> Void = { Task { @MainActor [weak self] in self?.bufferPlayed(generation: gen) } }
        var options = GenerationOptions()
        options.instruction = "Parla in italiano con tono calmo, asciutto e professionale."
        Task.detached {
            // ponytail: 0.6 s pre-buffer then 0.3 s chunks; generation is ~1.15x realtime on M4 Pro, raise if gaps
            var pending: [Float] = [], started = false
            func flush() {
                guard !pending.isEmpty, !flag.on,
                      let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pending.count)) else { return }
                buf.frameLength = buf.frameCapacity
                pending.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: $0.count) }
                pending = []; started = true
                scheduled.add(1)
                player.scheduleBuffer(buf) { scheduled.add(-1); played() }
            }
            do {
                _ = try await tts.generate(text: text, speaker: speaker, language: .italian, options: options) { step in
                    pending += step.audio
                    if pending.count >= (started ? 7_200 : 14_400) { flush() }
                    return !flag.on
                }
            } catch { if !flag.on { Log.write("TTSKit errore: \(error)") } }
            flush()
            await MainActor.run { [weak self] in self?.neuralFinished(generation: gen) }
        }
    }

    private func neuralFinished(generation gen: Int) {
        guard gen == generation else { return }
        rendering = false
        renderNext()
        if !isSpeaking { levels.set(.zero); onIdle?() }
    }

    private func bufferPlayed(generation gen: Int) {
        guard gen == generation, !isSpeaking else { return }
        levels.set(.zero)
        onIdle?()
    }

    private func prepare(_ format: AVAudioFormat) {
        if connectedFormat != format {
            engine.connect(player, to: engine.mainMixerNode, format: format)
            connectedFormat = format
        }
        if !engine.isRunning { try? engine.start() }
        if !player.isPlaying { player.play(); onStart?() }
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
        prepare(buffer.format)
        let scheduled = scheduled
        scheduled.add(1)
        player.scheduleBuffer(buffer) { [weak self] in
            scheduled.add(-1)
            Task { @MainActor in self?.bufferPlayed(generation: gen) }
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

    /// voiceID "" = neural Eric; "tts:<name>" = another neural voice; anything else = a system voice identifier.
    static func neuralSpeaker() -> Qwen3Speaker? {
        guard let id = Prefs.voiceID else { return .eric }
        return id.hasPrefix("tts:") ? Qwen3Speaker(rawValue: String(id.dropFirst(4))) : nil
    }

    /// System voice: chosen one, else best Italian "Luca", else best Italian voice.
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
