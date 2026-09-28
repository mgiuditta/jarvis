import SwiftUI

/// Menu bar › Cruscotto MCP: what the running agent sees, plus Jarvis's own servers to add/remove.
struct McpDashboard: View {
    let app: AppState
    @State private var selection: Pane?
    @State private var config: [String: [String: Any]] = [:]  // loaded in onAppear, not on every rebuild
    @State private var adding = false
    @State private var saveError: String?
    @State private var agentSilent = false  // no mcp_status after a few seconds: agent down or stuck

    /// Enum, not a sentinel string: a server can't be named like the log entry.
    private enum Pane: Hashable { case server(String), log }

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
        .navigationTitle("Cruscotto MCP")
        .navigationSubtitle("\(Prefs.isCopilot ? "GitHub Copilot" : "Claude Code") · \(summary)")
        .toolbar {
            ToolbarItemGroup {
                Button { app.refreshMcp() } label: { Label("Aggiorna", systemImage: "arrow.clockwise") }
                    .help("Rileggi lo stato dall'agente")
                Button { adding = true } label: { Label("Aggiungi server", systemImage: "plus") }
                    .help("Aggiungi un server MCP a Jarvis")
            }
        }
        .sheet(isPresented: $adding) { AddServerSheet(existing: Set(config.keys)) { name, entry in add(name, entry) } }
        .alert("Non riesco a salvare mcp.json",
               isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") {}
        } message: { Text(saveError ?? "") }
        .onAppear { config = McpConfig.load(); app.refreshMcp(); waitForAgent() }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Server") {
                ForEach(rows) { s in
                    ServerRow(server: s, owned: config[s.name] != nil).tag(Pane.server(s.name))
                }
            }
            Section { Label("Log di Jarvis", systemImage: "text.alignleft").tag(Pane.log) }
        }
        .overlay {
            if app.mcpUpdated == nil && agentSilent {
                ContentUnavailableView {
                    Label("L'agente non risponde", systemImage: "bolt.horizontal.circle")
                } description: {
                    Text("Controlla motore e cartella in Impostazioni, o il log.")
                } actions: {
                    Button("Riavvia l'agente") { agentSilent = false; app.restartAgent(); waitForAgent() }
                }
            } else if app.mcpUpdated == nil {
                ProgressView("Chiedo lo stato all'agente…")
            } else if rows.isEmpty {
                ContentUnavailableView {
                    Label("Nessun server MCP", systemImage: "puzzlepiece.extension")
                } description: {
                    Text("Aggiungine uno con +: funziona sia con Claude sia con Copilot.")
                }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if selection == .log {
            LogTail()
        } else if case .server(let name) = selection, let s = rows.first(where: { $0.name == name }) {
            ServerDetail(server: s, config: config[s.name], app: app, remove: { remove(s.name) })
        } else {
            ContentUnavailableView("Scegli un server", systemImage: "sidebar.left",
                                   description: Text("Stato, tool e configurazione compaiono qui."))
        }
    }

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
        selection = nil
    }

    private func persist(_ next: [String: [String: Any]]) {
        do { try McpConfig.save(next); config = next; app.reloadMcp() }
        catch { saveError = error.localizedDescription }
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
            }
            if owned { Image(systemName: "person.crop.circle").foregroundStyle(.tint).help("Aggiunto in Jarvis") }
        }
        .padding(.vertical, 2)
    }
}

private struct ServerDetail: View {
    let server: McpServer
    let config: [String: Any]?
    let app: AppState
    let remove: () -> Void
    @State private var confirmRemove = false

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
                    Button("Riconnetti") { app.reconnectMcp(server.name) }
                }
            } header: {
                Text(server.name).font(.title2.weight(.semibold)).foregroundStyle(.primary).textCase(nil)
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
    private var valid: Bool {
        !name.isEmpty && nameError == nil
            && (kind == "stdio" ? !command.trimmingCharacters(in: .whitespaces).isEmpty : URL(string: url)?.scheme?.hasPrefix("http") == true)
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
        ScrollViewReader { proxy in
            ScrollView {
                Text(lines.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                Color.clear.frame(height: 1).id("end")
            }
            .onChange(of: lines) { proxy.scrollTo("end") }
        }
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
