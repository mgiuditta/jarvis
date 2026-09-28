import AVFoundation
import Accelerate

/// Audio levels shared with the orb renderer: x = overall, y = low, z = mid, w = high band. Written from audio threads.
final class Levels: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = SIMD4<Float>(repeating: 0)
    var value: SIMD4<Float> { lock.withLock { _value } }
    func set(_ v: SIMD4<Float>) { lock.withLock { _value = v } }
}

/// Real FFT (vDSP) folded into 3 bands. One instance per audio thread.
final class Spectrum {
    private let n = 1024
    private let log2n = vDSP_Length(10)
    private let setup: FFTSetup
    private var window: [Float]
    private var real: [Float], imag: [Float], mags: [Float]

    init() {
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        real = .init(repeating: 0, count: n / 2); imag = real; mags = real
    }
    deinit { vDSP_destroy_fftsetup(setup) }

    func analyze(_ samples: UnsafePointer<Float>, count: Int) -> SIMD4<Float> {
        guard count > 0 else { return .zero }
        var frame = [Float](repeating: 0, count: n)
        vDSP_vmul(samples, 1, window, 1, &frame, 1, vDSP_Length(min(count, n)))
        real.withUnsafeMutableBufferPointer { r in
            imag.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                frame.withUnsafeBytes { raw in
                    vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(n / 2))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(n / 2))
            }
        }
        // ponytail: fixed bin ranges assume ~16–48 kHz input; fine for voice
        func band(_ a: Int, _ b: Int) -> Float {
            var mean: Float = 0
            vDSP_meanv(Array(mags[a..<b]), 1, &mean, vDSP_Length(b - a))
            return min(1, sqrt(mean) / 40)
        }
        let low = band(2, 16), mid = band(16, 80), high = band(80, 256)
        return SIMD4(min(1, (low + mid + high) / 1.5), low, mid, high)
    }
}

/// Buffers scheduled on the player but not yet played. Touched from the main actor and the audio thread.
/// Tagged with the speaker generation: completions of buffers dropped by stop() can't eat into the next answer's count.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0, gen = 0
    var value: Int { lock.withLock { n } }
    func add(_ d: Int, generation: Int) { lock.withLock { if generation == gen { n = max(0, n + d) } } }
    func reset(generation: Int) { lock.withLock { n = 0; gen = generation } }
}

/// Sentence-by-sentence TTS through our own AVAudioEngine, so the orb can run an FFT on the real voice.
/// System voice via AVSpeechSynthesizer.write(); nothing is spoken while muted.
@MainActor final class Speaker {
    var onIdle: (() -> Void)?
    var onStart: (() -> Void)?
    let levels = Levels()

    private let synth = AVSpeechSynthesizer()
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
        nonisolated(unsafe) let spectrum = Spectrum()  // only ever touched on the tap thread
        let levels = levels
        // @Sendable: without it the closure is inferred @MainActor and traps on the audio thread in Swift 6 mode.
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { @Sendable buffer, _ in
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
        rendering = false; scheduled.reset(generation: generation)
        spokenDone = true
        levels.set(.zero)
    }

    static func spokenPart(of text: String) -> String {
        String(text.components(separatedBy: "\n\n").first ?? text)
    }

    // MARK: rendering

    private func enqueue(_ raw: String) {
        let text = Self.plain(raw)
        guard !text.isEmpty, !Prefs.muted else { return }
        queue.append(text)
        renderNext()
    }

    private func renderNext() {
        guard !rendering, !queue.isEmpty else { return }
        rendering = true
        let text = queue.removeFirst()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice()
        utterance.rate = Float(Prefs.speechRate) * (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate) + AVSpeechUtteranceMinimumSpeechRate
        let gen = generation
        synth.write(utterance) { @Sendable [weak self] buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            nonisolated(unsafe) let pcm2 = pcm  // handed over, the synth doesn't reuse it
            // main queue, not a Task per chunk: FIFO is guaranteed, so chunks can't be played out of order
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.received(pcm2, generation: gen) } }
        }
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
        scheduled.add(1, generation: gen)
        player.scheduleBuffer(buffer) { @Sendable [weak self] in
            scheduled.add(-1, generation: gen)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.bufferPlayed(generation: gen) } }
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

    /// System voice: chosen one, else best Italian "Luca", else best Italian voice.
    static func voice() -> AVSpeechSynthesisVoice? {
        if let id = Prefs.voiceID, let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        let italian = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "it-IT" }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
        return italian.first { $0.name.hasPrefix("Luca") } ?? italian.first
    }

    /// Strip markdown so it isn't read aloud.
    static func plain(_ s: String) -> String {
        s.replacing(/\[\[(?:[^\]|]+\|)?([^\]]+)\]\]/) { String($0.1) }  // [[target|alias]] reads the alias
            .replacing(/\[([^\]]+)\]\([^)]+\)/) { String($0.1) }
            .replacing(/[*_`#>]/, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
