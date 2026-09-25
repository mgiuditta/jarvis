import AppKit
import SwiftUI
import ServiceManagement

/// Borderless, transparent panel on every Space. Sized to its content, so clicks outside
/// the orb/card go to the windows behind. Becomes key so Wispr can type into the input field.
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

    override var canBecomeKey: Bool { true }

    private func isOnScreen(_ r: NSRect) -> Bool { NSScreen.screens.contains { $0.visibleFrame.contains(r) } }
}

struct OverlayView: View {
    @Bindable var app: AppState
    let onSize: (CGSize) -> Void
    @AppStorage("orbColor") private var orbHex = "#9B5CFF"
    @AppStorage("muted") private var muted = false
    @State private var dropTargeted = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if app.expanded {
                card.transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            OrbView(state: app.state, colorHex: orbHex, levels: app.speaker.levels)
                .frame(width: orbSize, height: orbSize)
                .contentShape(Circle())
                .gesture(WindowDragGesture())
                .scaleEffect(dropTargeted ? 1.15 : 1)
                .dropDestination(for: URL.self) { urls, _ in
                    app.ingest(files: urls.filter(\.isFileURL)); return true
                } isTargeted: { dropTargeted = $0 }
                .contextMenu { MenuContent(app: app) }  // menu bar icon can hide behind the notch
                .help("Jarvis: ⌥Space e detta con Wispr, trascina qui un file per /ingest, clic destro per il menu")
        }
        .padding(8)
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
        .animation(.spring(duration: 0.35), value: app.expanded)
        .animation(.spring(duration: 0.35), value: orbSize)
    }

    private var hint: String? {
        switch app.state {
        case .listening: "Detta con Wispr: invio automatico dopo un secondo · Esc annulla"
        case .thinking: "Ci penso…"
        default: nil
        }
    }

    private var orbSize: CGFloat { app.state == .idle && !dropTargeted ? 96 : 260 }

    /// Wispr pastes the whole dictation at once: send when the text has been still for a second.
    private var input: some View {
        TextField(app.confirmation == nil ? "Detta con Wispr…" : "⏎ sì · Esc no · o dettalo", text: $app.draft)
            .textFieldStyle(.plain)
            .font(.body)
            .padding(8)
            .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: orbHex).opacity(0.6)))
            .focused($inputFocused)
            .onAppear { inputFocused = true }
            .onChange(of: app.focusRequest) { inputFocused = true }
            .onSubmit { app.submit() }
            .onExitCommand { app.escape() }
            .task(id: app.draft) {
                guard !app.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled { app.submit() }
            }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let hint {
                Label(hint, systemImage: app.state == .listening ? "waveform" : "ellipsis")
                    .font(.callout.weight(.medium)).foregroundStyle(Color(hex: orbHex))
            }
            if app.inputActive { input }
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
                        Label(t.text, systemImage: t.icon).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                    }
                }
                .foregroundStyle(.secondary)
            }
            if let c = app.confirmation {
                Text(c.question).font(.callout.weight(.semibold)).foregroundStyle(.orange)
                HStack {
                    Button("Sì") { app.answerConfirmation(true) }
                    Button("No") { app.answerConfirmation(false) }
                }
            }
            Toggle(isOn: $muted) { Label("Muto", systemImage: muted ? "speaker.slash" : "speaker.wave.2") }
                .toggleStyle(.button).controlSize(.small)
                .onChange(of: muted) { _, on in if on { app.speaker.stop() } }
            if !app.status.isEmpty {
                Text(app.status).font(.caption).foregroundStyle(app.state == .error ? .red : .secondary)
            }
        }
        .padding(14)
        .frame(width: 380, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(Color(red: 0.03, green: 0.01, blue: 0.06).opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(hex: orbHex).opacity(0.45)))
        .shadow(color: Color(hex: orbHex).opacity(0.35), radius: 14)
        .environment(\.colorScheme, .dark)  // HUD look, same in light mode
    }

    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

enum LoginItem {
    static func set(_ on: Bool) {
        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
        catch { Log.write("login item: \(error)") }
    }
}
