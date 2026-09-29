import SwiftUI

/// Menu bar › Cruscotto: Jarvis at a glance, the MCP servers the agent sees (plus Jarvis's own to add/remove), the log.
struct Dashboard: View {
    let app: AppState
    @State private var selection: Pane? = .overview
    @State private var config: [String: [String: Any]] = [:]  // loaded in onAppear, not on every rebuild
    @State private var adding = false
    @State private var saveError: String?
    @State private var agentSilent = false  // no mcp_status after a few seconds: agent down or stuck
    @State private var refreshing = false  // until the next mcp_status, or the agent is declared silent

    /// Enum, not a sentinel string: a server can't be named like the log entry.
    fileprivate enum Pane: Hashable { case overview, server(String), log }

    /// Agent's view first; Jarvis servers it didn't load (bad command, just added) still show up.
    private var rows: [McpServer] {
        let seen = Set(app.mcpServers.map(\.name))
        let missing = config.keys.filter { !seen.contains($0) }.sorted()
            .map { McpServer(name: $0, status: "not-loaded", error: nil, source: "jarvis", tools: nil) }
        return app.mcpServers + missing
    }

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            detail
        }
        .navigationTitle("Cruscotto")
        .navigationSubtitle("\(Prefs.isCopilot ? "GitHub Copilot" : "Claude Code") · \(app.state.label)")
        .toolbar {
            ToolbarItemGroup {
                Button { refreshing = true; app.refreshMcp(); waitForAgent() } label: {
                    Label("Aggiorna", systemImage: "arrow.clockwise")
                }
                .help("Rileggi lo stato dall'agente (⌘R)")
                .keyboardShortcut("r")
                .disabled(refreshing && !agentSilent)
                Button { adding = true } label: { Label("Aggiungi server", systemImage: "plus") }
                    .help("Aggiungi un server MCP a Jarvis (⌘N)")
                    .keyboardShortcut("n")
            }
        }
        .sheet(isPresented: $adding) { AddServerSheet(existing: Set(config.keys)) { name, entry in add(name, entry) } }
        .alert("Non riesco a salvare mcp.json",
               isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") {}
        } message: { Text(saveError ?? "") }
        .onAppear { config = McpConfig.load(); app.refreshMcp(); waitForAgent() }
        .onChange(of: app.mcpUpdated) { refreshing = false }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Label("Panoramica", systemImage: "gauge.with.dots.needle.33percent").tag(Pane.overview)
            Section("Server MCP · \(summary)") {
                ForEach(rows) { s in
                    ServerRow(server: s, owned: config[s.name] != nil).tag(Pane.server(s.name))
                }
                // Inline, not an overlay: Panoramica and Log stay reachable while the agent is down.
                if app.mcpUpdated == nil && agentSilent {
                    Label("L'agente non risponde", systemImage: "bolt.horizontal.circle").foregroundStyle(.secondary)
                    Button("Riavvia l'agente") { restartAgent() }
                } else if app.mcpUpdated == nil {
                    HStack { ProgressView().controlSize(.small); Text("Chiedo lo stato…").foregroundStyle(.secondary) }
                } else if rows.isEmpty {
                    Text("Nessun server: aggiungine uno con +.").foregroundStyle(.secondary)
                }
            }
            Section { Label("Log di Jarvis", systemImage: "text.alignleft").tag(Pane.log) }
        }
    }

    @ViewBuilder private var detail: some View {
        if selection == .overview {
            Overview(app: app, servers: rows, agentSilent: app.mcpUpdated == nil && agentSilent,
                     restartAgent: restartAgent, select: { selection = $0 })
        } else if selection == .log {
            LogTail()
        } else if case .server(let name) = selection, let s = rows.first(where: { $0.name == name }) {
            ServerDetail(server: s, config: config[s.name], app: app, remove: { remove(s.name) })
                .id(s.name)  // fresh state (reconnecting, confirm) per server
        } else {
            ContentUnavailableView("Scegli un server", systemImage: "sidebar.left",
                                   description: Text("Stato, tool e configurazione compaiono qui."))
        }
    }

    private func restartAgent() { agentSilent = false; app.restartAgent(); waitForAgent() }

    @State private var waitTask: Task<Void, Never>?
    private func waitForAgent() {
        waitTask?.cancel()
        let asked = app.mcpUpdated
        waitTask = Task {
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            if app.mcpUpdated == asked { agentSilent = true }
        }
    }

    private var summary: String {
        "\(rows.count(where: { $0.status == "connected" })) di \(rows.count) connessi"
    }

    private func add(_ name: String, _ entry: [String: Any]) {
        var next = config
        next[name] = entry
        persist(next)
        selection = .server(name)
    }

    private func remove(_ name: String) {
        var next = config
        next[name] = nil
        persist(next)
        selection = .overview
    }

    private func persist(_ next: [String: [String: Any]]) {
        do { try McpConfig.save(next); config = next; app.reloadMcp() }
        catch { saveError = error.localizedDescription }
    }
}

