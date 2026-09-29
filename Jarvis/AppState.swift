import AppKit
import Observation

struct ToolItem: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
}

/// A finished exchange, kept on screen above the current one.
struct Turn: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}

struct RecentCommand: Identifiable, Codable {
    var id = UUID()
    let label: String
    let command: String
}

/// Orchestrates dictated input (Wispr) ↔ agent ↔ voice/orb. Everything runs on the main actor.
@MainActor @Observable final class AppState {
    var state: OrbState = .idle
    var orbVariant = "blob"  // shape the orb takes while Jarvis works, picked by the agent (⟦orb:…⟧)
    var transcript = ""     // last message sent
    var history: [Turn] = []  // earlier exchanges of this session, oldest first
    var draft = ""          // what Wispr is typing into the input field
    var inputActive = false
    private(set) var awaitsReturn = false  // text put in the field by another app (link, Services): never auto-sent
    var focusRequest = 0    // bumped to (re)focus the input field
    var answer = ""
    var tools: [ToolItem] = []
    var confirmation: (id: String, question: String)?
    var status = ""
    var expanded = false
    var orbShown = false
    var anchorTop = false   // which screen corner the orb sits in: the card opens toward the center
    var anchorLeft = false
    var screenHeight: CGFloat = 800  // visible height of the orb's screen, caps the conversation
    private(set) var busy = false
    private(set) var startedAt: Date?          // current turn, for the header timer
    private(set) var failedPrompt: RecentCommand?  // last prompt that ended in an error: "Riprova"
    var commands: [SlashCommand] = []   // for the "/" picker, from the agent
    var mcpServers: [McpServer] = []    // MCP dashboard, from the agent's mcp_status
    var mcpUpdated: Date?
    var recent: [RecentCommand] = (try? JSONDecoder().decode([RecentCommand].self, from: UserDefaults.standard.data(forKey: "recent") ?? Data())) ?? []

    @ObservationIgnored let speaker = Speaker()
    @ObservationIgnored let agent = AgentClient()
    @ObservationIgnored let dictation = Dictation()
    @ObservationIgnored let notifier = Notifier()
    @ObservationIgnored var showOrb: ((Bool) -> Void)?
    @ObservationIgnored var activate: (() -> Void)?   // bring Jarvis forward so Wispr types into it
    @ObservationIgnored var openDashboard: (() -> Void)?  // set by MenuBarIcon, which lives in a scene
    @ObservationIgnored var openSettings: (() -> Void)?
    @ObservationIgnored var openOnboarding: (() -> Void)?
    @ObservationIgnored private var lastAnswer = ""
    @ObservationIgnored private var previousApp: NSRunningApplication?
    @ObservationIgnored private var collapseTask: Task<Void, Never>?
    @ObservationIgnored private var errorTask: Task<Void, Never>?
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var replyWaiters: [CheckedContinuation<String, any Error>] = []  // Shortcuts waiting for the answer

    init() {
        speaker.onStart = { [weak self] in
            guard let self, self.state != .confirm else { return }
            self.state = .speaking
        }
        speaker.onIdle = { [weak self] in self?.speechEnded() }
        agent.onEvent = { [weak self] in self?.handle($0) }
        notifier.onClick = { [weak self] in self?.listen() }
        if Prefs.onboarded { agent.start() }  // first run: the onboarding starts it, instead of a "folder not found" error
    }

    // MARK: input

    /// Hotkey: open the conversation (or bring the cursor back to it); again = send now (or close it if empty).
    /// Also barges in on speech.
    func hotkey() {
        Log.write("hotkey (stato \(state.rawValue))")
        guard inputActive else { return listen() }
        guard NSApp.isActive else { return focusInput() }
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? close() : submit()
    }

    /// Shows the input field focused, remembering which app to give focus back to.
    /// `prefill` goes in before the built-in dictation starts, so the dictation continues it.
    /// `awaitsReturn`: the text came from outside Jarvis (a link any web page can open): only ⏎ sends it.
    func listen(prefill: String = "", awaitsReturn: Bool = false) {
        speaker.stop()  // don't let Wispr hear Jarvis
        draft = prefill
        self.awaitsReturn = awaitsReturn
        inputActive = true
        state = restingState
        expand()
        focusInput()
        startDictation()
    }

