import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

/// What's in front of the user when they call Jarvis: the app they came from, its window, document and selection.
enum FrontContext {
    /// Shows the system prompt the first time. Without the permission `describe` only knows the app name.
    @MainActor static func requestAccessibility() {
        guard !AXIsProcessTrusted() else { return }
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)  // the constant is a C global var: not concurrency-safe
    }

    /// Off the main actor: every attribute is an IPC round trip to the other app.
    @concurrent static func describe(pid: pid_t, name: String) async -> String {
        var lines = ["App: \(name)"]
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)  // a hung app must not hang Jarvis for the default 6 s
        if let window: AXUIElement = attribute(app, kAXFocusedWindowAttribute) {
            if let title: String = attribute(window, kAXTitleAttribute), !title.isEmpty { lines.append("Finestra: \(title)") }
            if let doc: String = attribute(window, kAXDocumentAttribute), !doc.isEmpty { lines.append("Documento: \(doc)") }  // file or page URL
        }
        if let focused: AXUIElement = attribute(app, kAXFocusedUIElementAttribute),
           let selected: String = attribute(focused, kAXSelectedTextAttribute), !selected.isEmpty {
            lines.append("Testo selezionato:\n\(selected.prefix(8000))")
        }
        return lines.joined(separator: "\n")
    }

    nonisolated private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// Front window of `pid` as a PNG the agent can read. Asks for Screen Recording the first time (then throws until Jarvis restarts).
    /// ponytail: one fixed file, overwritten each time; timestamped names if the agent needs to compare two screens.
    @concurrent static func screenshot(pid: pid_t) async throws -> URL {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        // windows come front to back: the first normal-layer one is the app's front window
        guard let window = content.windows.first(where: { $0.owningApplication?.processID == pid && $0.windowLayer == 0 }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let info = SCShareableContent.info(for: filter)
        let config = SCStreamConfiguration()
        config.width = Int(info.contentRect.width * CGFloat(info.pointPixelScale))
        config.height = Int(info.contentRect.height * CGFloat(info.pointPixelScale))
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        let url = URL(fileURLWithPath: Prefs.support).appending(path: "schermo.png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }
}
