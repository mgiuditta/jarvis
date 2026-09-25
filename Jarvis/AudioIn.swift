import AVFoundation
import Accelerate
import WhisperKit

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

/// Mic → 16 kHz mono → energy VAD → WhisperKit, with partial text every ~1 s.
@MainActor final class AudioIn {
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?   // empty string = nothing heard
    var onStatus: ((String) -> Void)?
    let levels = Levels()

    private var whisper: WhisperKit?
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private var speechStarted = false
    private var silence: TimeInterval = 0
    private var peakRMS: Float = 0
    private var listening = false
    private var transcribing = false
    private var lastPartial = Date.distantPast
    private var startedAt = Date()
    // Calibration knobs: raise `speechRMS` in a noisy room.
    private let speechRMS: Float = 0.015, endSilence: TimeInterval = 0.8, noSpeechTimeout: TimeInterval = 6, maxLength: TimeInterval = 45

    var isReady: Bool { whisper != nil }

    func loadModel() async {
        let base = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Jarvis/models")
        onStatus?("Carico il modello vocale… (la prima volta scarica circa 1,6 GB)")
        do {
            whisper = try await WhisperKit(WhisperKitConfig(model: "large-v3-v20240930_turbo", downloadBase: base, verbose: false))
            onStatus?("")
            Log.write("WhisperKit pronto")
        } catch {
            onStatus?("Modello vocale non disponibile: \(error.localizedDescription)")
            Log.write("WhisperKit errore: \(error)")
        }
    }

    func start() {
        guard !listening, whisper != nil else { return }
        Log.write("ascolto: avvio (microfono \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue))")
        samples.removeAll(keepingCapacity: true)
        speechStarted = false; silence = 0; peakRMS = 0; startedAt = .now; lastPartial = .now
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              inFormat.channelCount > 0, let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            Log.write("ascolto: formato microfono non valido \(inFormat)")
            onStatus?("Microfono non disponibile: controlla il permesso in Privacy › Microfono.")
            onFinal?("")
            return
        }
        let spectrum = Spectrum(), levels = levels

        input.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { [weak self] buffer, _ in
            if let ch = buffer.floatChannelData?[0] { levels.set(spectrum.analyze(ch, count: Int(buffer.frameLength))) }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / inFormat.sampleRate) + 1
            guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
            var fed = false
            converter.convert(to: out, error: nil) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return buffer
            }
            guard let ch = out.floatChannelData?[0] else { return }
            let chunk = Array(UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
            Task { @MainActor in self?.append(chunk) }
        }
        do {
            try engine.start()
            listening = true
        } catch {
            input.removeTap(onBus: 0)
            Log.write("ascolto: engine.start fallito \(error)")
            onStatus?("Microfono non disponibile: \(error.localizedDescription)")
            onFinal?("")
        }
    }

    /// Stops listening; `transcribe: false` discards what was heard.
    func stop(transcribe: Bool = true) {
        guard listening else { return }
        listening = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        levels.set(.zero)
        let audio = samples; samples = []
        Log.write("ascolto: fine, \(String(format: "%.1f", Double(audio.count) / 16_000)) s, voce \(speechStarted ? "sì" : "no"), picco RMS \(String(format: "%.4f", peakRMS)) (soglia \(speechRMS))")
        guard transcribe, speechStarted else { if transcribe { onFinal?("") }; return }
        Task {
            while transcribing { try? await Task.sleep(for: .milliseconds(30)) } // one decode at a time
            onFinal?(await run(audio))
        }
    }

    private func append(_ chunk: [Float]) {
        guard listening, !chunk.isEmpty else { return }
        samples += chunk
        var rms: Float = 0
        vDSP_rmsqv(chunk, 1, &rms, vDSP_Length(chunk.count))
        peakRMS = max(peakRMS, rms)
        let seconds = Double(chunk.count) / 16_000
        if rms > speechRMS { speechStarted = true; silence = 0 } else if speechStarted { silence += seconds }

        let elapsed = Date.now.timeIntervalSince(startedAt)
        if (speechStarted && silence >= endSilence) || elapsed > maxLength || (!speechStarted && elapsed > noSpeechTimeout) {
            return stop()
        }
        if speechStarted, !transcribing, Date.now.timeIntervalSince(lastPartial) > 1 {
            lastPartial = .now; transcribing = true
            let audio = samples
            Task {
                let text = await run(audio); transcribing = false
                if listening, !text.isEmpty { onPartial?(text) }
            }
        }
    }

    private func run(_ audio: [Float]) async -> String {
        guard let whisper else { return "" }
        let options = DecodingOptions(task: .transcribe, language: "it", temperatureFallbackCount: 2, usePrefillPrompt: true, detectLanguage: false, skipSpecialTokens: true, withoutTimestamps: true)
        let results = (try? await whisper.transcribe(audioArray: audio, decodeOptions: options)) ?? []
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