    /// Built-in dictation (no Wispr): the mic writes into the field; the auto-send in the overlay does the rest.
    /// Off while Jarvis thinks or speaks, so it never hears itself.
    private func startDictation() {
        guard Prefs.dictation == "jarvis", inputActive else { return }
        let base = draft  // e.g. a dropped folder path: the dictation continues it
        dictation.start { [weak self] in self?.draft = base + $0 }
    }

    /// Makes Jarvis the key app and puts the cursor in the input field (after SwiftUI has built it).
    func focusInput() {
        if let front = NSWorkspace.shared.frontmostApplication, front != .current { previousApp = front }
        activate?()
        Task { @MainActor in focusRequest += 1 }
    }

    /// ⏎ or auto-send. The field stays open, so the next dictation continues the conversation.
    /// An empty ⏎ during a confirmation means "sì".
    func submit() {
        dictation.stop()
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        awaitsReturn = false
        guard !text.isEmpty else { if confirmation != nil { answerConfirmation(true) }; return }
        heard(text)
    }

    /// Esc: "no" to a confirmation, else clears the field, else closes the conversation.
    func escape() {
        if confirmation != nil { draft = ""; return answerConfirmation(false) }
        if !draft.isEmpty { draft = ""; awaitsReturn = false; return }
        close()
    }

    /// ✕ / Esc on an empty field: stop talking, hide the card, give focus back. Claude keeps working if busy.
    func close() {
        if confirmation != nil { answerConfirmation(false) }  // don't leave the agent waiting on a hidden question
        speaker.stop()
        dictation.stop()
        draft = ""
        awaitsReturn = false
        inputActive = false
        expanded = false
        state = restingState
        previousApp?.activate()
        previousApp = nil
        if Prefs.orbOnlyWhenActive, !busy { setOrb(false) }
    }

