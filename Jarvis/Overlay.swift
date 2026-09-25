import AppKit
import SwiftUI
import AVFoundation
import ServiceManagement

/// Borderless, non-activating, transparent panel on every Space. Sized to its content,
/// so clicks outside the orb/card go to the windows behind.
final class OverlayPanel: NSPanel {
    init(app: AppState) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 96, height: 96),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        contentView = NSHostingView(rootView: OverlayView(app: app) { [weak self] size in self?.fit(size) })
        if !setFrameUsingName("JarvisOrb") || !isOnScreen(frame), let screen = NSScreen.main?.visibleFrame {
            setFrameOrigin(NSPoint(x: screen.maxX - frame.width - 24, y: screen.minY + 24))
        }
        setFrameAutosaveName("JarvisOrb")
    }

    /// Resize to the SwiftUI content keeping the bottom-right corner (where the orb sits), clamped on screen.
    // ponytail: always anchors bottom-right; add per-quadrant anchoring if the orb lives top-left
    private func fit(_ size: CGSize) {
        guard size.width > 0, size != frame.size else { return }
        var r = NSRect(x: frame.maxX - size.width, y: frame.minY, width: size.width, height: size.height)
        if let v = (screen ?? NSScreen.main)?.visibleFrame {
            r.origin.x = min(max(r.minX, v.minX), v.maxX - r.width)
            r.origin.y = min(max(r.minY, v.minY), v.maxY - r.height)
        }
        setFrame(r, display: true)
    }

    private func isOnScreen(_ r: NSRect) -> Bool { NSScreen.screens.contains { $0.visibleFrame.contains(r) } }
}

struct OverlayView: View {
    @Bindable var app: AppState
    let onSize: (CGSize) -> Void
    @AppStorage("orbHex") private var orbHex = "#3FD8FF"
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if app.expanded || !app.modelReady || needsMic {
                card.transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            OrbView(state: app.state, colorHex: orbHex, mic: app.audio.levels, tts: app.speaker.levels)
                .frame(width: orbSize, height: orbSize)
                .scaleEffect(dropTargeted ? 1.15 : 1)
                .dropDestination(for: URL.self) { urls, _ in
                    app.ingest(files: urls.filter(\.isFileURL)); return true
                } isTargeted: { dropTargeted = $0 }
                .contextMenu { MenuContent(app: app) }  // menu bar icon can hide behind the notch
                .help("Jarvis: ⌥Space per parlare, trascina qui un file per /ingest, clic destro per il menu")
        }
        .padding(8)
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
        .animation(.spring(duration: 0.35), value: app.expanded)
        .animation(.spring(duration: 0.35), value: orbSize)
    }

    private var hint: String? {
        switch app.state {
        case .listening: "Ti ascolto… fai una pausa o premi ⌥Space per finire"
        case .thinking: app.transcribing ? "Trascrivo…" : "Ci penso…"
        default: nil
        }
    }

    private var orbSize: CGFloat { app.state == .idle && !dropTargeted ? 72 : 120 }
    private var needsMic: Bool { AVCaptureDevice.authorizationStatus(for: .audio) != .authorized }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            if needsMic || !app.modelReady { Onboarding(app: app) }
            if let hint {
                Label(hint, systemImage: app.state == .listening ? "waveform" : "ellipsis")
                    .font(.callout.weight(.medium)).foregroundStyle(.tint)
            }
            if !app.transcript.isEmpty {
                Text(app.transcript).font(.callout).foregroundStyle(.secondary).lineLimit(3)
            }
            if !app.answer.isEmpty {
                ScrollView {
                    Text(markdown(app.answer)).font(.body).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
            }
            if !app.tools.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(app.tools.suffix(6)) { t in
                        Label(t.text, systemImage: t.icon).font(.caption).lineLimit(1).truncationMode(.middle)
                    }
                }
                .foregroundStyle(.secondary)
            }
            if let c = app.confirmation {
                Text(c.question).font(.callout.weight(.semibold)).foregroundStyle(.orange)
                HStack {
                    Button("Sì") { app.answerConfirmation(true) }.keyboardShortcut(.defaultAction)
                    Button("No") { app.answerConfirmation(false) }
                }
            }
            if !app.status.isEmpty {
                Text(app.status).font(.caption).foregroundStyle(app.state == .error ? .red : .secondary)
            }
        }
        .padding(14)
        .frame(width: 380, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }

    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

/// First-run steps: microphone, voice model, login item. Accessibility isn't needed (Carbon hotkeys).
struct Onboarding: View {
    let app: AppState
    @State private var mic = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var login = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Configura Jarvis").font(.headline)
            HStack {
                Image(systemName: mic == .authorized ? "checkmark.circle.fill" : "mic.circle")
                Text("Microfono")
                Spacer()
                if mic == .notDetermined {
                    Button("Consenti") {
                        AVCaptureDevice.requestAccess(for: .audio) { _ in
                            Task { @MainActor in mic = AVCaptureDevice.authorizationStatus(for: .audio) }
                        }
                    }
                } else if mic != .authorized {
                    Button("Apri Privacy") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                    }
                }
            }
            HStack {
                Image(systemName: app.modelReady ? "checkmark.circle.fill" : "arrow.down.circle")
                Text(app.modelReady ? "Modello vocale pronto" : "Modello vocale in download…")
            }
            Toggle("Avvia al login", isOn: $login)
                .onChange(of: login) { _, on in LoginItem.set(on) }
        }
        .font(.callout)
    }
}

enum LoginItem {
    static func set(_ on: Bool) {
        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
        catch { Log.write("login item: \(error)") }
    }
}
