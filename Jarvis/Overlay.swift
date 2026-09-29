import AppKit
import SwiftUI
import ServiceManagement

/// Borderless, transparent panel on every Space. Sized to its content, so clicks outside
/// the orb/card go to the windows behind. Becomes key so Wispr can type into the input field.
final class OverlayPanel: NSPanel {
    private let app: AppState

    init(app: AppState) {
        self.app = app
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
        // Always start bottom-right of the menu-bar screen; dragging moves it only for the current session.
        if let screen = NSScreen.screens.first?.visibleFrame {
            setFrameOrigin(NSPoint(x: screen.maxX - frame.width - 4, y: screen.minY + 4))
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateAnchor() }
        }
    }

    /// The orb's corner follows the screen quadrant it was dragged to. Only while collapsed,
    /// so the orb doesn't jump across the open card mid-drag.
    private func updateAnchor() {
        guard let v = (screen ?? NSScreen.main)?.visibleFrame else { return }
        if app.screenHeight != v.height { app.screenHeight = v.height }  // the panel's own screen, not the key one
        guard !app.expanded else { return }
        let top = frame.midY > v.midY, left = frame.midX < v.midX
        if app.anchorTop != top { app.anchorTop = top }
        if app.anchorLeft != left { app.anchorLeft = left }
    }

    /// Resize to the SwiftUI content keeping the orb's corner fixed, clamped on screen.
    private func fit(_ size: CGSize) {
        guard size.width > 0, size != frame.size else { return }
        var r = NSRect(x: app.anchorLeft ? frame.minX : frame.maxX - size.width,
                       y: app.anchorTop ? frame.maxY - size.height : frame.minY,
                       width: size.width, height: size.height)
        if let v = (screen ?? NSScreen.main)?.visibleFrame {
            r.origin.x = min(max(r.minX, v.minX), v.maxX - r.width)
            r.origin.y = min(max(r.minY, v.minY), v.maxY - r.height)
        }
        setFrame(r, display: true)
    }

    override var canBecomeKey: Bool { true }
}

