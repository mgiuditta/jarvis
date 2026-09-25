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
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        }
    }
}

/// User settings (UserDefaults keys shared with @AppStorage in SettingsView).
enum Prefs {
    private static let d = UserDefaults.standard
    static let home = NSHomeDirectory()

    static var vaultPath: String { d.string(forKey: "vaultPath").nonEmpty ?? home + "/Dev/sbu-brain" }
    static var nodePath: String { d.string(forKey: "nodePath").nonEmpty ?? defaultNode() }
    static var claudePath: String { d.string(forKey: "claudePath").nonEmpty ?? home + "/.local/bin/claude" }
    static var orbHex: String { d.string(forKey: "orbHex").nonEmpty ?? "#3FD8FF" }
    static var voiceID: String? { d.string(forKey: "voiceID").nonEmpty }
    static var speechRate: Double { d.object(forKey: "speechRate") as? Double ?? 0.5 }
    static var orbVisible: Bool { d.object(forKey: "orbVisible") as? Bool ?? true }
    static var orbOnlyWhenActive: Bool { d.bool(forKey: "orbOnlyWhenActive") }

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
    private static let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.mgiuditta.jarvis",
        kSecAttrAccount as String: "anthropic-api-key",
    ]

    static var apiKey: String? {
        get {
            var query = base
            query[kSecReturnData as String] = true
            var out: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            SecItemDelete(base as CFDictionary)
            guard let v = newValue, !v.isEmpty else { return }
            var item = base
            item[kSecValueData as String] = Data(v.utf8)
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
