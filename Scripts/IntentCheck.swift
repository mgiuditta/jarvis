// Run: swiftc Jarvis/Intent.swift Scripts/IntentCheck.swift -o /tmp/intentcheck && /tmp/intentcheck
@main struct IntentCheck {
    static func main() {
        let cases: [(String, Intent)] = [
            ("Ingesta il PDF sul checkout", .agent("/ingest il PDF sul checkout")),
            ("Jarvis, prepara la giornata.", .agent("/prep-day")),
            ("chiudi la giornata", .agent("/close-day")),
            ("Decisione: usiamo Spartacus 2211", .agent("/decision usiamo Spartacus 2211")),
            ("Sincronizza i ticket della release R.4", .agent("/pull-tickets della release R.4")),
            ("sincronizza le MR", .agent("/pull-mrs")),
            ("sincronizza i messaggi", .unsupported("Non ho ancora una skill per i messaggi.")),
            ("Settimana", .agent("/weekly")),
            ("Cosa ho fatto questa settimana?", .agent("Cosa ho fatto questa settimana?")),
            ("Stop.", .stop), ("ripeti", .repeatLast), ("Annulla", .cancel),
            ("Sì.", .yes), ("no", .no),
            ("Ingesta la clipboard", .clipboard(ingest: true, question: "Ingesta la clipboard")),
            ("riassumi quello che ho copiato", .clipboard(ingest: false, question: "riassumi quello che ho copiato")),
            ("Chi è Anna Rossi?", .agent("Chi è Anna Rossi?")),
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
