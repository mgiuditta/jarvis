import AppIntents

/// "Chiedi a Jarvis" in Shortcuts, Spotlight and Siri. Returns the answer, so a shortcut can pass it on.
struct AskJarvisIntent: AppIntent {
    static let title: LocalizedStringResource = "Chiedi a Jarvis"
    static let description = IntentDescription("Manda una richiesta all'agente di Jarvis e restituisce la risposta.")

    @Parameter(title: "Richiesta", requestValueDialog: "Cosa chiedo a Jarvis?")
    var request: String

    @Dependency private var app: AppState

    @MainActor func perform() async throws -> some ReturnsValue<String> {
        .result(value: try await app.reply(to: request))
    }
}

struct JarvisShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskJarvisIntent(), phrases: ["Chiedi a \(.applicationName)", "Domanda a \(.applicationName)"],
                    shortTitle: "Chiedi a Jarvis", systemImageName: "sparkles")
    }
}
