import Foundation
import Security

/// Text-only log in ~/Library/Logs/Jarvis/jarvis.log, rotated at 5 MB. Audio is never written anywhere.
enum Log {
    static let dir = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Jarvis")
    static let url = dir.appending(path: "jarvis.log")
    private static let queue = DispatchQueue(label: "jarvis.log")

    static func write(_ message: String) {
        let line = "\(Date.now.ISO8601Format()) \(message)\n"
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if let size = try? fm.attributesOfItem(atPath: url.path)[.size] as? Int, size > 5_000_000 {
                let old = dir.appending(path: "jarvis.1.log")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: url, to: old)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else {
                try? line.write(to: url, atomically: true, encoding: .utf8); return
            }
            // throwing API: the old write(_:) raises an ObjC exception (a crash) on a full disk
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        }
    }
}

/// User settings (UserDefaults keys shared with @AppStorage in SettingsView).
enum Prefs {
    private static var d: UserDefaults { .standard }
    static let home = NSHomeDirectory()

    static var vaultPath: String { d.string(forKey: "vaultPath").nonEmpty ?? home + "/Dev/sbu-brain" }
    static var nodePath: String { d.string(forKey: "nodePath").nonEmpty ?? defaultNode() }
    static var claudePath: String { d.string(forKey: "claudePath").nonEmpty ?? home + "/.local/bin/claude" }
    static var copilotPath: String { d.string(forKey: "copilotPath").nonEmpty ?? "/opt/homebrew/bin/copilot" }
    static var backend: String { d.string(forKey: "backend").nonEmpty ?? "claude" }  // "claude" | "copilot"
    static var isCopilot: Bool { backend == "copilot" }
    /// The sbu-brain layout (00-Inbox, daily, vault skills). Any other folder gets the generic Jarvis.
    static var isVault: Bool { FileManager.default.fileExists(atPath: vaultPath + "/00-Inbox") }
    static let support = home + "/Library/Application Support/Jarvis"
    static var sessionFile: String { support + (isCopilot ? "/copilot-session.json" : "/session.json") }
    static var orbHex: String { d.string(forKey: "orbColor").nonEmpty ?? "#9B5CFF" }
    static var muted: Bool { d.bool(forKey: "muted") }
    static var voiceID: String? { d.string(forKey: "voiceID").nonEmpty }
    static var speechRate: Double { d.object(forKey: "speechRate") as? Double ?? 0.5 }
    static var orbVisible: Bool { d.object(forKey: "orbVisible") as? Bool ?? true }
    static var orbOnlyWhenActive: Bool { d.bool(forKey: "orbOnlyWhenActive") }
    /// "wispr" (Wispr Flow types into the field) | "jarvis" (built-in Dictation).
    static var dictation: String { d.string(forKey: "dictation").nonEmpty ?? "wispr" }
    /// First-run setup done. Whoever already chose a folder before onboarding existed counts as done.
    static var onboarded: Bool {
        get { d.bool(forKey: "onboarded") || d.string(forKey: "vaultPath").nonEmpty != nil }
        set { d.set(newValue, forKey: "onboarded") }
    }

    /// Bundle id moved from com.mgiuditta.jarvis: bring the old settings (paths, hotkeys, orb) over once.
    static func migrate() {
        let old = "com.mgiuditta.jarvis"
        guard Bundle.main.bundleIdentifier != old, !d.bool(forKey: "migrated"),
              let prev = d.persistentDomain(forName: old) else { return }
        for (k, v) in prev where d.object(forKey: k) == nil { d.set(v, forKey: k) }
        d.set(true, forKey: "migrated")
    }

    /// Latest nvm node, so a `nvm install` doesn't break Jarvis unless a path is set explicitly.
    static func defaultNode() -> String {
        let nvm = home + "/.nvm/versions/node"
        let latest = (try? FileManager.default.contentsOfDirectory(atPath: nvm))?
            .sorted { $0.compare($1, options: .numeric) == .orderedAscending }.last
        return latest.map { "\(nvm)/\($0)/bin/node" } ?? "/opt/homebrew/bin/node"
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? { self?.isEmpty == false ? self : nil }
}

/// Optional Anthropic API key. Without it the agent uses the Claude Code login (subscription).
enum Keychain {
    nonisolated(unsafe) private static let base: [String: Any] = [  // immutable, only read
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.mgiuditta.jarvis",
        kSecAttrAccount as String: "anthropic-api-key",
    ]

    static var apiKey: String? {
        var query = base
        query[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Replaces the key (nil/empty = remove). False if the Keychain refused: the caller tells the user.
    @discardableResult static func setApiKey(_ v: String?) -> Bool {
        SecItemDelete(base as CFDictionary)
        guard let v, !v.isEmpty else { return true }
        var item = base
        item[kSecValueData as String] = Data(v.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess { Log.write("keychain: SecItemAdd \(status)") }
        return status == errSecSuccess
    }
}

/// Jarvis's own MCP servers: ~/Library/Application Support/Jarvis/mcp.json, same shape as a .mcp.json.
/// Both agents read it (JARVIS_MCP); servers from Claude/Copilot's own config are only shown.
enum McpConfig {
    static let url = URL(fileURLWithPath: Prefs.support + "/mcp.json")

    /// Raw JSON per server, so fields the dashboard doesn't edit (env, headers…) survive a save.
    static func load(from url: URL = url) -> [String: [String: Any]] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json["mcpServers"] as? [String: [String: Any]] ?? [:]
    }

    static func save(_ servers: [String: [String: Any]], to url: URL = url) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: ["mcpServers": servers], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
