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
    ])
    func routes(input: String, expected: Intent) {
        #expect(Intent.route(input) == expected)
    }
}
