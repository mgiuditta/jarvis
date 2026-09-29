import SwiftUI
import AVFoundation
import Speech

/// First run: engine (Claude / Copilot), dictation (Wispr / built-in), vault (existing / new, built by the agent).
/// Opens by itself until done or skipped; menu › "Configurazione guidata…" reopens it.
struct OnboardingView: View {
    let app: AppState
    @AppStorage("backend") private var backend = "claude"
    @AppStorage("dictation") private var dictation = "wispr"
    @AppStorage("vaultPath") private var vaultPath = ""
    @AppStorage("orbColor") private var orbHex = "#9B5CFF"
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = Step.welcome
    @State private var apiKey = ""
    @State private var recheck = 0            // bumped by "Ricontrolla": the checks below are read in body
    @State private var permissions = Dictation.authorized
    @State private var vaultChoice: VaultChoice?
    @State private var newVault: URL?
    @State private var launchAtLogin = true
    @State private var error: String?

    enum Step: Int, CaseIterable { case welcome, engine, dictation, vault }
    enum VaultChoice { case existing, new }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch step {
                case .welcome: welcome
                case .engine: engine
                case .dictation: dictationStep
                case .vault: vault
                }
            }
            .id(step)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 32)
            Divider()
            footer
        }
        .frame(width: 580, height: 500)
        .tint(Color(hex: orbHex))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: step)
        // Back from Terminal or System Settings: re-read CLIs and permissions without a click.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            recheck += 1
            permissions = Dictation.authorized
        }
        .task {
            apiKey = Keychain.apiKey ?? ""
            // Preselect the engine that is actually installed, unless the user already picked one.
            if UserDefaults.standard.string(forKey: "backend") == nil, !cliFound("claude"), cliFound("copilot") { backend = "copilot" }
            if !vaultPath.isEmpty { vaultChoice = .existing }
        }
    }

    // MARK: frame

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule().fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: s == step ? 22 : 8, height: 8)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Passo \(step.rawValue + 1) di \(Step.allCases.count)")
            Spacer()
            if step != .vault {
                Button("Salta") { finish(skipping: true) }
                    .buttonStyle(.link)
                    .help("Configuri tutto dopo in Impostazioni")
            }
        }
        .padding(.horizontal, 32).padding(.top, 20).padding(.bottom, 16)
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Indietro") { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
                    .keyboardShortcut(.cancelAction)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
            }
            Spacer()
            Button(step == .welcome ? "Inizia" : step == .vault ? "Fine" : "Continua") {
                if let next = Step(rawValue: step.rawValue + 1) { step = next } else { finish(skipping: false) }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(step == .vault && !vaultReady)
        }
        .controlSize(.large)
        .padding(.horizontal, 32).padding(.vertical, 16)
    }

    // MARK: steps

    private var welcome: some View {
        VStack(spacing: 14) {
            OrbView(state: .idle, colorHex: orbHex, levels: app.speaker.levels, hovering: false)
                .frame(width: 150, height: 150)
                .accessibilityHidden(true)
            Text("Ciao, sono Jarvis").font(.largeTitle.bold())
            Text("Parli, io lavoro nel tuo secondo cervello con Claude Code o GitHub Copilot e ti rispondo a voce.\nTre scelte e ci siamo: motore, dettatura, vault.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var engine: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Quale AI uso?", "Jarvis guida la CLI che hai già, con il tuo login.")
            Picker("Motore", selection: $backend) {
                Text("Claude Code").tag("claude")
                Text("GitHub Copilot").tag("copilot")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            let _ = recheck
            let node = FileManager.default.isExecutableFile(atPath: Prefs.defaultNode())
            let cli = cliFound(backend)
            StatusRow(ok: node, text: node ? "Node trovato" : "Node non trovato", command: node ? nil : "brew install node")
            if backend == "claude" {
                StatusRow(ok: cli, text: cli ? "Claude Code trovato" : "Claude Code non trovato",
                          command: cli ? nil : "curl -fsSL https://claude.ai/install.sh | bash")
                Text("Serve il login: nel Terminale `claude`, poi segui le istruzioni. Oppure una API key:")
                    .font(.callout).foregroundStyle(.secondary)
                SecureField("API key Anthropic (opzionale)", text: $apiKey, prompt: Text("vuota = login di Claude Code"))
            } else {
                StatusRow(ok: cli, text: cli ? "Copilot CLI trovata" : "Copilot CLI non trovata",
                          command: cli ? nil : "brew install copilot-cli")
                Text("Serve il login GitHub: nel Terminale `copilot`, poi `/login`.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if !node || !cli {
                Button("Ricontrolla", systemImage: "arrow.clockwise") { recheck += 1 }
                Text("Path diversi da quelli standard? Li imposti dopo in Impostazioni.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var dictationStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Come mi parli?", "Premi ⌥Space, detti, e dopo qualche secondo di silenzio parte da solo.")
            ChoiceCard(icon: "keyboard.badge.waveform", title: "Wispr Flow",
                       detail: wisprInstalled ? "Installato: detta nel campo di Jarvis." : "Non installato. Scaricalo da wisprflow.ai.",
                       selected: dictation == "wispr") { dictation = "wispr" }
            ChoiceCard(icon: "waveform", title: "Dettatura di Jarvis",
                       detail: "Riconoscimento vocale di Apple, sul Mac quando possibile. Nessun'altra app.",
                       selected: dictation == "jarvis") { dictation = "jarvis" }
            if dictation == "jarvis" {
                if permissions {
                    StatusRow(ok: true, text: "Microfono e riconoscimento vocale consentiti")
                } else if let pane = deniedPane {
                    StatusRow(ok: false, text: "Permesso negato: attivalo in Privacy › \(pane == "Privacy_Microphone" ? "Microfono" : "Riconoscimento vocale")")
                    Button("Apri Impostazioni di Sistema") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                    }
                } else {
                    Text("Ascolto solo mentre il campo è aperto, e mai mentre parlo io. L'audio non viene salvato.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Consenti microfono e riconoscimento vocale") {
                        Task { permissions = await Dictation.requestPermissions() }
                    }
                }
            } else if !wisprInstalled {
                Link("Scarica Wispr Flow", destination: URL(string: "https://wisprflow.ai")!)
            }
        }
    }

    private var vault: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Dove lavoro?", "Un vault Obsidian o una cartella qualsiasi: lì leggo e scrivo.")
            ChoiceCard(icon: "folder", title: "Ho già un vault",
                       detail: vaultChoice == .existing && !vaultPath.isEmpty ? existingDetail : "Scegli la cartella.",
                       selected: vaultChoice == .existing) {
                vaultChoice = .existing
                if let url = pickFolder() { vaultPath = url.path }
            }
            ChoiceCard(icon: "sparkles", title: "Creane uno nuovo",
                       detail: newVault.map { "Lo creo in \(($0.path as NSString).abbreviatingWithTildeInPath). Prima ti intervisto a round e ti mostro la mappa." }
                            ?? "Scegli dove. Poi ti intervisto a round e ti mostro la mappa prima di crearlo.",
                       selected: vaultChoice == .new) {
                vaultChoice = .new
                if let url = pickNewFolder() { newVault = url }
            }
            Toggle("Avvia Jarvis al login", isOn: $launchAtLogin)
        }
    }

    // MARK: helpers

    private func title(_ t: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(.title.bold()).accessibilityAddTraits(.isHeader)
            Text(subtitle).foregroundStyle(.secondary)
        }
    }

    private func cliFound(_ backend: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: backend == "copilot" ? Prefs.copilotPath : Prefs.claudePath)
    }

    /// The System Settings pane of the first denied permission, nil if none is denied.
    private var deniedPane: String? {
        let _ = recheck
        if AVCaptureDevice.authorizationStatus(for: .audio) == .denied { return "Privacy_Microphone" }
        if SFSpeechRecognizer.authorizationStatus() == .denied { return "Privacy_SpeechRecognition" }
        return nil
    }

    private var wisprInstalled: Bool { FileManager.default.fileExists(atPath: "/Applications/Wispr Flow.app") }

    private var existingDetail: String {
        let path = (vaultPath as NSString).abbreviatingWithTildeInPath
        return FileManager.default.fileExists(atPath: vaultPath + "/00-Inbox") ? "\(path) · vault riconosciuto" : "\(path) · cartella generica (niente daily e skill del vault)"
    }

    private var vaultReady: Bool {
        switch vaultChoice {
        case .existing: !vaultPath.isEmpty && FileManager.default.fileExists(atPath: vaultPath)
        case .new: newVault != nil
        case nil: false
        }
    }

    private func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: vaultPath.isEmpty ? Prefs.home : vaultPath)
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func pickNewFolder() -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Jarvis"
        panel.nameFieldLabel = "Nome del vault:"
        panel.prompt = "Crea"
        panel.directoryURL = URL(fileURLWithPath: Prefs.home)
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func finish(skipping: Bool) {
        error = nil
        if !skipping {
            if backend == "claude", !Keychain.setApiKey(apiKey) { return error = "Non riesco a salvare la API key nel Portachiavi." }
            if vaultChoice == .new, let newVault {
                let skill = newVault.appending(path: ".claude/skills/grill-me")
                do {
                    try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
                    try Onboarding.grillSkill.write(to: skill.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
                }
                catch { return self.error = "Non riesco a creare la cartella: \(error.localizedDescription)" }
                vaultPath = newVault.path
            }
            if launchAtLogin { LoginItem.set(true) }
        }
        app.finishOnboarding(newVault: !skipping && vaultChoice == .new)
        dismissWindow()
    }
}

