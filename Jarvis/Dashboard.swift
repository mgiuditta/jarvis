import SwiftUI

/// Jarvis's own MCP servers: ~/Library/Application Support/Jarvis/mcp.json, same shape as a .mcp.json.
/// Both agents read it (JARVIS_MCP); servers from Claude/Copilot's own config are only shown.
enum McpConfig {
    static let url = URL(fileURLWithPath: Prefs.support + "/mcp.json")

    /// Raw JSON per server, so fields the dashboard doesn't edit (env, headers…) survive a save.
    static func load() -> [String: [String: Any]] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json["mcpServers"] as? [String: [String: Any]] ?? [:]
    }

    static func save(_ servers: [String: [String: Any]]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: ["mcpServers": servers], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}

/// Menu bar › Cruscotto MCP: what the running agent sees, plus Jarvis's own servers to add/remove.
struct McpDashboard: View {
    let app: AppState
    @State private var selection: String?
    @State private var config = McpConfig.load()
    @State private var adding = false
    @State private var saveError: String?

    /// Agent's view first; Jarvis servers it didn't load (bad command, just added) still show up.
    private var rows: [McpServer] {
        let seen = Set(app.mcpServers.map(\.name))
        let missing = config.keys.filter { !seen.contains($0) }.sorted()
            .map { McpServer(name: $0, status: "not-loaded", error: nil, source: "jarvis", tools: nil) }
        return app.mcpServers + missing
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Server") {
                    ForEach(rows) { s in
                        ServerRow(server: s, owned: config[s.name] != nil).tag(s.name)
                    }
                }
                Section { Label("Log di Jarvis", systemImage: "text.alignleft").tag(Self.logTag) }
            }
            .overlay {
                if app.mcpUpdated == nil { ProgressView("Chiedo lo stato all'agente…") }
                else if rows.isEmpty {
                    ContentUnavailableView {
                        Label("Nessun server MCP", systemImage: "puzzlepiece.extension")
                    } description: {
                        Text("Aggiungine uno con +: funziona sia con Claude sia con Copilot.")
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if selection == Self.logTag {
                LogTail()
            } else if let s = rows.first(where: { $0.name == selection }) {
                ServerDetail(server: s, config: config[s.name], app: app, remove: { remove(s.name) })
            } else {
                ContentUnavailableView("Scegli un server", systemImage: "sidebar.left",
                                       description: Text("Stato, tool e configurazione compaiono qui."))
            }
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
        .sheet(isPresented: $adding) { AddServerSheet { name, entry in add(name, entry) } }
        .alert("Non riesco a salvare mcp.json", isPresented: .constant(saveError != nil)) {
            Button("OK") { saveError = nil }
        } message: { Text(saveError ?? "") }
        .onAppear { config = McpConfig.load(); app.refreshMcp() }
    }

    private static let logTag = "__log__"

    private var summary: String {
        let up = rows.filter { $0.status == "connected" }.count
        return "\(up) di \(rows.count) connessi"
    }

    private func add(_ name: String, _ entry: [String: Any]) {
        var next = config
        next[name] = entry
        persist(next)
        selection = name
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
    let onAdd: (String, [String: Any]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind = "stdio"
    @State private var command = ""
    @State private var args = ""
    @State private var url = ""

    private var nameError: String? {
        name.isEmpty || name.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
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
                Button { load() } label: { Label("Ricarica log", systemImage: "arrow.down.doc") }
            }
            ToolbarItem {
                Button { NSWorkspace.shared.open(Log.dir) } label: { Label("Apri cartella log", systemImage: "folder") }
            }
        }
        .overlay { if lines.isEmpty { ContentUnavailableView("Log vuoto", systemImage: "text.alignleft") } }
        .task { load() }
    }

    private func load() {
        let text = (try? String(contentsOf: Log.url, encoding: .utf8)) ?? ""
        lines = Array(text.split(separator: "\n").suffix(200).map(String.init))
    }
}
