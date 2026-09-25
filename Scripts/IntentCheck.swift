// Run: swiftc Jarvis/Intent.swift Scripts/IntentCheck.swift -o /tmp/intentcheck && /tmp/intentcheck
@main struct IntentCheck {
    static func main() {
        let cases: [(String, Intent)] = [
            // Commands in plain words go to Claude, which picks the skill.
            ("Jarvis, prepara la giornata.", .agent("prepara la giornata")),
            ("sincronizza i messaggi", .agent("sincronizza i messaggi")),
            ("aggiorna la nota di Mario sul ticket BEN-12", .agent("aggiorna la nota di Mario sul ticket BEN-12")),
            ("Cosa ho fatto questa settimana?", .agent("Cosa ho fatto questa settimana?")),
            ("/ingest 00-Inbox/a.pdf", .agent("/ingest 00-Inbox/a.pdf")),
            ("Stop.", .stop), ("ripeti", .repeatLast), ("Annulla", .cancel),
            ("Sì.", .yes), ("no", .no), ("Stop, ma prima dimmi l'ora", .agent("Stop, ma prima dimmi l'ora")),
            ("Ingesta la clipboard", .clipboard(ingest: true, question: "Ingesta la clipboard")),
            ("riassumi quello che ho copiato", .clipboard(ingest: false, question: "riassumi quello che ho copiato")),
        ]
        var failed = 0
        for (input, expected) in cases where Intent.route(input) != expected {
            print("FAIL \(input) -> \(Intent.route(input)) (atteso \(expected))"); failed += 1
        }
        print(failed == 0 ? "ok \(cases.count) casi" : "\(failed) falliti")
        if failed > 0 { exit(1) }
    }
}
import Foundation
