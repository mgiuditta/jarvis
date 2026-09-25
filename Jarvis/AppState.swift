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

/// Orchestrates dictated input (Wispr) ↔ agent ↔ voice/orb. Everything runs on the main actor.
@MainActor @Observable final class AppState {
    var state: OrbState = .idle
    var transcript = ""     // last message sent
    var draft = ""          // what Wispr is typing into the input field
    var inputActive = false
    var focusRequest = 0    // bumped to (re)focus the input field
    var answer = ""
    var tools: [ToolItem] = []
    var confirmation: (id: String, question: String)?
    var status = ""
    var expanded = false
    var orbShown = false
    var recent: [RecentCommand] = (try? JSONDecoder().decode([RecentCommand].self, from: UserDefaults.standard.data(forKey: "recent") ?? Data())) ?? []

    @ObservationIgnored let speaker = Speaker()
    @ObservationIgnored let agent = AgentClient()
    @ObservationIgnored var showOrb: ((Bool) -> Void)?
    @ObservationIgnored var activate: (() -> Void)?   // bring Jarvis forward so Wispr types into it
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var lastAnswer = ""
    @ObservationIgnored private var previousApp: NSRunningApplication?
    @ObservationIgnored private var collapseTask: Task<Void, Never>?

    init() {
        speaker.onStart = { [weak self] in
            guard let self, self.state != .confirm, self.state != .listening else { return }
            self.state = .speaking
        }
        speaker.onIdle = { [weak self] in self?.speechEnded() }
        agent.onEvent = { [weak self] in self?.handle($0) }
        agent.start()
    }

    // MARK: input

    /// Hotkey: open the input field; again = send now (or close it if empty). Also barges in on speech.
    func hotkey() {
        Log.write("hotkey (stato \(state.rawValue))")
        guard inputActive else { return listen() }
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? closeInput() : submit()
    }

    /// Shows the input field focused, remembering which app to give focus back to.
    func listen() {
        speaker.stop()  // don't let Wispr hear Jarvis
        if let front = NSWorkspace.shared.frontmostApplication, front != .current { previousApp = front }
        draft = ""
        inputActive = true
        if confirmation == nil { state = .listening }
        expand()
        activate?()
        focusRequest += 1
    }

    /// ⏎ or auto-send: an empty ⏎ during a confirmation means "sì".
    func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        guard !text.isEmpty else { if confirmation != nil { answerConfirmation(true) }; return }
        closeInput()
        heard(text)
    }

    /// Esc: "no" to a confirmation, otherwise close the field.
    func escape() {
        if confirmation != nil { draft = ""; return answerConfirmation(false) }
        closeInput()
        scheduleCollapse()
    }

    private func closeInput() {
        draft = ""
        inputActive = false
        if state == .listening { state = restingState }
        previousApp?.activate()
        previousApp = nil
    }

    private func heard(_ text: String) {
        status = ""
        transcript = text
        Log.write("utente: \(text)")
        let intent = Intent.route(text)

        if let c = confirmation {
            switch intent {
            case .yes: return answerConfirmation(true)
            case .no, .cancel, .stop: return answerConfirmation(false)
            default: listen(); return say("Dimmi sì o no. \(c.question)")  // listen() first: it stops speech
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
        case .agent(let command):
            ask(command, label: text)
        case .yes, .no:
            ask(text, label: text)  // no pending confirmation: just words for Claude
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
        closeInput()
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
            listen()  // ⏎ = sì, Esc = no, or dictate it
            say(q)
        case "done":
            busy = false
            confirmation = nil
            lastAnswer = e.text ?? answer
            if let text = e.text, !text.isEmpty { answer = text }
            Log.write("jarvis: \(Speaker.spokenPart(of: lastAnswer))")
            speaker.finishAnswer(fullText: lastAnswer)
            if !speaker.isSpeaking, state != .listening { state = restingState; scheduleCollapse() }
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
        if state == .speaking || state == .idle { state = restingState }
        if !busy { scheduleCollapse() }
    }

    func expand() {
        collapseTask?.cancel()
        expanded = true
        if !orbShown { setOrb(true) }
    }

    /// `remember` = user choice from menu/hotkey; auto show/hide doesn't persist.
    func setOrb(_ visible: Bool, remember: Bool = false) {
        orbShown = visible
        showOrb?(visible)
        if remember { UserDefaults.standard.set(visible, forKey: "orbVisible") }
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task {
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled, state == .idle, !inputActive else { return }
            expanded = false
            if Prefs.orbOnlyWhenActive { setOrb(false) }
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
