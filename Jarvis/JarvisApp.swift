import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let talk = Self("talk", default: .init(.space, modifiers: [.option]))
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
        app.setOrbVisible = { visible in
            UserDefaults.standard.set(visible, forKey: "orbVisible")
            visible ? panel.orderFrontRegardless() : panel.orderOut(nil)
        }
        if Prefs.orbVisible { panel.orderFrontRegardless() }
        KeyboardShortcuts.onKeyUp(for: .talk) { [app] in
            if !(self.panel?.isVisible ?? false) { app.setOrbVisible?(true) }
            app.hotkey()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        app.agent.stop()
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
            openObsidian(Prefs.vaultPath + "/00-Inbox/daily/\(Date.now.formatted(.iso8601.year().month().day())).md")
        }
        Button(Prefs.orbVisible ? "Nascondi orb" : "Mostra orb") { app.setOrbVisible?(!Prefs.orbVisible) }
        Button("Nuova sessione") { app.newSession() }
        Button("Apri log") { NSWorkspace.shared.open(Log.dir) }
        Divider()
        SettingsLink { Text("Impostazioni…") }.keyboardShortcut(",")
        Button("Esci") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private var statusLine: String {
        switch app.state {
        case .idle: app.modelReady ? "● Pronto" : "○ Carico il modello vocale…"
        case .listening: "● In ascolto"
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
