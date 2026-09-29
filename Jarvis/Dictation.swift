import AVFoundation
import Speech

/// Jarvis's own dictation, for who doesn't use Wispr Flow: Apple speech recognition, Italian, on the Mac when supported.
/// macOS 26+: SpeechAnalyzer's dictation model (on-device, better punctuation); SFSpeechRecognizer on 15 or if Italian isn't there.
@MainActor final class Dictation {
    private var generation = 0  // results of a stopped task (late partials, the cancel error) are dropped
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "it-IT"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var analysis: Task<Void, Never>?
    private var endAnalysis: (() -> Void)?

    static var authorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized && SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// Shows the two system prompts (microphone, speech recognition) the first time. True if both are granted.
    static func requestPermissions() async -> Bool {
        guard await AVCaptureDevice.requestAccess(for: .audio) else { return false }
        return await speechAuthorization() == .authorized
    }

    nonisolated private static func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
    }

    /// `onText` gets the whole utterance so far, on every partial result.
    /// No-op while already listening: the running session keeps its own `onText`.
    func start(onText: @escaping (String) -> Void) {
        guard task == nil, analysis == nil else { return }
        guard Self.authorized else { return Log.write("dettatura: permessi mancanti") }
        generation += 1
        let gen = generation
        if #available(macOS 26, *) {
            analysis = Task {
                guard await !analyze(gen: gen, onText: onText), generation == gen else { return }
                analysis = nil
                startRecognizer(gen: gen, onText: onText)  // no Italian model: the old recognizer
            }
        } else {
            startRecognizer(gen: gen, onText: onText)
        }
    }

    private func startRecognizer(gen: Int, onText: @escaping (String) -> Void) {
        guard let recognizer, recognizer.isAvailable else {
            return Log.write("dettatura: riconoscimento non disponibile")
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition  // audio stays on the Mac when it can
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: Self.tap(request))
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return Log.write("dettatura: microfono \(error)")
        }
        self.request = request
        task = recognizer.recognitionTask(with: request, resultHandler: Self.results { [weak self] text, done in
            guard let self, generation == gen else { return }
            if let text, !text.isEmpty { onText(text) }
            if done { stop() }
        })
    }

    func stop() {
        guard task != nil || analysis != nil else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        endAnalysis?()
        request = nil; task = nil; analysis = nil; endAnalysis = nil
        generation += 1
    }

    /// One SpeechAnalyzer session, until stop(). False if it can't run (no Italian model, audio error): use the recognizer.
    @available(macOS 26, *)
    private func analyze(gen: Int, onText: @escaping (String) -> Void) async -> Bool {
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: "it-IT")) else { return false }
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
        do {
            if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                Log.write("dettatura: scarico il modello italiano")
                try await install.downloadAndInstall()  // once; the first dictation waits for it
            }
        } catch {
            Log.write("dettatura: modello non disponibile \(error)")
            return false
        }
        let input = engine.inputNode
        let natural = input.outputFormat(forBus: 0)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: natural),
              let converter = AVAudioConverter(from: natural, to: format) else { return false }
        guard generation == gen else { return true }  // stopped while setting up: nothing to fall back to

        let (stream, feed) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        input.installTap(onBus: 0, bufferSize: 4096, format: natural, block: Self.tap(converter, to: format, into: feed))
        endAnalysis = { feed.finish(); Task { await analyzer.cancelAndFinishNow() } }  // ends `results` below; set before the await, a stop() may come during it
        do {
            engine.prepare()
            try engine.start()
            try await analyzer.start(inputSequence: stream)
        } catch {
            guard generation == gen else { return true }  // stop() got there first and cleaned up
            engine.stop()
            input.removeTap(onBus: 0)
            endAnalysis?(); endAnalysis = nil
            Log.write("dettatura: microfono \(error)")
            return false
        }
        var final = AttributedString()
        do {
            for try await result in transcriber.results {
                guard generation == gen else { break }
                if result.isFinal { final += result.text }
                let text = String((result.isFinal ? final : final + result.text).characters)
                if !text.isEmpty { onText(text) }
            }
        } catch {
            Log.write("dettatura: \(error)")
        }
        if generation == gen { stop() }
        return true
    }

    // Built outside the main actor: both run on audio/recognition threads, a main-actor closure would trap there.
    nonisolated private static func tap(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    /// Microphone buffers → the analyzer's format. Runs on the audio thread.
    @available(macOS 26, *)
    nonisolated private static func tap(_ converter: AVAudioConverter, to format: AVAudioFormat,
                                        into feed: AsyncStream<AnalyzerInput>.Continuation) -> AVAudioNodeTapBlock {
        { buffer, _ in
            let frames = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 1
            guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
            var consumed = false
            converter.convert(to: out, error: nil) { _, status in
                if consumed { status.pointee = .noDataNow; return nil }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            if out.frameLength > 0 { feed.yield(AnalyzerInput(buffer: out)) }
        }
    }

    nonisolated private static func results(_ deliver: @escaping @MainActor @Sendable (String?, Bool) -> Void)
        -> (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let done = error != nil || result?.isFinal == true
            DispatchQueue.main.async { MainActor.assumeIsolated { deliver(text, done) } }  // FIFO: partials stay in order
        }
    }
}
