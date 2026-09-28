import Foundation

/// One JSON line from agent/agent.mjs.
struct AgentEvent: Decodable {
    let type: String
    var id, delta, name, summary, path, op, question, text, message, session_id: String?
    var commands: [SlashCommand]?
    var servers: [McpServer]?
}

/// An MCP server as the running agent sees it (mcp_status).
struct McpServer: Decodable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let status: String   // connected | failed | needs-auth | pending | disabled | stopped
    var error: String?
    var source: String?
    var tools: [String]?
}

/// A skill or command Claude Code offers in this session (typed as /name).
struct SlashCommand: Decodable, Hashable {
    let name: String
    let description: String
    let argumentHint: String?
}

/// Runs `node agent.mjs` (Claude) or `node copilot.mjs` (Copilot) with cwd = vault and talks JSON lines. Restarts with backoff if it dies.
@MainActor final class AgentClient {
    var onEvent: ((AgentEvent) -> Void)?
    private var process: Process?
    private var stdin: FileHandle?
    private var backoff: Double = 1
    private var stopping = false

    func start() {
        stopping = false
        signal(SIGPIPE, SIG_IGN)  // writing to a just-died agent must fail, not kill the app
        let name = Prefs.isCopilot ? "copilot" : "agent"
        guard let script = Bundle.main.url(forResource: name, withExtension: "mjs", subdirectory: "agent") else {
            return fail("\(name).mjs non trovato nel bundle")
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: Prefs.vaultPath, isDirectory: &isDir), isDir.boolValue else {
            return fail("Cartella di lavoro non trovata: \(Prefs.vaultPath). Sceglila in Impostazioni.")
        }
        let node = Prefs.nodePath
        guard FileManager.default.isExecutableFile(atPath: node) else { return fail("Node non trovato in \(node). Controlla le impostazioni.") }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: node)
        p.arguments = [script.path]
        p.currentDirectoryURL = URL(fileURLWithPath: Prefs.vaultPath)
        var env = ProcessInfo.processInfo.environment
        // GUI apps don't inherit the shell PATH: give skills the usual tools.
        env["PATH"] = [(node as NSString).deletingLastPathComponent, Prefs.home + "/.local/bin",
                       "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")
        env["JARVIS_VAULT"] = Prefs.vaultPath
        env["JARVIS_CLAUDE"] = Prefs.claudePath
        env["JARVIS_COPILOT"] = Prefs.copilotPath
        env["JARVIS_STATE"] = Prefs.sessionFile
        env["JARVIS_MCP"] = McpConfig.url.path
        if let key = Keychain.apiKey { env["ANTHROPIC_API_KEY"] = key }
        p.environment = env

        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = errPipe

        nonisolated(unsafe) var buffer = Data()  // readabilityHandler calls are serial for one handle
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { h.readabilityHandler = nil; return }  // EOF: else it fires in a loop
            buffer.append(data)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<nl]; buffer.removeSubrange(...nl)
                guard let event = try? JSONDecoder().decode(AgentEvent.self, from: line) else { continue }
                Task { @MainActor in self?.received(event) }
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            guard !data.isEmpty else { h.readabilityHandler = nil; return }
            if let s = String(data: data, encoding: .utf8) { Log.write("agent stderr: \(s)") }
        }
        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in self?.terminated(proc) }
        }
        do {
            try p.run()
            process = p; stdin = inPipe.fileHandleForWriting
            Log.write("agent avviato pid \(p.processIdentifier)")
        } catch { fail("Avvio agente fallito: \(error.localizedDescription)") }
    }

    func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        guard let stdin, (try? stdin.write(contentsOf: data + Data([0x0A]))) != nil else {
            return fail("Agente non pronto, riprova tra un attimo.")  // unblocks a UI waiting on this prompt
        }
    }

    func stop() {
        stopping = true
        process?.terminate()
    }

    private func received(_ event: AgentEvent) {
        if event.type == "ready" || event.type == "done" { backoff = 1 }
        onEvent?(event)
    }

    private func terminated(_ proc: Process) {
        guard proc === process else { return } // an old process after a manual restart
        process = nil; stdin = nil
        guard !stopping else { return }
        Log.write("agente terminato (\(proc.terminationStatus)), riavvio tra \(backoff)s")
        onEvent?(AgentEvent(type: "error", message: "L'agente si è fermato, lo riavvio."))
        let delay = backoff
        backoff = min(backoff * 2, 30)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            if !self.stopping { self.start() }
        }
    }

    private func fail(_ message: String) {
        Log.write(message)
        onEvent?(AgentEvent(type: "error", message: message))
    }
}
