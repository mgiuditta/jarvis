import AppKit

/// Services menu (declared in Info.plist): "Chiedi a Jarvis" on selected text, "Invia a Jarvis" on Finder files.
@MainActor final class ServiceProvider: NSObject {
    private let app: AppState

    init(app: AppState) {
        self.app = app
    }

    /// Files are ingested like a drop on the orb. Text goes in the field, quoted, and waits for what to do with it.
    @objc func sendToJarvis(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let files = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !files.isEmpty { return app.ingest(files: files) }
        guard let text = pboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        // ponytail: newlines flattened, the input field is one line; the selection keeps its layout via "testo selezionato" (FrontContext)
        app.listen(prefill: "\"\(text.split(whereSeparator: \.isNewline).joined(separator: " "))\" ", awaitsReturn: true)
    }
}
