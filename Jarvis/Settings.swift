import SwiftUI
import AVFoundation
import KeyboardShortcuts
import ServiceManagement
import TTSKit

struct SettingsView: View {
    let app: AppState
    @AppStorage("orbHex") private var orbHex = "#3FD8FF"
    @AppStorage("orbOnlyWhenActive") private var orbOnlyWhenActive = false
    @AppStorage("voiceID") private var voiceID = ""
    @AppStorage("speechRate") private var speechRate = 0.5
    @AppStorage("vaultPath") private var vaultPath = ""
    @AppStorage("nodePath") private var nodePath = ""
    @AppStorage("claudePath") private var claudePath = ""
    @State private var apiKey = Keychain.apiKey ?? ""
    @State private var login = SMAppService.mainApp.status == .enabled

    private let voices = AVSpeechSynthesisVoice.speechVoices()
        .filter { $0.language == "it-IT" }
        .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }

    var body: some View {
        Form {
            Section("Attivazione") {
                KeyboardShortcuts.Recorder("Parla con Jarvis", name: .talk)
                Toggle("Avvia al login", isOn: $login).onChange(of: login) { _, on in LoginItem.set(on) }
            }
            Section("Voce") {
                Picker("Voce", selection: $voiceID) {
                    Text("Eric · neurale (consigliata)").tag("")
                    ForEach(Qwen3Speaker.allCases.filter { $0 != .eric }, id: \.self) { v in
                        Text("\(v.rawValue.capitalized) · neurale").tag("tts:\(v.rawValue)")
                    }
                    Divider()
                    ForEach(voices, id: \.identifier) { v in Text("\(v.name) · sistema \(quality(v))").tag(v.identifier) }
                }
                Slider(value: $speechRate, in: 0.3...0.7) { Text("Velocità (solo voci di sistema)") }
                Button("Prova") { app.speaker.stop(); app.speaker.say("Ciao, sono Jarvis. Dimmi pure.") }
                Text("Le voci neurali (Qwen3-TTS) girano in locale; al primo avvio il modello si scarica e compila per qualche minuto, intanto parla la voce di sistema.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Orb") {
                ColorPicker("Colore", selection: Binding(get: { Color(hex: orbHex) }, set: { orbHex = $0.hex }), supportsOpacity: false)
                KeyboardShortcuts.Recorder("Mostra / nascondi orb", name: .toggleOrb)
                Toggle("Mostra l'orb solo quando parlo con Jarvis", isOn: $orbOnlyWhenActive)
            }
            Section("Vault e runtime") {
                HStack {
                    TextField("Vault", text: $vaultPath, prompt: Text(Prefs.vaultPath))
                    Button("Scegli…") { chooseVault() }
                }
                TextField("Node", text: $nodePath, prompt: Text(Prefs.defaultNode()))
                TextField("Claude Code", text: $claudePath, prompt: Text(Prefs.home + "/.local/bin/claude"))
                SecureField("API key Anthropic (opzionale)", text: $apiKey, prompt: Text("vuota = login di Claude Code"))
                Button("Salva e riavvia l'agente") {
                    Keychain.apiKey = apiKey.isEmpty ? nil : apiKey
                    app.restartAgent()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding(.vertical, 8)
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

extension Color {
    init(hex: String) {
        let c = OrbRenderer.rgb(hex: hex)
        self.init(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
    }

    var hex: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#3FD8FF" }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}
