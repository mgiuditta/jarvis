import AppKit
import Observation

struct ToolItem: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
}

struct RecentCommand: Identifiable, Codable {
    var id = UUID()
    let label: String
    let command: String
}

/// Orchestrates voice ↔ agent ↔ orb. Everything runs on the main actor.
@MainActor @Observable final class AppState {
    var state: OrbState = .idle
    var transcript = ""
    var answer = ""
    var tools: [ToolItem] = []
    var confirmation: (id: String, question: String)?
    var status = ""
    var expanded = false
    var recent: [RecentCommand] = (try? JSONDecoder().decode([RecentCommand].self, from: UserDefaults.standard.data(forKey: "recent") ?? Data())) ?? []

    @ObservationIgnored let audio = AudioIn()
    @ObservationIgnored let speaker = Speaker()
    @ObservationIgnored let agent = AgentClient()
    @ObservationIgnored var setOrbVisible: ((Bool) -> Void)?
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var lastAnswer = ""
    @ObservationIgnored private var listenAfterSpeech = false
    @ObservationIgnored private var collapseTask: Task<Void, Never>?

    var modelReady: Bool { audio.isReady }

    init() {
        audio.onPartial = { [weak self] in self?.transcript = $0 }
        audio.onFinal = { [weak self] in self?.heard($0) }
        audio.onStatus = { [weak self] in self?.status = $0 }
        speaker.onStart = { [weak self] in
            guard let self, self.state != .confirm, self.state != .listening else { return }
            self.state = .speaking
        }
        speaker.onIdle = { [weak self] in self?.speechEnded() }
        agent.onEvent = { [weak self] in self?.handle($0) }
        agent.start()
        Task { await audio.loadModel() }
    }

    // MARK: input

    /// Hotkey: start listening; again while listening = done talking; while speaking = barge in.
    func hotkey() {
        switch state {
        case .listening: audio.stop()
        case .speaking: speaker.stop(); listen()
        default: listen()
        }
    }

    func listen() {
        guard audio.isReady else { status = "Il modello vocale non è ancora pronto."; expand(); return }
        listenAfterSpeech = false
        transcript = ""
        state = .listening
        expand()
        audio.start()
    }

    private func heard(_ text: String) {
        state = restingState
        guard !text.isEmpty else { return }
        transcript = text
        Log.write("utente: \(text)")
        let intent = Intent.route(text)

        if let c = confirmation {
            switch intent {
            case .yes: return answerConfirmation(true)
            case .no, .cancel, .stop: return answerConfirmation(false)
            default: listenAfterSpeech = true; return say("Dimmi sì o no. \(c.question)")
            }
        }
        switch intent {
        case .stop:
            speaker.stop()
            if busy { agent.send(["type": "interrupt"]) }
        case .cancel:
            if busy { speaker.stop(); agent.send(["type": "interrupt"]); say("Annullato.") } else { say("Non c'è niente da annullare.") }
        case .repeatLast:
            say(lastAnswer.isEmpty ? "Non ho ancora detto niente." : Speaker.spokenPart(of: lastAnswer))
        case .clipboard(let ingest, let question):
            clipboard(ingest: ingest, question: question)
        case .unsupported(let message):
            say(message)
        case .agent(let command):
            ask(command, label: text)
        case .yes, .no:
            ask(text, label: text)
        }
    }

    /// Sends a prompt to the agent. `label` is what the user said (shown in "recenti").
    func ask(_ command: String, label: String? = nil) {
        speaker.stop()
        answer = ""; tools = []
        busy = true
        state = .thinking
        expand()
        speaker.beginAnswer()
        remember(RecentCommand(label: label ?? command, command: command))
        agent.send(["type": "prompt", "id": UUID().uuidString, "text": command])
    }

    func answerConfirmation(_ allow: Bool) {
        guard let c = confirmation else { return }
        confirmation = nil
        agent.send(["type": "confirm", "id": c.id, "allow": allow])
        tools.append(ToolItem(icon: allow ? "checkmark.circle" : "xmark.circle", text: allow ? "Confermato" : "Rifiutato"))
        state = restingState
    }

    // MARK: files & clipboard

