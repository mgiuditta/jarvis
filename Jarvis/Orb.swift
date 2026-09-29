import SwiftUI
import WebKit

enum OrbState: String {
    case idle, listening, thinking, speaking, confirm, error

    /// Menu bar, menu and dashboard say the same thing.
    var label: String {
        switch self {
        case .idle: "Pronto"
        case .listening: "Aspetto la dettatura"
        case .thinking: "Sta pensando"
        case .speaking: "Sta parlando"
        case .confirm: "Attende conferma"
        case .error: "Errore"
        }
    }

    var symbol: String {
        switch self {
        case .idle: "circle.circle"
        case .listening: "waveform.circle.fill"
        case .thinking: "ellipsis.circle.fill"
        case .speaking: "speaker.wave.2.circle.fill"
        case .confirm: "questionmark.circle.fill"
        case .error: "exclamationmark.circle.fill"
        }
    }
}

/// The 3D orb is a three.js page (orb/orb.html in the bundle) in a WKWebView.
/// Swift pushes state, voice level and color ~30×/s; the page never talks back.
final class OrbWebView: WKWebView, WKNavigationDelegate {
    var state: OrbState = .idle
    var colorHex = "#9B5CFF"
    var hovering = false
    private let levels: Levels
    private var timer: Timer?
    private var lastPush = ""

    init(levels: Levels) {
        self.levels = levels
        super.init(frame: .zero, configuration: WKWebViewConfiguration())
        setValue(false, forKey: "drawsBackground")
        navigationDelegate = self
        guard let url = Bundle.main.url(forResource: "orb", withExtension: "html", subdirectory: "orb") else {
            Log.write("orb.html non trovato nel bundle: overlay solo testo")
            return
        }
        loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    required init?(coder: NSCoder) { fatalError() }

    // Clicks, drags and drops go to the SwiftUI view around it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate(); timer = nil
        guard window != nil else { return }
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.push() }
        }
        RunLoop.main.add(t, forMode: .common)  // keeps running while a menu is open or a panel is modal
        timer = t
    }

    // ponytail: skips pushes while hidden; WebKit throttles the page's own render loop for hidden windows
    private func push() {
        guard window?.isVisible == true else { return }
        let v = state == .speaking ? levels.value : .zero
        let js = "window.orb && orb.set({state:'\(state.rawValue)',level:\(v.x),low:\(v.y),high:\(v.w),hover:\(hovering),color:'\(colorHex)'})"
        guard js != lastPush else { return }  // idle orb: nothing changes, nothing to send
        lastPush = js
        evaluateJavaScript(js)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Log.write("orb: caricamento fallito \(error)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Log.write("orb: processo web terminato, ricarico")
        lastPush = ""
        webView.reload()
    }
}

struct OrbView: NSViewRepresentable {
    let state: OrbState
    let colorHex: String
    let levels: Levels
    let hovering: Bool

    func makeNSView(context: Context) -> OrbWebView { OrbWebView(levels: levels) }

    func updateNSView(_ v: OrbWebView, context: Context) {
        v.state = state
        v.colorHex = colorHex
        v.hovering = hovering
    }
}
