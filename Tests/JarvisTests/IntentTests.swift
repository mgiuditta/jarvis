import Foundation
import Testing
@testable import JarvisCore

struct IntentTests {
    @Test(arguments: [
        // Commands in plain words go to Claude, which picks the skill.
        ("Jarvis, prepara la giornata.", Intent.agent("prepara la giornata")),
        ("sincronizza i messaggi", .agent("sincronizza i messaggi")),
        ("aggiorna la nota di Mario sul ticket BEN-12", .agent("aggiorna la nota di Mario sul ticket BEN-12")),
        ("Cosa ho fatto questa settimana?", .agent("Cosa ho fatto questa settimana?")),
        ("/ingest 00-Inbox/a.pdf", .agent("/ingest 00-Inbox/a.pdf")),
        ("Stop, ma prima dimmi l'ora", .agent("Stop, ma prima dimmi l'ora")),
        ("/clear", .clear), ("Nuova sessione.", .clear), ("Stop.", .stop), ("ripeti", .repeatLast), ("Annulla", .cancel),
        ("Sì.", .yes), ("no", .no),
        ("Ingesta la clipboard", .clipboard(ingest: true, question: "Ingesta la clipboard")),
        ("riassumi quello che ho copiato", .clipboard(ingest: false, question: "riassumi quello che ho copiato")),
        ("Domanda veloce: quanto fa 7 per 8?", .quick("quanto fa 7 per 8?")),
        ("Jarvis, cosa vedi sullo schermo?", .screen("cosa vedi sullo schermo?")),
        ("Riassumi questa pagina", .front("Riassumi questa pagina")),
        ("traduci il testo selezionato", .front("traduci il testo selezionato")),
    ])
    func routes(input: String, expected: Intent) {
        #expect(Intent.route(input) == expected)
    }

    @Test(arguments: [
        ("jarvis://ask?q=riassumi%20la%20daily", "riassumi la daily"),
        ("jarvis://listen", ""),
        ("https://example.com/?q=x", nil),
    ])
    func prefill(url: String, expected: String?) {
        #expect(Intent.prefill(from: URL(string: url)!) == expected)
    }
}