/// Home pane: the agent, the conversation, what's worth a click. Everything else has its own pane or Settings.
private struct Overview: View {
    let app: AppState
    let servers: [McpServer]
    let agentSilent: Bool
    let restartAgent: () -> Void
    let select: (Dashboard.Pane) -> Void
    @AppStorage("muted") private var muted = false
    @AppStorage("vaultPath") private var vaultPath = ""  // observed: the vault section follows a folder change

    private var folder: String { vaultPath.isEmpty ? Prefs.vaultPath : vaultPath }
    private var troubled: [McpServer] { servers.filter { $0.status != "connected" && $0.status != "disabled" } }

    var body: some View {
        Form {
            Section {
                LabeledContent("Stato") {
                    Label(agentSilent ? "L'agente non risponde" : app.state.label,
                          systemImage: agentSilent ? "bolt.horizontal.circle" : app.state.symbol)
                        .foregroundStyle(agentSilent || app.state == .error ? .red : .primary)
                }
                if app.state == .error, !app.status.isEmpty {
                    Text(app.status).foregroundStyle(.red).textSelection(.enabled)
                }
                LabeledContent("Motore", value: Prefs.isCopilot ? "GitHub Copilot" : "Claude Code")
                LabeledContent("Cartella") {
                    Button(folder.replacingOccurrences(of: Prefs.home, with: "~")) {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder)
                    }
                    .buttonStyle(.link)
                    .help("Mostra nel Finder")
                }
                LabeledContent("Dettatura", value: Prefs.dictation == "jarvis" ? "Jarvis (microfono)" : "Wispr Flow")
                Toggle("Voce muta", isOn: $muted).onChange(of: muted) { _, m in if m { app.speaker.stop() } }
                HStack {
                    Button("Parla con Jarvis") { app.listen() }.keyboardShortcut(.return)
                    Button("Nuova sessione") { app.newSession() }
                    Button("Apri in Terminale") { Terminal.resumeSession() }
                        .help("Stessa conversazione di Jarvis: non usarli tutti e due nello stesso momento")
                    Spacer()
                    Button("Riavvia l'agente", action: restartAgent)
                }
            } header: {
                Text("Jarvis").font(.title2.weight(.semibold)).foregroundStyle(.primary).textCase(nil)
                    .accessibilityAddTraits(.isHeader)
            }

            Section("Conversazione") {
                if app.transcript.isEmpty {
                    Text("Nessuna domanda in questa sessione.").foregroundStyle(.secondary)
                } else {
                    LabeledContent("Ultima domanda") { Text(app.transcript).lineLimit(2).textSelection(.enabled) }
                    if app.busy {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(app.tools.last?.text ?? "Al lavoro…").lineLimit(1).foregroundStyle(.secondary)
                            Spacer()
                            Button("Ferma") { app.stopAnswer() }
                        }
                    } else if !app.answer.isEmpty {
                        Text(Speaker.spokenPart(of: app.answer)).lineLimit(4).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    LabeledContent("Scambi", value: "\(app.history.count + 1)")
                }
            }

            if !app.recent.isEmpty {
                Section("Recenti") {
                    ForEach(app.recent) { r in
                        Button { app.ask(r.command, label: r.label) } label: {
                            Label(r.label, systemImage: "arrow.counterclockwise").lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .help("Richiedi di nuovo: \(r.command)")
                    }
                }
            }

            if FileManager.default.fileExists(atPath: folder + "/00-Inbox") {  // = Prefs.isVault, observed
                Section("Vault") {
                    HStack {
                        Button("Prepara la giornata") { app.ask("/prep-day") }
                        Button("Chiudi la giornata") { app.ask("/close-day") }
                        Button("Settimana") { app.ask("/weekly") }
                    }
                    HStack {
                        Button("Sincronizza ticket") { app.ask("/pull-tickets") }
                        Button("Sincronizza MR") { app.ask("/pull-mrs") }
                        Spacer()
                        Button("Daily in Obsidian") { openObsidian(todayDaily) }
                    }
                }
            }

            Section("Server MCP") {
                LabeledContent("Connessi", value: "\(servers.count(where: { $0.status == "connected" })) di \(servers.count)")
                ForEach(troubled) { s in
                    Button { select(.server(s.name)) } label: {
                        LabeledContent(s.name) { McpStatusBadge(status: s.status) }
                    }
                    .buttonStyle(.plain)
                    .help("Apri \(s.name)")
                }
                if !servers.isEmpty && troubled.isEmpty {
                    Label("Tutti a posto", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Status is always icon + word + color, never color alone.
struct McpStatusBadge: View {
    let status: String

    var body: some View {
        Label(text, systemImage: icon)
            .foregroundStyle(color)
            .accessibilityLabel("Stato: \(text)")
    }

    private var text: String {
        switch status {
        case "connected": "Connesso"
        case "failed": "Errore"
        case "needs-auth": "Serve login"
        case "pending": "In connessione"
        case "disabled": "Disattivato"
        case "stopped": "Fermo"
        case "not-loaded": "Non caricato"
        default: status
        }
    }

    private var icon: String {
        switch status {
        case "connected": "checkmark.circle.fill"
        case "failed", "not-loaded": "exclamationmark.triangle.fill"
        case "needs-auth": "key.fill"
        case "pending": "clock.fill"
        default: "pause.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case "connected": .green
        case "failed", "not-loaded": .red
        case "needs-auth", "pending": .orange
        default: .secondary
        }
    }
}

private struct ServerRow: View {
    let server: McpServer
    let owned: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name).fontWeight(.medium)
                McpStatusBadge(status: server.status).font(.caption).labelStyle(.titleAndIcon)
            }
            Spacer()
            if let n = server.tools?.count, n > 0 {
                Text("\(n)").monospacedDigit().font(.caption).foregroundStyle(.secondary)
                    .help("\(n) tool")
                    .accessibilityLabel("\(n) tool")
            }
            if owned {
                Image(systemName: "person.crop.circle").foregroundStyle(.tint).help("Aggiunto in Jarvis")
                    .accessibilityLabel("Aggiunto in Jarvis")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct ServerDetail: View {
    let server: McpServer
    let config: [String: Any]?
    let app: AppState
    let remove: () -> Void
    @State private var confirmRemove = false
    @State private var reconnecting = false  // until the next mcp_status, at most 10s

    var body: some View {
        Form {
            Section {
                LabeledContent("Stato") { McpStatusBadge(status: server.status) }
                LabeledContent("Origine", value: origin)
                if let error = server.error {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                        .accessibilityLabel("Errore: \(error)")
                }
                if server.status != "not-loaded" {
                    HStack {
                        Button("Riconnetti") { reconnecting = true; app.reconnectMcp(server.name) }
                            .disabled(reconnecting)
                        if reconnecting { ProgressView().controlSize(.small) }
                    }
                }
            } header: {
                Text(server.name).font(.title2.weight(.semibold)).foregroundStyle(.primary).textCase(nil)
                    .accessibilityAddTraits(.isHeader)
            }

            if let config {
                Section("Configurazione (mcp.json)") {
                    if let url = config["url"] as? String {
                        LabeledContent("URL") { Text(url).monospaced().textSelection(.enabled) }
                    } else {
                        LabeledContent("Comando") { Text(commandLine(config)).monospaced().textSelection(.enabled) }
                    }
                    Button("Rimuovi da Jarvis…", role: .destructive) { confirmRemove = true }
                }
            }

            Section("Tool (\(server.tools?.count ?? 0))") {
                if let tools = server.tools, !tools.isEmpty {
                    ForEach(tools, id: \.self) { Text($0).monospaced().textSelection(.enabled) }
                } else {
                    Text(server.status == "connected" ? "Nessun tool esposto." : "I tool compaiono quando il server è connesso.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: app.mcpUpdated) { reconnecting = false }
        .task(id: reconnecting) {
            guard reconnecting else { return }
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            reconnecting = false
        }
        .confirmationDialog("Rimuovere \(server.name) da Jarvis?", isPresented: $confirmRemove) {
            Button("Rimuovi", role: .destructive, action: remove)
        } message: {
            Text("Viene tolto da mcp.json e l'agente ricarica i server.")
        }
    }

    private var origin: String {
        if config != nil { return "Jarvis (mcp.json)" }
        switch server.source {
        case "user": return "Utente"
        case "project": return "Progetto (.mcp.json)"
        case "local": return "Locale"
        case "builtin": return "Integrato"
        case "plugin": return "Plugin"
        case let s?: return s.capitalized
        case nil: return "—"
        }
    }

    private func commandLine(_ c: [String: Any]) -> String {
        ([c["command"] as? String ?? ""] + (c["args"] as? [String] ?? [])).joined(separator: " ")
    }
}

private struct AddServerSheet: View {
    let existing: Set<String>
    let onAdd: (String, [String: Any]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind = "stdio"
    @State private var command = ""
    @State private var args = ""
    @State private var url = ""

    private var nameError: String? {
        if existing.contains(name) { return "Esiste già in mcp.json: rimuovilo prima, o modifica il file." }  // add would drop its env/headers
        return name.isEmpty || name.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
            ? nil : "Solo lettere, numeri, - e _."
    }
    private var urlValid: Bool { URL(string: url.trimmingCharacters(in: .whitespaces))?.scheme?.hasPrefix("http") == true }
    private var valid: Bool {
        !name.isEmpty && nameError == nil
            && (kind == "stdio" ? !command.trimmingCharacters(in: .whitespaces).isEmpty : urlValid)
    }

    var body: some View {
        Form {
            Section {
                TextField("Nome", text: $name, prompt: Text("es. filesystem"))
                if let nameError { Text(nameError).font(.caption).foregroundStyle(.red) }
                Picker("Tipo", selection: $kind) {
                    Text("Locale (stdio)").tag("stdio")
                    Text("Remoto (HTTP)").tag("http")
                }
                .pickerStyle(.segmented)
            }
            Section {
                if kind == "stdio" {
                    TextField("Comando", text: $command, prompt: Text("npx"))
                    TextField("Argomenti", text: $args, prompt: Text("-y @modelcontextprotocol/server-filesystem ~/Documents"))
                    Text("Argomenti separati da spazi. Variabili d'ambiente: modifica mcp.json a mano.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    TextField("URL", text: $url, prompt: Text("https://example.com/mcp"))
                    if !url.isEmpty && !urlValid {
                        Text("Deve iniziare con http:// o https://").font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Aggiungi") {
                    // ponytail: args split on spaces, no quoting; paths with spaces go in mcp.json by hand
                    let entry: [String: Any] = kind == "stdio"
                        ? ["type": "stdio", "command": command.trimmingCharacters(in: .whitespaces),
                           "args": args.split(separator: " ").map(String.init)]
                        : ["type": "http", "url": url.trimmingCharacters(in: .whitespaces)]
                    onAdd(name, entry)
                    dismiss()
                }
                .disabled(!valid)
            }
        }
    }
}

private struct LogTail: View {
    @State private var lines: [String] = []

    var body: some View {
        ScrollView {
            Text(lines.joined(separator: "\n"))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .defaultScrollAnchor(.bottom)  // follows new lines only while already at the bottom
        .toolbar {
            ToolbarItem {
                Button { NSWorkspace.shared.open(Log.dir) } label: { Label("Apri cartella log", systemImage: "folder") }
            }
        }
        .overlay { if lines.isEmpty { ContentUnavailableView("Log vuoto", systemImage: "text.alignleft") } }
        .task {
            // Follows the log while shown; the task ends with the view.
            while !Task.isCancelled {
                let tail = await Self.tail()
                if tail != lines { lines = tail }  // unchanged: no scroll jump
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    /// Last ~64 KB only (the log grows to 5 MB), read off the main actor.
    @concurrent private static func tail() async -> [String] {
        guard let h = try? FileHandle(forReadingFrom: Log.url) else { return [] }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 65_536 ? size - 65_536 : 0)
        let text = String(decoding: (try? h.readToEnd()) ?? Data(), as: UTF8.self)
        var lines = text.split(separator: "\n").map(String.init)
        if size > 65_536, !lines.isEmpty { lines.removeFirst() }  // cut mid-line
        return Array(lines.suffix(200))
    }
}