struct OverlayView: View {
    @Bindable var app: AppState
    let onSize: (CGSize) -> Void
    @AppStorage("orbColor") private var orbHex = "#9B5CFF"
    @AppStorage("muted") private var muted = false
    @AppStorage("autoSendDelay") private var autoSendDelay = 3.0
    @State private var dropTargeted = false
    @State private var hovering = false
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The card opens toward the screen center from the orb's corner.
        VStack(alignment: app.anchorLeft ? .leading : .trailing, spacing: 10) {
            if app.expanded && !app.anchorTop {
                card.transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
            OrbView(state: app.state, colorHex: orbHex, levels: app.speaker.levels, hovering: hovering, variant: app.orbVariant)
                .frame(width: orbSize, height: orbSize)
                .opacity(orbResting ? 0.55 : 1)
                .contentShape(Circle())
                .onHover { hovering = $0 }
                .gesture(WindowDragGesture())
                .scaleEffect(dropTargeted ? 1.15 : 1)
                .dropDestination(for: URL.self) { urls, _ in
                    app.ingest(files: urls.filter(\.isFileURL)); return true
                } isTargeted: { dropTargeted = $0 }
                .contextMenu { MenuContent(app: app) }  // menu bar icon can hide behind the notch
                .help("Jarvis:\(shortcutLabel(.talk)) e detta con Wispr, trascina qui un file per /ingest, clic destro per il menu")
            if app.expanded && app.anchorTop {
                card.transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(20)  // room for the card's shadow
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.35), value: app.expanded)
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: orbSize)
        .animation(.easeOut(duration: 0.25), value: orbResting)
    }

    private var accent: Color { Color(hex: orbHex) }
    /// Small and see-through while idle, so it doesn't cover other apps' corners.
    private var orbSize: CGFloat { app.state == .idle && !dropTargeted ? 64 : 170 }
    private var orbResting: Bool { app.state == .idle && !app.expanded && !hovering && !dropTargeted }

    // MARK: card

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if hasConversation { conversation }
            if let c = app.confirmation { confirmBox(c.question) }
            if !app.status.isEmpty { statusBox }
            if app.inputActive { input }
        }
        .padding(14)
        .frame(width: 460, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .background(Color(red: 0.03, green: 0.01, blue: 0.06).opacity(0.78), in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(accent.opacity(0.35)) }
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
        .shadow(color: accent.opacity(0.2), radius: 20)
        .environment(\.colorScheme, .dark)  // HUD look, same in light mode
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(stateColor).frame(width: 7, height: 7)
                .shadow(color: stateColor, radius: 4)
            Text("JARVIS").font(.caption.monospaced().weight(.semibold)).tracking(3).foregroundStyle(accent)
            Text(stateLabel).font(.caption).foregroundStyle(.secondary)
                .contentTransition(.opacity).animation(.easeOut(duration: 0.2), value: stateLabel)
            if app.busy, let start = app.startedAt {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .font(.caption.monospacedDigit()).foregroundStyle(.tertiary).fixedSize()
            }
            Spacer()
            if hasConversation && !app.busy {
                iconButton("square.and.pencil", help: "Nuova sessione (/clear)") { app.newSession() }
            }
            iconButton(muted ? "speaker.slash.fill" : "speaker.wave.2.fill", help: muted ? "Riattiva la voce" : "Muto") {
                muted.toggle(); if muted { app.speaker.stop() }
            }
            if app.busy { iconButton("stop.fill", help: "Ferma la risposta") { app.stopAnswer() } }
            iconButton("xmark", help: "Chiudi (Esc)") { app.close() }
        }
    }

    private var stateLabel: String {
        switch app.state {
        case .idle: "pronto"
        case .listening: "in ascolto"
        case .thinking: "sto pensando"
        case .speaking: "sto parlando"
        case .confirm: "serve una conferma"
        case .error: "errore"
        }
    }

    private var stateColor: Color {
        switch app.state {
        case .confirm: .orange
        case .error: .red
        case .idle: .secondary
        default: accent
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(HUDIconStyle())
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: conversation

    private var hasConversation: Bool { !app.history.isEmpty || !app.transcript.isEmpty || !app.answer.isEmpty || app.busy }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(app.history) { turn in
                        userBubble(turn.question)
                        MessageText(text: turn.answer, accent: accent).equatable().opacity(0.7)  // not re-parsed on every streamed token
                        CopyButton(text: turn.answer, label: "Copia")
                        Rectangle().fill(accent.opacity(0.2)).frame(height: 1)
                    }
                    if !app.transcript.isEmpty { userBubble(app.transcript) }
                    if !app.tools.isEmpty { activity }
                    if !app.answer.isEmpty {
                        MessageText(text: app.answer, accent: accent)
                        if !app.busy { CopyButton(text: app.answer, label: "Copia") }
                    } else if app.busy {
                        TypingDots(color: accent)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 6)
            }
            .frame(maxHeight: app.screenHeight * 0.5)
            .onChange(of: app.answer) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: app.tools.count) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: app.transcript) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private func userBubble(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .textSelection(.enabled)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(accent.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 40)
    }

    /// Tool calls folded into one line (the latest), expandable to the full list.
    private var activity: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(app.tools) { t in
                    Label(t.text, systemImage: t.icon).lineLimit(1).truncationMode(.middle)
                }
            }
            .font(.caption.monospaced())
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                if app.busy { ProgressView().controlSize(.mini) } else { Image(systemName: "checkmark.circle") }
                Text(app.tools.last.map { $0.text } ?? "").font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                Text("· \(app.tools.count)").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.secondary)
    }

    private func confirmBox(_ question: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(question, systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { app.answerConfirmation(true) } label: { Text("Sì  ⏎").frame(minWidth: 60) }
                    .buttonStyle(.borderedProminent).tint(.orange)
                Button { app.answerConfirmation(false) } label: { Text("No  Esc").frame(minWidth: 60) }
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.orange.opacity(0.5)) }
    }

    private var statusBox: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(app.status, systemImage: app.state == .error ? "exclamationmark.octagon.fill" : "info.circle")
                .font(.caption)
                .foregroundStyle(app.state == .error ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if app.failedPrompt != nil && !app.busy {
                Button("Riprova", systemImage: "arrow.clockwise") { app.retry() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    /// Empty card: the last prompts one click away (not /ingest, whose files are already in the vault).
    private var recentChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECENTI").font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(.tertiary)
            ForEach(recentPrompts) { r in
                Button { app.ask(r.command, label: r.label) } label: {
                    Label(r.label, systemImage: "arrow.uturn.backward")
                        .font(.caption).lineLimit(1).truncationMode(.tail)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(ChipStyle(accent: accent))
                .help(r.label)
            }
        }
    }

    private var recentPrompts: [RecentCommand] {
        Array(app.recent.filter { !$0.command.hasPrefix("/ingest") }.prefix(3))
    }

    // MARK: input

    @State private var sendProgress: CGFloat = 0

    private var autoSending: Bool {
        let t = app.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard autoSendDelay > 0, !app.awaitsReturn, !t.isEmpty, !t.hasPrefix("/"), !t.hasPrefix("\"/") else { return false }  // a dropped folder path waits for ⏎
        // A lone word is usually a dictation cut short: it waits for more or ⏎. Jarvis's own words ("stop", "sì") still go.
        if case .agent = Intent.route(t), !t.contains(" ") { return false }
        return true
    }

    private var input: some View {
        VStack(alignment: .leading, spacing: 4) {
            if app.draft.isEmpty && !hasConversation && app.confirmation == nil && !recentPrompts.isEmpty {
                recentChips.padding(.bottom, 6)
            }
            ForEach(suggestions, id: \.self) { c in
                Button { pick(c) } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("/" + c.name).font(.callout.monospaced()).foregroundStyle(accent)
                        Text(c.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            field
        }
    }

    /// Typing "/" lists the session's skills: ⏎ or Tab completes the first one, click picks any.
    private var suggestions: [SlashCommand] {
        guard app.draft.hasPrefix("/"), !app.draft.contains(" ") else { return [] }
        let typed = app.draft.dropFirst().lowercased()
        let hits = app.commands.filter { $0.name.lowercased().hasPrefix(typed) }
            + app.commands.filter { !$0.name.lowercased().hasPrefix(typed) && $0.name.lowercased().contains(typed) }
        return Array(hits.prefix(8))  // ponytail: first 8 matches, add scrolling if skills get hard to find
    }

    private func pick(_ c: SlashCommand) {
        app.draft = "/\(c.name) "
        inputFocused = true
    }

    /// Wispr pastes each dictation at once: send when the text has been still for `autoSendDelay` s (0 = only ⏎).
    /// The bar under the field shows the countdown, so the auto-send never comes as a surprise.
    private var field: some View {
        HStack(spacing: 8) {
            iconButton("plus", help: "Allega file (/ingest)") { app.pickFiles() }
            Image(systemName: app.confirmation == nil ? "waveform" : "questionmark.bubble")
                .foregroundStyle(inputFocused ? accent : .secondary)
            TextField(placeholder, text: $app.draft)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($inputFocused)
                .onAppear { inputFocused = true }
                .onChange(of: app.focusRequest) { inputFocused = true }
                .onSubmit {
                    if let first = suggestions.first, !app.commands.contains(where: { "/" + $0.name == app.draft }) { pick(first) } else { app.submit() }
                }
                .onKeyPress(.tab) { guard let first = suggestions.first else { return .ignored }; pick(first); return .handled }
                .onChange(of: app.draft) { _, text in if !text.isEmpty { app.speaker.stop() } }  // dictating = barge in
                .onExitCommand { app.escape() }
                .task(id: app.draft) {
                    // Typed commands wait for ⏎: they may need arguments. Dictation never starts with "/".
                    var reset = Transaction(); reset.disablesAnimations = true
                    withTransaction(reset) { sendProgress = 0 }
                    guard autoSending else { return }
                    do { try await Task.sleep(for: .milliseconds(20)) } catch { return }  // cancelled: no stray animation
                    withAnimation(.linear(duration: autoSendDelay)) { sendProgress = 1 }
                    do { try await Task.sleep(for: .seconds(autoSendDelay)) } catch { return }
                    app.submit()
                }
            Text("⏎").font(.caption.monospaced()).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(accent.opacity(inputFocused ? 0.8 : 0.3), lineWidth: inputFocused ? 1.5 : 1)
        }
        .overlay(alignment: .bottomLeading) {
            if autoSending {
                Capsule().fill(accent).frame(height: 2)
                    .scaleEffect(x: sendProgress, anchor: .leading)
                    .padding(.horizontal, 8).padding(.bottom, 1)
            }
        }
        .animation(.easeOut(duration: 0.15), value: inputFocused)
    }

    private var placeholder: String {
        if app.confirmation != nil { return "Detta sì o no…" }
        return app.history.isEmpty && app.transcript.isEmpty ? (Prefs.dictation == "jarvis" ? "Parla, ti ascolto… (/ per le skill)" : "Detta con Wispr… (/ per le skill)") : "Continua…"
    }
}

/// An answer: the spoken lead in full size, then the on-screen details with block markdown
/// (headings, bullet and numbered lists) that SwiftUI's inline-only markdown can't lay out.
struct MessageText: View, Equatable {
    let text: String
    let accent: Color

    var body: some View {
        // Spoken lead = first paragraph, unless the answer opens with code.
        let parts = text.components(separatedBy: "\n\n")
        let lead = parts[0].contains("```") ? "" : parts[0]
        let rest = lead.isEmpty ? text : parts.dropFirst().joined(separator: "\n\n")
        VStack(alignment: .leading, spacing: 8) {
            if !lead.isEmpty { Text(inline(lead)).font(.body.weight(.medium)).lineSpacing(2) }
            if !rest.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(Self.blocks(rest).enumerated()), id: \.offset) { _, block in
                        switch block {
                        case .line(let line): row(line)
                        case .code(let code): codeBlock(code)
                        }
                    }
                }
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.85))
            }
        }
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    enum Block { case line(String), code(String) }

    /// Lines, with ``` fences folded into code blocks (an unclosed fence is code still streaming).
    static func blocks(_ s: String) -> [Block] {
        var out: [Block] = [], code: [String]?
        for line in s.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if let c = code { out.append(.code(c.joined(separator: "\n"))); code = nil } else { code = [] }
            } else if code != nil {
                code!.append(line)
            } else {
                out.append(.line(line))
            }
        }
        if let c = code { out.append(.code(c.joined(separator: "\n"))) }
        return out
    }

    private func codeBlock(_ code: String) -> some View {
        Text(code)
            .font(.caption.monospaced())
            .foregroundStyle(.primary.opacity(0.9))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10).padding(.trailing, 22)
            .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(accent.opacity(0.25)) }
            .overlay(alignment: .topTrailing) { CopyButton(text: code).padding(6) }
    }

    @ViewBuilder private func row(_ raw: String) -> some View {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            Color.clear.frame(height: 4)
        } else if let m = line.firstMatch(of: /^#{1,6}\s+(.*)/) {
            Text(inline(String(m.1))).font(.callout.weight(.semibold)).foregroundStyle(accent).padding(.top, 4)
        } else if let m = line.firstMatch(of: /^[-*•]\s+(.*)/) {
            bullet("•", String(m.1), indent: raw.prefix { $0 == " " }.count)
        } else if let m = line.firstMatch(of: /^(\d+)[.)]\s+(.*)/) {
            bullet("\(m.1).", String(m.2), indent: raw.prefix { $0 == " " }.count)
        } else {
            Text(inline(line))
        }
    }

    private func bullet(_ mark: String, _ text: String, indent: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(mark).foregroundStyle(accent).monospacedDigit()
            Text(inline(text))
        }
        .padding(.leading, CGFloat(min(indent, 8)) * 5)
    }

    private func inline(_ s: String) -> AttributedString {
        let wiki = s.replacing(/\[\[([^\]|]+)(\|([^\]]+))?\]\]/) { m in String(m.3 ?? m.1) }  // [[Nota|alias]] → alias
        return (try? AttributedString(markdown: wiki, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

/// Copies `text`; shows a check for a moment so the click feels done.
struct CopyButton: View {
    let text: String
    var label: String?
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
        } label: {
            if let label { Label(copied ? "Copiato" : label, systemImage: copied ? "checkmark" : "doc.on.doc").font(.caption) }
            else { Label(copied ? "Copiato" : "Copia", systemImage: copied ? "checkmark" : "doc.on.doc").labelStyle(.iconOnly).font(.caption) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tertiary)
        .help("Copia")
    }
}

/// Three dots breathing in turn while Claude works and nothing has streamed yet. Static under Reduce Motion.
struct TypingDots: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle().fill(color)
                        .frame(width: 6, height: 6)
                        .opacity(reduceMotion ? 0.7 : 0.3 + 0.7 * max(0, sin(t * 4 - Double(i) * 0.7)))
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityLabel("Jarvis sta pensando")
    }
}

/// Round header button: brightens on hover, dips on press.
struct HUDIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }

    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(hovering ? .primary : .secondary)
                .background(.white.opacity(hovering ? 0.16 : 0.08), in: Circle())
                .scaleEffect(configuration.isPressed ? 0.88 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)
                .animation(.spring(duration: 0.2), value: configuration.isPressed)
        }
    }
}

/// Tinted pill for the recent prompts, same hover/press feel as the header buttons.
struct ChipStyle: ButtonStyle {
    let accent: Color
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration, accent: accent) }

    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        let accent: Color
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(hovering ? .primary : .secondary)
                .background(accent.opacity(hovering ? 0.24 : 0.12), in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(accent.opacity(hovering ? 0.5 : 0.2)) }
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)
                .animation(.spring(duration: 0.2), value: configuration.isPressed)
        }
    }
}

enum LoginItem {
    static func set(_ on: Bool) {
        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
        catch { Log.write("login item: \(error)") }
    }
}
