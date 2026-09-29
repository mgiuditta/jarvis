import AppIntents
import SwiftUI
@preconcurrency import KeyboardShortcuts  // Name isn't Sendable yet

extension KeyboardShortcuts.Name {
    static let talk = Self("talk", default: .init(.space, modifiers: [.option]))
    static let toggleOrb = Self("toggleOrb", default: .init(.space, modifiers: [.option, .shift]))
}

/// Current binding as shown in menus ("⌥Space"), since both shortcuts can be changed in Settings.
func shortcutLabel(_ name: KeyboardShortcuts.Name) -> String {
    KeyboardShortcuts.getShortcut(for: name).map { "  \($0)" } ?? ""
}

@main
struct JarvisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(app: delegate.app)
        } label: {
            MenuBarIcon(app: delegate.app)  // own view: only it re-renders on state changes, not the scenes
        }
        Settings { SettingsView(app: delegate.app) }
        Window("Cruscotto", id: "dashboard") { Dashboard(app: delegate.app) }
            .handlesExternalEvents(matching: [])  // jarvis:// links go to the delegate, they never open a window
            .defaultSize(width: 820, height: 600)
            .defaultLaunchBehavior(.suppressed)  // a menu bar agent never opens windows at launch/login
            .restorationBehavior(.disabled)
        Window("Benvenuto in Jarvis", id: "onboarding") { OnboardingView(app: delegate.app) }
            .windowResizability(.contentSize)
            .handlesExternalEvents(matching: [])
            .defaultLaunchBehavior(.suppressed)  // opened by MenuBarIcon on first run only
            .restorationBehavior(.disabled)
    }
}

struct MenuBarIcon: View {
    let app: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Label("Jarvis", systemImage: app.state.symbol)
            .task {
                // The orb's right-click menu lives in a plain NSHostingView, outside any scene:
                // openWindow/SettingsLink do nothing there, so it goes through these.
                app.openDashboard = { NSApp.activate(); openWindow(id: "dashboard") }
                app.openSettings = { NSApp.activate(); openSettings() }
                app.openOnboarding = { NSApp.activate(); openWindow(id: "onboarding") }
                if !Prefs.onboarded { app.openOnboarding?() }
            }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let app: AppState
    private var panel: OverlayPanel?
    private var services: ServiceProvider?

    override init() {
        Prefs.migrate()  // before AppState starts the agent with those settings
        let app = AppState()
        self.app = app
        AppDependencyManager.shared.add(dependency: app)  // @Dependency in AskJarvisIntent
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("Jarvis avviato")
        let panel = OverlayPanel(app: app)
        self.panel = panel
        app.showOrb = { visible in visible ? panel.orderFrontRegardless() : panel.orderOut(nil) }
        app.activate = { NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil) }  // cooperative activate() can be refused from a hotkey
        app.setOrb(Prefs.orbVisible && !Prefs.orbOnlyWhenActive)
        KeyboardShortcuts.onKeyUp(for: .talk) { [app] in app.hotkey() }
        KeyboardShortcuts.onKeyUp(for: .toggleOrb) { [app] in app.setOrb(!app.orbShown, remember: true) }
        Task { [app] in StatusItemDrop.install(app: app) }  // next main-actor turn: the status item exists by then
        let services = ServiceProvider(app: app)
        self.services = services
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
    }

    /// jarvis://ask?q=… from Raycast, Alfred, a note, a web page: the text waits in the field for ⏎.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let prefill = Intent.prefill(from: url) else { continue }
            app.listen(prefill: prefill, awaitsReturn: !prefill.isEmpty)
        }
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
    @AppStorage("vaultPath") private var vaultPath = ""  // observed: vault items follow a folder change

    var body: some View {
        Text(statusLine)
        Button("Parla" + shortcutLabel(.talk)) { app.hotkey() }
        Divider()
        if !app.recent.isEmpty {
            Section("Recenti") {
                ForEach(app.recent) { r in Button(r.label) { app.ask(r.command, label: r.label) } }
            }
            Divider()
        }
        if FileManager.default.fileExists(atPath: (vaultPath.isEmpty ? Prefs.vaultPath : vaultPath) + "/00-Inbox") {  // = Prefs.isVault, observed
            Button("Prepara la giornata") { app.ask("/prep-day") }
            Button("Chiudi la giornata") { app.ask("/close-day") }
            Button("Settimana") { app.ask("/weekly") }
            Button("Sincronizza ticket") { app.ask("/pull-tickets") }
            Button("Sincronizza MR") { app.ask("/pull-mrs") }
            Divider()
            Button("Apri vault in Obsidian") { openObsidian(Prefs.vaultPath) }
            Button("Apri la daily di oggi") {
                openObsidian(todayDaily)
            }
        }
        if !skills.isEmpty {
            Menu("Skill") {
                ForEach(skills, id: \.self) { s in Button(s) { app.ask("/" + s) } }
            }
        }
        Button("Cruscotto…") { app.openDashboard?() }
        Button((app.orbShown ? "Nascondi orb" : "Mostra orb") + shortcutLabel(.toggleOrb)) { app.setOrb(!app.orbShown, remember: true) }
        Picker("Posizione orb", selection: Binding(get: { app.zone }, set: { app.placeOrb?($0) })) {
            ForEach(OrbZone.all, id: \.self) { Text($0.name).tag($0) }
        }
        Button("Apri la sessione in Terminale") { Terminal.resumeSession() }
            .help("Stessa conversazione di Jarvis: non usarli tutti e due nello stesso momento")
        Button("Nuova sessione") { app.newSession() }
        Button("Apri log") { NSWorkspace.shared.open(Log.dir) }
        Divider()
        Button("Configurazione guidata…") { app.openOnboarding?() }
        Button("Impostazioni…") { app.openSettings?() }.keyboardShortcut(",")  // activates: an accessory app opens Settings behind
        Button("Esci") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    /// The vault's own skills (.claude/skills/<name>/SKILL.md): read by both Claude and Copilot, unlike app.commands.
    private var skills: [String] {
        let dir = URL(fileURLWithPath: vaultPath.isEmpty ? Prefs.vaultPath : vaultPath).appending(path: ".claude/skills")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { FileManager.default.fileExists(atPath: dir.appending(path: "\($0)/SKILL.md").path) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var statusLine: String {
        "● " + app.state.label + (app.state == .error ? ": \(app.status)" : "")
    }
}

func openObsidian(_ path: String) {
    let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?/"))) ?? path
    if let url = URL(string: "obsidian://open?path=\(encoded)") { NSWorkspace.shared.open(url) }
}

var todayDaily: String {
    Prefs.vaultPath + "/00-Inbox/daily/\(Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())).md"
}

/// Opens today's Jarvis session in Terminal via a .command file (no Automation permission needed).
enum Terminal {
    static func resumeSession() {
        let support = URL(fileURLWithPath: Prefs.support)
        struct Saved: Decodable { let id: String }
        let saved = (try? Data(contentsOf: URL(fileURLWithPath: Prefs.sessionFile))).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let resume = saved.map { " --resume " + q($0.id) } ?? ""
        let script = support.appending(path: "resume.command")
        do {
            try "#!/bin/zsh\ncd \(q(Prefs.vaultPath)) && exec \(q(Prefs.isCopilot ? Prefs.copilotPath : Prefs.claudePath))\(resume)\n".write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
        } catch {
            Log.write("apri in Terminale: \(error)")
        }
    }
}