    /// Drag & drop: copy into 00-Inbox and run /ingest.
    func ingest(files: [URL]) {
        let inbox = URL(fileURLWithPath: Prefs.vaultPath).appending(path: "00-Inbox")
        var copied: [String] = []
        for file in files {
            let dest = Self.unique(inbox.appending(path: file.lastPathComponent))
            do {
                try FileManager.default.copyItem(at: file, to: dest)
                copied.append("\"00-Inbox/\(dest.lastPathComponent)\"")
            } catch {
                Log.write("copia fallita \(file.path): \(error)")
                status = "Non riesco a copiare \(file.lastPathComponent)."
            }
        }
        guard !copied.isEmpty else { return }
        ask("/ingest " + copied.joined(separator: " "), label: "Ingest di \(files.map(\.lastPathComponent).joined(separator: ", "))")
    }

    private func clipboard(ingest: Bool, question: String) {
        let pb = NSPasteboard.general
        let text = pb.string(forType: .string)
        guard ingest else {
            guard let text, !text.isEmpty else { return say("Nella clipboard non c'è testo.") }
            return ask("\(question)\n\nContenuto della clipboard:\n\(text)", label: question)
        }
        let stamp = Date.now.formatted(.verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)", timeZone: .current, calendar: .current))
        let inbox = URL(fileURLWithPath: Prefs.vaultPath).appending(path: "00-Inbox")
        do {
            let file: URL
            if let text, !text.isEmpty {
                file = Self.unique(inbox.appending(path: "clipboard-\(stamp).md"))
                try text.write(to: file, atomically: true, encoding: .utf8)
            } else if let image = NSImage(pasteboard: pb), let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                file = Self.unique(inbox.appending(path: "clipboard-\(stamp).png"))
                try png.write(to: file)
            } else {
                return say("La clipboard è vuota.")
            }
            ask("/ingest \"00-Inbox/\(file.lastPathComponent)\"", label: question)
        } catch {
            status = "Non riesco a salvare la clipboard: \(error.localizedDescription)"
        }
    }

    private static func unique(_ url: URL) -> URL {
        var candidate = url, n = 2
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appending(path: "\(base)-\(n)" + (ext.isEmpty ? "" : ".\(ext)"))
            n += 1
        }
        return candidate
    }

    // MARK: agent events

    private func handle(_ e: AgentEvent) {
        switch e.type {
        case "partial_text":
            guard let d = e.delta else { return }
            answer += d
            speaker.feed(d)
        case "tool_call":
            tools.append(ToolItem(icon: "wrench.and.screwdriver", text: "\(e.name ?? "tool") \(e.summary ?? "")"))
        case "file_changed":
            let path = (e.path ?? "").replacingOccurrences(of: Prefs.vaultPath + "/", with: "")
            tools.append(ToolItem(icon: "doc.badge.ellipsis", text: path))
        case "need_confirmation":
            guard let id = e.id, let q = e.question else { return }
            confirmation = (id, q)
            state = .confirm
            expand()
            speaker.stop()
            listenAfterSpeech = true
            say(q)
        case "done":
            busy = false
            lastAnswer = e.text ?? answer
            if let text = e.text, !text.isEmpty { answer = text }
            Log.write("jarvis: \(Speaker.spokenPart(of: lastAnswer))")
            speaker.finishAnswer(fullText: lastAnswer)
            if !speaker.isSpeaking { state = restingState; scheduleCollapse() }
        case "error":
            busy = false
            confirmation = nil
            status = e.message ?? "Errore sconosciuto"
            Log.write("errore: \(status)")
            state = .error
            expand()
            Task { try? await Task.sleep(for: .seconds(4)); if state == .error { state = restingState } }
        default: break
        }
    }

    // MARK: helpers

    private var restingState: OrbState { confirmation != nil ? .confirm : busy ? .thinking : .idle }

    private func say(_ text: String) {
        speaker.say(text)
    }

    private func speechEnded() {
        if listenAfterSpeech { listenAfterSpeech = false; return listen() }
        if state == .speaking || state == .idle { state = restingState }
        if !busy { scheduleCollapse() }
    }

    func expand() {
        collapseTask?.cancel()
        expanded = true
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task {
            try? await Task.sleep(for: .seconds(25))
            if !Task.isCancelled, state == .idle { expanded = false }
        }
    }

    private func remember(_ c: RecentCommand) {
        recent.removeAll { $0.command == c.command }
        recent.insert(c, at: 0)
        recent = Array(recent.prefix(5))
        UserDefaults.standard.set(try? JSONEncoder().encode(recent), forKey: "recent")
    }

    func newSession() {
        agent.send(["type": "new_session"])
        answer = ""; tools = []; transcript = ""
    }

    func restartAgent() {
        agent.stop()
        Task { try? await Task.sleep(for: .milliseconds(500)); agent.start() }
    }
}
