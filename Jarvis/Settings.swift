import SwiftUI
import AVFoundation
import KeyboardShortcuts
import ServiceManagement

struct SettingsView: View {
    let app: AppState
    @AppStorage("orbColor") private var orbHex = "#9B5CFF"
    @AppStorage("orbOnlyWhenActive") private var orbOnlyWhenActive = false
    @AppStorage("voiceID") private var voiceID = ""
    @AppStorage("speechRate") private var speechRate = 0.5
    @AppStorage("vaultPath") private var vaultPath = ""
    @AppStorage("nodePath") private var nodePath = ""
    @AppStorage("claudePath") private var claudePath = ""
    @AppStorage("copilotPath") private var copilotPath = ""
    @AppStorage("backend") private var backend = "claude"
    @AppStorage("autoSendDelay") private var autoSendDelay = 3.0
    // Loaded in .task, not as initial values: those run every time SwiftUI rebuilds the view.
    @State private var apiKey = ""
    @State private var login = SMAppService.Status.notRegistered
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var orbColor = Color(hex: Prefs.orbHex)
    @State private var keyError = false

    var body: some View {
        Form {
            Section("Attivazione") {
                KeyboardShortcuts.Recorder("Parla con Jarvis", name: .talk)
                Toggle("Avvia al login", isOn: Binding(get: { login == .enabled }, set: { on in
                    LoginItem.set(on)
                    login = SMAppService.mainApp.status  // the real outcome, not what was asked
                    if login == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
                }))
                if login == .requiresApproval {
                    Text("Da approvare in Impostazioni di Sistema › Generali › Elementi login.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Stepper(value: $autoSendDelay, in: 0...10, step: 0.5) {
                    Text(autoSendDelay == 0 ? "Invio automatico: spento (solo ⏎)" : "Invio automatico dopo \(autoSendDelay.formatted()) s di silenzio")
                }
            }
            Section("Voce") {
                Picker("Voce", selection: $voiceID) {
                    Text("Automatica (Luca, se installata)").tag("")
                    ForEach(voices, id: \.identifier) { v in Text("\(v.name) · \(quality(v))").tag(v.identifier) }
                }
                Slider(value: $speechRate, in: 0.3...0.7) { Text("Velocità") } minimumValueLabel: { Text("Lenta") } maximumValueLabel: { Text("Veloce") }
                Button("Prova") { app.speaker.stop(); app.speaker.say("Ciao, sono Jarvis. Dimmi pure.") }
                if !voices.contains(where: { $0.name.hasPrefix("Luca") && $0.quality == .premium }) {
                    Text("Per una voce migliore scarica \"Luca (Premium)\" da Impostazioni di Sistema › Accessibilità › Contenuti letti ad alta voce.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Orb") {
                ColorPicker("Colore", selection: $orbColor, supportsOpacity: false)
                    .onChange(of: orbColor) { _, c in orbHex = c.hex }
                KeyboardShortcuts.Recorder("Mostra / nascondi orb", name: .toggleOrb)
                Toggle("Mostra l'orb solo quando parlo con Jarvis", isOn: $orbOnlyWhenActive)
            }
            Section("Motore e cartella di lavoro") {
                Picker("Motore", selection: $backend) {
                    Text("Claude Code").tag("claude")
                    Text("GitHub Copilot").tag("copilot")
                }
                .pickerStyle(.segmented)
                HStack {
                    TextField("Cartella", text: $vaultPath, prompt: Text(Prefs.vaultPath))
                    Button("Scegli…") { chooseVault() }
                }
                TextField("Node", text: $nodePath, prompt: Text(Prefs.defaultNode()))
                if backend == "copilot" {
                    TextField("Copilot CLI", text: $copilotPath, prompt: Text("/opt/homebrew/bin/copilot"))
                    Text("Serve la Copilot CLI con login GitHub: nel Terminale `copilot`, poi `/login`.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    TextField("Claude Code", text: $claudePath, prompt: Text(Prefs.home + "/.local/bin/claude"))
                    SecureField("API key Anthropic (opzionale)", text: $apiKey, prompt: Text("vuota = login di Claude Code"))
                }
                Button("Salva e riavvia l'agente") {
                    keyError = !Keychain.setApiKey(apiKey)
                    app.restartAgent()
                }
                if keyError {
                    Label("Non riesco a salvare la API key nel Portachiavi: vedi il log.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            Section {
                Text("© 2026 Matteo Giuditta · Licenza MIT").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding(.vertical, 8)
        .task {
            apiKey = Keychain.apiKey ?? ""
            login = SMAppService.mainApp.status
            voices = AVSpeechSynthesisVoice.speechVoices()
                .filter { $0.language == "it-IT" }
                .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
        }
    }

    private func quality(_ v: AVSpeechSynthesisVoice) -> String {
        switch v.quality { case .premium: "Premium"; case .enhanced: "Enhanced"; default: "Base" }
    }

    private func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: Prefs.vaultPath)
        if panel.runModal() == .OK, let url = panel.url { vaultPath = url.path }
    }
}
