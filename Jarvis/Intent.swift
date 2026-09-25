import Foundation

/// What a spoken utterance means. Pure, so Scripts/IntentCheck.swift can test it.
enum Intent: Equatable {
    case agent(String)          // text sent to the agent (slash command or free question)
    case stop, repeatLast, cancel
    case yes, no                // answers to a need_confirmation
    case clipboard(ingest: Bool, question: String)
    case unsupported(String)    // spoken back as is

    static func route(_ raw: String) -> Intent {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["hey jarvis", "jarvis"] where t.lowercased().hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,.:"))
        }
        let s = t.lowercased().folding(options: .diacriticInsensitive, locale: .init(identifier: "it"))
            .trimmingCharacters(in: CharacterSet(charactersIn: " .!?,"))
        // Everything after the first word/colon, keeping the user's casing.
        func rest(after keyword: String) -> String {
            guard let r = t.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive]) else { return "" }
            return t[r.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " :,."))
        }

        switch s {
        case "stop", "basta", "fermati", "zitto": return .stop
        case "ripeti", "ripeti per favore", "puoi ripetere": return .repeatLast
        case "annulla", "lascia perdere", "annulla tutto": return .cancel
        case "si", "sì", "ok", "conferma", "confermo", "vai", "procedi", "certo": return .yes
        case "no", "non farlo", "nega", "rifiuta": return .no
        default: break
        }
        let mentionsClipboard = s.contains("clipboard") || s.contains("appunti") || s.contains("ho copiato")
        if mentionsClipboard && (s.hasPrefix("ingest") || s.contains("salva")) { return .clipboard(ingest: true, question: t) }
        if mentionsClipboard { return .clipboard(ingest: false, question: t) }
        if s.hasPrefix("ingest") { return .agent("/ingest " + rest(after: s.hasPrefix("ingesta") ? "ingesta" : "ingest")) }
        if s.contains("prepara la giornata") { return .agent("/prep-day") }
        if s.contains("chiudi la giornata") { return .agent("/close-day") }
        if s.hasPrefix("decisione") { return .agent("/decision " + rest(after: "decisione")) }
        if s.contains("sincronizza") || s.contains("aggiorna") {
            if s.contains("ticket") { return .agent("/pull-tickets " + rest(after: "ticket")) }
            if s.contains(" mr") || s.contains("merge request") { return .agent("/pull-mrs") }
            if s.contains("messaggi") { return .unsupported("Non ho ancora una skill per i messaggi.") }
        }
        // ponytail: "settimana" only as a command, so "cosa ho fatto questa settimana?" stays a question
        if s == "settimana" || s.hasPrefix("fai la weekly") || s.contains("chiudi la settimana") || s == "weekly" { return .agent("/weekly") }
        return .agent(t)
    }
}
