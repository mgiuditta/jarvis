import FoundationModels

/// "domanda veloce …": Apple's on-device model answers in a second, without waking the agent.
enum QuickAnswer {
    /// Nil without Apple Intelligence (macOS 15, turned off, unsupported Mac) or on a model error: the agent answers instead.
    static func reply(_ question: String) async -> String? {
        guard #available(macOS 26, *), SystemLanguageModel.default.isAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
            Sei Jarvis, un assistente. Rispondi in italiano in una o due frasi, senza markdown: la risposta viene letta ad alta voce.
            """)
        do { return try await session.respond(to: question).content }
        catch { Log.write("risposta veloce: \(error)"); return nil }
    }
}