/// ✓ / ✗ with words, never color alone; a missing tool shows the command to copy.
private struct StatusRow: View {
    let ok: Bool
    let text: String
    var command: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(text, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
            if let command {
                HStack {
                    Text(command).font(.callout.monospaced()).textSelection(.enabled)
                    Spacer()
                    Button("Copia", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                    .labelStyle(.iconOnly)
                    .help("Copia il comando")
                }
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

/// One of two mutually exclusive options, as a big clickable card.
private struct ChoiceCard: View {
    let icon: String
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title2).frame(width: 32).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .padding(14)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .background(selected ? AnyShapeStyle(.tint.opacity(0.1)) : AnyShapeStyle(.quaternary.opacity(0.5)), in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: selected ? 2 : 1) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

enum Onboarding {
    /// Written into a new vault before the first prompt, so both engines have it without any plugin (method from mattpocock's grilling).
    static let grillSkill = """
    ---
    name: grill-me
    description: Intervista a round per chiarire un piano, una decisione o come organizzare il vault. Usala quando l'utente dice grigliami, grill-me, intervistami, o quando va disegnato qualcosa su misura per lui.
    ---

    Intervista l'utente finché non avete la stessa idea. Tieni in testa un albero di decisioni: ogni decisione apre quelle che dipendono da lei.

    Lavora a round. La frontiera sono le decisioni i cui prerequisiti sono già decisi: quelle che puoi chiedere adesso senza indovinare risposte che non hai ancora. \
    In ogni round fai tutta la frontiera insieme, numerata, e per ogni domanda dai la tua risposta consigliata. Poi aspetta le risposte.

    Le risposte cambiano l'albero: ricalcola la frontiera e fai il round dopo. Una domanda che dipende da un'altra ancora aperta va nel round successivo, non in questo.

    I fatti li cerchi tu (file, cartelle, strumenti e server MCP disponibili), non chiederli mai all'utente. Le decisioni sono sue: proponile e aspetta.

    Hai finito quando la frontiera è vuota: ogni ramo visitato, niente dato per scontato. Riassumi cosa avete deciso e non agire finché l'utente non conferma.
    """

    /// First prompt in a new vault: the agent grills the user with grill-me, shows the map, builds it only after a yes.
    static func vaultPrompt(engine: String) -> String {
        let uses = engine == "copilot" ? "GitHub Copilot" : "Claude Code"
        return """
        Questa cartella è il mio nuovo secondo cervello e lo costruiamo insieme. Uso \(uses). \
        Usa la skill grill-me (.claude/skills/grill-me/SKILL.md): intervistami a round per disegnare la mappa del vault su misura per me. \
        Non creare nessun file finché non ho approvato la mappa.

        Rami da coprire, ognuno con le domande che ne dipendono:
        - Chi sono: lavoro, ruolo, contesto (dipendente, freelance, studente…), lingua delle note.
        - Storico: ho note da portare dentro (Obsidian, export Notion, Apple Notes, cartelle, niente)? Se sì: dove sono, quanto indietro, tutto o solo l'attivo, archiviate o smistate.
        - Cosa tracciare: progetti, aree, persone, riunioni, decisioni, ticket e merge request, obiettivi, abitudini, apprendimento, altro. Per ognuno scelto: una nota per elemento o dentro la daily, e cosa ci scrivo.
        - Strumenti: ticket, repo, mail, calendario, chat. Controlla tu quali server MCP o CLI ho: solo quelli disponibili diventano skill pull-*.
        - Motore: \(uses) lo so già; chiedimi solo se uso anche l'altro.
        - Routine: come apro e chiudo giornata e settimana, a che ora, cosa voglio nella daily.

        Quando la frontiera è vuota mostrami la mappa: albero delle cartelle, cosa va dove, le skill con una riga ciascuna, le routine. Chiedimi se va bene e correggila finché non dico sì.

        Dopo il sì crea il vault in formato Obsidian: \
        00-Inbox/daily/ (obbligatoria, lì va la nota del giorno AAAA-MM-GG.md), le cartelle numerate della mappa \
        (per esempio 01-Projects, 02-Areas, 06-People, 99-Archive), un CLAUDE.md con le regole del vault e un USER.md con chi sono e le risposte dell'intervista. \
        Se uso anche Copilot, un AGENTS.md che rimanda a CLAUDE.md. \
        Poi crea le skill in .claude/skills/<nome>/SKILL.md (le leggono sia Claude Code sia Copilot), adattate a me: \
        prep-day (prepara la giornata nella daily), close-day (chiude la giornata), ingest (smista un file messo in 00-Inbox), \
        weekly (riepilogo della settimana), decision (registra una decisione), più quelle degli strumenti. Lascia grill-me dov'è. \
        Se c'è storico da importare fallo per ultimo, o crea una skill import se è troppo grosso per una volta. \
        Alla fine dimmi in breve cosa hai creato e come iniziare.
        """
    }
}
