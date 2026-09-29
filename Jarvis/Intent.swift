import Foundation

/// What a dictated message means. Only Jarvis's own controls are caught here;
/// everything else goes to Claude, which picks the vault skill itself. Pure, so Tests/ can test it.
enum Intent: Equatable {
    case agent(String)          // text sent to the agent as is
    case stop, repeatLast, cancel, clear
    case yes, no                // answers to a need_confirmation
    case clipboard(ingest: Bool, question: String)
    case screen(String)         // "cosa vedi sullo schermo": screenshot + context of the app Jarvis was called from
    case front(String)          // "riassumi questa pagina": that app's window, document and selection (Accessibility)
    case quick(String)          // "domanda veloce …": Apple's on-device model answers, the agent isn't involved

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
        if let p = ["domanda veloce", "al volo"].first(where: s.hasPrefix) {
            return .quick(String(t.dropFirst(p.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,.:")))
        }
        // ponytail: fixed phrases, not "questo" alone: "questa settimana" is about the vault, not the screen
        if ["schermo", "cosa vedi", "cosa vedo"].contains(where: s.contains) { return .screen(t) }
        if ["questa pagina", "questo file", "questo documento", "questa mail", "questa email", "questo testo",
            "questa finestra", "selezionato", "selezionata", "selezione"].contains(where: s.contains) { return .front(t) }
        return .agent(t)
    }

    /// jarvis://ask?q=… (or plain jarvis://): text for the input field. Nil if it isn't a Jarvis link.
    static func prefill(from url: URL) -> String? {
        guard url.scheme == "jarvis" else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value ?? ""
    }
}
