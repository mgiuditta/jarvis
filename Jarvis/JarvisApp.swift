import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let talk = Self("talk", default: .init(.space, modifiers: [.option]))
    static let toggleOrb = Self("toggleOrb", default: .init(.space, modifiers: [.option, .shift]))
}

@main
struct JarvisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(app: delegate.app)
        } label: {
            Image(systemName: icon(delegate.app.state))
        }
        Settings { SettingsView(app: delegate.app) }
    }

    private func icon(_ s: OrbState) -> String {
        switch s {
        case .idle: "circle.circle"
        case .listening: "waveform.circle.fill"
        case .thinking: "ellipsis.circle.fill"
        case .speaking: "speaker.wave.2.circle.fill"
        case .confirm: "questionmark.circle.fill"
        case .error: "exclamationmark.circle.fill"
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let app = AppState()
    private var panel: OverlayPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("Jarvis avviato")
        let panel = OverlayPanel(app: app)
        self.panel = panel
        app.showOrb = { visible in visible ? panel.orderFrontRegardless() : panel.orderOut(nil) }
        app.activate = { NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil) }  // cooperative activate() can be refused from a hotkey
        app.setOrb(Prefs.orbVisible && !Prefs.orbOnlyWhenActive)
        KeyboardShortcuts.onKeyUp(for: .talk) { [app] in app.hotkey() }
        KeyboardShortcuts.onKeyUp(for: .toggleOrb) { [app] in app.setOrb(!app.orbShown, remember: true) }
        DispatchQueue.main.async { [app] in StatusItemDrop.install(app: app) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        app.agent.stop()
    }
}

/// MenuBarExtra has no drop API: overlay the status item button with a view that only accepts file drags.
final class StatusItemDrop: NSView {
    private let app: AppState

    static func install(app: AppState) {
        // ponytail: finds the button by window class name, breaks silently if AppKit renames it
        guard let button = NSApp.windows.first(where: { $0.className.contains("NSStatusBarWindow") })?.contentView
                .flatMap({ $0 as? NSButton ?? $0.subviews.compactMap { $0 as? NSButton }.first }) else {
            return Log.write("drop menu bar: bottone non trovato")
        }
        let drop = StatusItemDrop(app: app)
        drop.frame = button.bounds
        drop.autoresizingMask = [.width, .height]
        button.addSubview(drop)
    }

    init(app: AppState) {
        self.app = app
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }  // clicks go to the button

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        (superview as? NSButton)?.highlight(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { (superview as? NSButton)?.highlight(false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        (superview as? NSButton)?.highlight(false)
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        app.ingest(files: urls)
        return true
    }
}

struct MenuContent: View {
    let app: AppState

    var body: some View {
        Text(statusLine)
        Button("Parla  ⌥Space") { app.hotkey() }
        Divider()
        if !app.recent.isEmpty {
            Section("Recenti") {
                ForEach(app.recent) { r in Button(r.label) { app.ask(r.command, label: r.label) } }
            }
            Divider()
        }
        Button("Prepara la giornata") { app.ask("/prep-day") }
        Button("Chiudi la giornata") { app.ask("/close-day") }
        Button("Settimana") { app.ask("/weekly") }
        Button("Sincronizza ticket") { app.ask("/pull-tickets") }
        Button("Sincronizza MR") { app.ask("/pull-mrs") }
        Divider()
        Button("Apri vault in Obsidian") { openObsidian(Prefs.vaultPath) }
        Button("Apri la daily di oggi") {
            openObsidian(Prefs.vaultPath + "/00-Inbox/daily/\(Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())).md")
        }
        Button(app.orbShown ? "Nascondi orb  ⌥⇧Space" : "Mostra orb  ⌥⇧Space") { app.setOrb(!app.orbShown, remember: true) }
        Button("Apri la sessione in Terminale") { Terminal.resumeSession() }
            .help("Stessa conversazione di Jarvis: non usarli tutti e due nello stesso momento")
        Button("Nuova sessione") { app.newSession() }
        Button("Apri log") { NSWorkspace.shared.open(Log.dir) }
        Divider()
        SettingsLink { Text("Impostazioni…") }.keyboardShortcut(",")
        Button("Esci") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private var statusLine: String {
        switch app.state {
        case .idle: "● Pronto"
        case .listening: "● Aspetto la dettatura"
        case .thinking: "● Sta pensando"
        case .speaking: "● Sta parlando"
        case .confirm: "● Attende conferma"
        case .error: "● Errore: \(app.status)"
        }
    }

    private func openObsidian(_ path: String) {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?/"))) ?? path
        if let url = URL(string: "obsidian://open?path=\(encoded)") { NSWorkspace.shared.open(url) }
    }
}

/// Opens today's Jarvis session in Terminal via a .command file (no Automation permission needed).
enum Terminal {
    static func resumeSession() {
        let support = URL(fileURLWithPath: Prefs.home + "/Library/Application Support/Jarvis")
        struct Saved: Decodable { let id: String }
        let saved = (try? Data(contentsOf: support.appending(path: "session.json"))).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let resume = saved.map { " --resume " + q($0.id) } ?? ""
        let script = support.appending(path: "resume.command")
        do {
            try "#!/bin/zsh\ncd \(q(Prefs.vaultPath)) && exec \(q(Prefs.claudePath))\(resume)\n".write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
        } catch {
            Log.write("apri in Terminale: \(error)")
        }
    }
}
