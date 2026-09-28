import Testing
@testable import JarvisCore

@MainActor struct SpeakerTests {
    @Test(arguments: [
        ("Fatto.\n\nDettagli sotto.", "Fatto."),
        ("Una riga sola", "Una riga sola"),
        ("", ""),
        ("\n\nDopo", ""),
    ])
    func spokenPartIsFirstParagraph(text: String, expected: String) {
        #expect(Speaker.spokenPart(of: text) == expected)
    }

    @Test(arguments: [
        ("Vedi [[Mario Rossi]].", "Vedi Mario Rossi."),
        ("Vedi [[daily/2026-09-28|oggi]].", "Vedi oggi."),
        ("Apri [il sito](https://example.com).", "Apri il sito."),
        ("**Grassetto** e `codice`", "Grassetto e codice"),
        ("# Titolo", "Titolo"),
        ("> citazione", "citazione"),
    ])
    func plainStripsMarkdown(markdown: String, expected: String) {
        #expect(Speaker.plain(markdown) == expected)
    }
}
