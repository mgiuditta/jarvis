import Foundation

/// What a dictated message means. Only Jarvis's own controls are caught here;
/// everything else goes to Claude, which picks the vault skill itself. Pure, so Tests/ can test it.
enum Intent: Equatable {
    case agent(String)          // text sent to the agent as is
    case stop, repeatLast, cancel, clear
    case yes, no                // answers to a need_confirmation
    case clipboard(ingest: Bool, question: String)

    static func route(_ raw: String) -> Intent {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["hey jarvis", "jarvis"] where t.lowercased().hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,.:"))
        }
        let s = t.lowercased().folding(options: .diacriticInsensitive, locale: .init(identifier: "it"))
            .trimmingCharacters(in: CharacterSet(charactersIn: " .!?,"))

        switch s {
        case "/clear", "nuova sessione", "ricomincia": return .clear
        case "stop", "basta", "fermati", "zitto": return .stop
        case "ripeti", "ripeti per favore", "puoi ripetere": return .repeatLast
        case "annulla", "lascia perdere", "annulla tutto": return .cancel
        case "si", "ok", "conferma", "confermo", "vai", "procedi", "certo": return .yes
        case "no", "non farlo", "nega", "rifiuta": return .no
        default: break
        }
        // The clipboard lives on this Mac, so Jarvis reads it before Claude sees the request.
        let mentionsClipboard = s.contains("clipboard") || s.contains("appunti") || s.contains("ho copiato")
        if mentionsClipboard && (s.hasPrefix("ingest") || s.contains("salva")) { return .clipboard(ingest: true, question: t) }
        if mentionsClipboard { return .clipboard(ingest: false, question: t) }
        return .agent(t)
    }
}