    private func heard(_ text: String) {
        status = ""
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
            stopAnswer()
        case .clear:
            newSession()
        case .cancel:
            if busy { speaker.stop(); agent.send(["type": "interrupt"]); say("Annullato.") } else { say("Non c'è niente da annullare.") }
        case .repeatLast:
            say(lastAnswer.isEmpty ? "Non ho ancora detto niente." : Speaker.spokenPart(of: lastAnswer))
        case .clipboard(let ingest, let question):
            clipboard(ingest: ingest, question: question)
        case .agent(let command):
            ask(command, label: text)
        case .screen(let question):
            askAboutFrontApp(question, screenshot: true)
        case .front(let question):
            askAboutFrontApp(question, screenshot: false)
        case .quick(let question):
            quickAnswer(question, label: text)
        case .yes, .no:
            ask(text, label: text)  // no pending confirmation: just words for Claude
        }
    }

    /// Sends a prompt to the agent. `label` is what the user said (shown in "recenti").
    func ask(_ command: String, label: String? = nil) {
        beginTurn(label ?? command)
        busy = true
        startedAt = .now
        failedPrompt = nil
        state = .thinking
        expand()
        speaker.beginAnswer()
        remember(RecentCommand(label: label ?? command, command: command))
        agent.send(["type": "prompt", "id": UUID().uuidString, "text": command])
    }

    /// Shortcuts / Spotlight: same as `ask`, then waits for the end of the turn and returns the answer.
    func reply(to prompt: String) async throws -> String {
        guard !busy else { throw JarvisError(message: "Jarvis sta già rispondendo, riprova tra poco.") }  // the running turn's done would answer this one
        // registered before ask(): a failed send emits its error synchronously
        return try await withCheckedThrowingContinuation { replyWaiters.append($0); ask(prompt) }
    }

    private func endTurn(_ result: Result<String, any Error>) {
        orbVariant = "blob"
        let waiters = replyWaiters
        replyWaiters = []
        for w in waiters { w.resume(with: result) }
    }

    /// Moves the current exchange into the history and starts showing a new one.
    private func beginTurn(_ label: String) {
        speaker.stop()
        dictation.stop()
        if !transcript.isEmpty, !answer.isEmpty {
            history.append(Turn(question: transcript, answer: answer))
            history = Array(history.suffix(10))  // ponytail: last 10 on screen, the full session is in Claude Code
        }
        transcript = label
        answer = ""; tools = []
    }

    /// "domanda veloce": the on-device model answers; without Apple Intelligence the agent does.
    private func quickAnswer(_ question: String, label: String) {
        state = .thinking
        Task {
            guard let reply = await QuickAnswer.reply(question) else { return ask(question, label: label) }
            beginTurn(label)
            answer = reply
            lastAnswer = reply
            state = restingState
            expand()
            say(reply)
        }
    }

    /// "cosa vedi" / "questa pagina": adds what the app Jarvis was called from shows (and a screenshot of it).
    private func askAboutFrontApp(_ question: String, screenshot: Bool) {
        guard let front = previousApp else {
            return screenshot ? say("Chiamami dall'app che vuoi farmi vedere.") : ask(question)
        }
        FrontContext.requestAccessibility()
        state = .thinking
        Task {
            let pid = front.processIdentifier
            var context = await FrontContext.describe(pid: pid, name: front.localizedName ?? "sconosciuta")
            if screenshot {
                do { context += "\nScreenshot della finestra (leggilo): \(try await FrontContext.screenshot(pid: pid).path)" }
                catch {
                    Log.write("screenshot: \(error)")
                    state = restingState
                    return say("Non riesco a vedere lo schermo. Dai il permesso Registrazione schermo a Jarvis in Impostazioni di Sistema, poi riavvialo.")
                }
            }
            ask("\(question)\n\nContesto, l'app da cui mi hai chiamato:\n\(context)", label: question)
        }
    }

    func answerConfirmation(_ allow: Bool) {
        guard let c = confirmation else { return }
        confirmation = nil
        speaker.beginAnswer()  // stop() muted the rest of the turn: speak what Claude says after the answer
        agent.send(["type": "confirm", "id": c.id, "allow": allow])
        tools.append(ToolItem(icon: allow ? "checkmark.circle" : "xmark.circle", text: allow ? "Confermato" : "Rifiutato"))
        state = restingState
    }

    // MARK: files & clipboard

    /// Drag & drop: copy into 00-Inbox and run /ingest.
    /// Folders (e.g. a project in ~/Dev) are never copied: their absolute path goes in the field, to dictate what to do.
    /// Outside the vault there is no 00-Inbox or /ingest: files get the same treatment as folders.
    func ingest(files: [URL]) {
        let isDir = { (u: URL) in !Prefs.isVault || (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        let folders = files.filter(isDir)
        if !folders.isEmpty {
            listen(prefill: folders.map { "\"\($0.path)\"" }.joined(separator: " ") + " ")
        }
        let files = files.filter { !isDir($0) }
        guard !files.isEmpty else { return }
        let inbox = URL(fileURLWithPath: Prefs.vaultPath).appending(path: "00-Inbox")
        Task {
            let (copied, failed) = await Self.copy(files, to: inbox)  // a big drop must not freeze the orb
            if let f = failed.last { status = "Non riesco a copiare \(f)." }
            guard !copied.isEmpty else { return }
            ask("/ingest " + copied.joined(separator: " "), label: "Ingest di \(files.map(\.lastPathComponent).joined(separator: ", "))")
        }
    }

    /// Off the main actor. Returns the quoted vault paths copied and the names that failed.
    @concurrent private static func copy(_ files: [URL], to inbox: URL) async -> ([String], [String]) {
        var copied: [String] = [], failed: [String] = []
        for file in files {
            let dest = unique(inbox.appending(path: file.lastPathComponent))
            do {
                try FileManager.default.copyItem(at: file, to: dest)
                copied.append("\"00-Inbox/\(dest.lastPathComponent)\"")
            } catch {
                Log.write("copia fallita \(file.path): \(error)")
                failed.append(file.lastPathComponent)
            }
        }
        return (copied, failed)
    }

    /// "+" in the input field: same as dropping the files on the orb.
    func pickFiles() {
        let open = NSOpenPanel()
        open.allowsMultipleSelection = true
        open.canChooseDirectories = true
        NSApp.activate()
        if open.runModal() == .OK, !open.urls.isEmpty { ingest(files: open.urls) }
        activate?()
    }

    private func clipboard(ingest: Bool, question: String) {
        let pb = NSPasteboard.general
        // Finder's ⌘C on a file or folder: the string is just the name, the path is in the file URLs.
        let copied = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let text = copied.isEmpty ? pb.string(forType: .string) : copied.map(\.path).joined(separator: "\n")
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
            } else if let tiff = NSImage(pasteboard: pb)?.tiffRepresentation {
                file = Self.unique(inbox.appending(path: "clipboard-\(stamp).png"))
                Task {
                    do { try await Self.writePNG(tiff, to: file) }  // encoding a big screenshot takes a while
                    catch { return status = "Non riesco a salvare la clipboard: \(error.localizedDescription)" }
                    ask("/ingest \"00-Inbox/\(file.lastPathComponent)\"", label: question)
                }
                return
            } else {
                return say("La clipboard è vuota.")
            }
            ask("/ingest \"00-Inbox/\(file.lastPathComponent)\"", label: question)
        } catch {
            status = "Non riesco a salvare la clipboard: \(error.localizedDescription)"
        }
    }

    @concurrent private static func writePNG(_ tiff: Data, to url: URL) async throws {
        guard let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
    }

    nonisolated private static func unique(_ url: URL) -> URL {
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
        case "commands":
            // /clear is a CLI built-in the SDK doesn't list: Jarvis handles it itself (Intent.clear).
            commands = [SlashCommand(name: "clear", description: "Nuova sessione, azzera la conversazione", argumentHint: nil)]
                + (e.commands ?? []).filter { $0.name != "clear" }
        case "partial_text":
            guard let d = e.delta else { return }
            answer += d
            speaker.feed(d)
        case "mcp_status":
            mcpServers = (e.servers ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            mcpUpdated = .now
        case "orb":
            orbVariant = e.variant ?? "blob"
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
            endTurn(.success(lastAnswer))
            // In another app for a long turn: the voice alone may go unheard (muted, headphones off).
            if !NSApp.isActive, let startedAt, Date.now.timeIntervalSince(startedAt) > 15 {
                notifier.post(Speaker.spokenPart(of: lastAnswer))
            }
            speaker.finishAnswer(fullText: lastAnswer)
            if !speaker.isSpeaking { state = restingState; scheduleCollapse() }
        case "error":
            busy = false
            confirmation = nil
            status = e.message ?? "Errore sconosciuto"
            failedPrompt = recent.first  // ask() put the prompt that failed on top
            Log.write("errore: \(status)")
            endTurn(.failure(JarvisError(message: status)))
            state = .error
            expand()
            errorTask?.cancel()
            errorTask = Task {
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                if state == .error { state = restingState }
            }
        default: break
        }
    }

    // MARK: helpers

    private var restingState: OrbState { confirmation != nil ? .confirm : busy ? .thinking : inputActive ? .listening : .idle }

    private func say(_ text: String) {
        dictation.stop()
        speaker.say(text)
    }

    private func speechEnded() {
        if state == .speaking || state == .idle || state == .listening { state = restingState }
        if !busy { scheduleCollapse() }
        if !busy || confirmation != nil { startDictation() }  // the next turn, or the "sì / no"
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

    func retry() {
        guard let p = failedPrompt else { return }
        status = ""
        ask(p.command, label: p.label)
    }

    /// Stop button / "stop": silence and interrupt Claude mid-answer. The agent closes the turn with a done.
    func stopAnswer() {
        speaker.stop()
        if busy { agent.send(["type": "interrupt"]) }
    }

    func newSession() {
        agent.send(["type": "new_session"])  // the old turn gets no done/error: reset here
        endTurn(.failure(CancellationError()))
        speaker.stop()
        busy = false; confirmation = nil
        answer = ""; tools = []; transcript = ""; history = []
        state = restingState
    }

    // MARK: MCP dashboard

    func refreshMcp() { agent.send(["type": "mcp_status"]) }
    func reconnectMcp(_ name: String) { agent.send(["type": "mcp_reconnect", "name": name]) }
    /// After mcp.json changed: the agent re-reads it and answers with a fresh mcp_status.
    func reloadMcp() { agent.send(["type": "mcp_reload"]) }

    /// End of the onboarding. A new vault is built by the agent itself, interviewing the user.
    func finishOnboarding(newVault: Bool) {
        Prefs.onboarded = true
        agent.start()  // right away, not restartAgent()'s delay: the prompt below goes to this process
        if newVault { ask(Onboarding.vaultPrompt(engine: Prefs.backend), label: "Crea il mio vault") }
    }

    func restartAgent() {
        agent.stop()
        // The old turn gets no done/error (stop() is deliberate): reset it here, like newSession().
        endTurn(.failure(CancellationError()))
        speaker.stop()
        busy = false; confirmation = nil
        state = restingState
        restartTask?.cancel()
        restartTask = Task {
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            agent.start()
        }
    }
}

/// Shown by Shortcuts when "Chiedi a Jarvis" fails.
struct JarvisError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
