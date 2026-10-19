import AppKit
import WebKit

/// Headless preview rendering for automated checks:
///
///     "Markdown Viewer.app/Contents/MacOS/Markdown Viewer" --render-snapshot in.md out.png [--dark] [--width 1000]
///
/// Renders the document through the same bundled page and `mdv:` scheme as the
/// app's preview, waits for Mermaid/math/maps to finish, writes a full-page PNG
/// and exits (status 0 on success). Works without a visible window, so it can
/// run over SSH or while the screen is locked.
@MainActor
final class SnapshotRenderer: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    struct Options {
        var input: URL
        var output: URL
        var dark = false
        var width: CGFloat = 1000
    }

    static func options(from arguments: [String]) -> Options? {
        guard let index = arguments.firstIndex(of: "--render-snapshot"), arguments.count > index + 2 else { return nil }
        var options = Options(
            input: URL(filePath: arguments[index + 1]).standardizedFileURL,
            output: URL(filePath: arguments[index + 2]).standardizedFileURL
        )
        options.dark = arguments.contains("--dark")
        if let w = arguments.firstIndex(of: "--width"), arguments.count > w + 1, let value = Double(arguments[w + 1]) {
            options.width = value
        }
        return options
    }

    private static var current: SnapshotRenderer?

    static func run(_ options: Options) {
        log("starting \(options.input.path)")
        let renderer = SnapshotRenderer(options: options)
        current = renderer
        renderer.start()
    }

    private let options: Options
    private var window: NSWindow?
    private var webView: WKWebView?

    private init(options: Options) {
        self.options = options
    }

    private func start() {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(LocalSchemeHandler(), forURLScheme: LocalSchemeHandler.scheme)
        configuration.userContentController.add(self, name: "mdv")
        let frame = NSRect(x: 0, y: 0, width: options.width, height: 800)
        let webView = WKWebView(frame: frame, configuration: configuration)
        webView.navigationDelegate = self
        webView.appearance = NSAppearance(named: options.dark ? .darkAqua : .aqua)

        // WebKit only paints inside a window; keep it off screen.
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.contentView = webView
        window.orderBack(nil)
        self.window = window
        self.webView = webView
        webView.load(URLRequest(url: URL(string: "mdv://app/index.html")!))

        // Never hang an automated run.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(60))
            Self.finish("timed out", status: 2)
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        Self.log("message \(type)")
        switch type {
        case "ready": render()
        case "rendered": Task { await snapshot() }
        default: break
        }
    }

    private func render() {
        guard let text = try? String(contentsOf: options.input, encoding: .utf8) else {
            Self.finish("cannot read \(options.input.path)", status: 1)
            return
        }
        let base = LocalSchemeHandler.documentURL(for: options.input.deletingLastPathComponent(), isDirectory: true).absoluteString
        webView?.callAsyncJavaScript(
            "window.mdv.render(markdown, { baseURL: base })",
            arguments: ["markdown": text, "base": base],
            in: nil,
            in: .page,
            completionHandler: nil
        )
    }

    private func snapshot() async {
        guard let webView, let window else { return }
        // Give remote images and map tiles a moment, then grow to the full page height.
        try? await Task.sleep(for: .seconds(2))
        let height = (try? await webView.evaluateJavaScript("document.documentElement.scrollHeight") as? Double) ?? 800
        let size = NSSize(width: options.width, height: min(height, 30_000))
        window.setContentSize(size)
        webView.frame = NSRect(origin: .zero, size: size)
        try? await Task.sleep(for: .milliseconds(500))

        let configuration = WKSnapshotConfiguration()
        configuration.rect = NSRect(origin: .zero, size: size)
        configuration.afterScreenUpdates = true
        do {
            let image = try await webView.takeSnapshot(configuration: configuration)
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                Self.finish("cannot encode PNG", status: 1)
                return
            }
            try png.write(to: options.output)
            Self.finish("wrote \(options.output.path) (\(Int(size.width))x\(Int(size.height)))", status: 0)
        } catch {
            Self.finish("snapshot failed: \(error)", status: 1)
        }
    }

    static func log(_ message: String) {
        FileHandle.standardError.write(Data("render-snapshot: \(message)\n".utf8))
    }

    private static func finish(_ message: String, status: Int32) {
        FileHandle.standardError.write(Data("render-snapshot: \(message)\n".utf8))
        exit(status)
    }
}
