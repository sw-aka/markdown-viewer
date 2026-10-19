import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// GitHub-style rendered preview. The page and its renderer are bundled in
/// Resources/Renderer and served over the custom `mdv:` scheme:
/// - `mdv://app/<path>` serves bundled renderer files.
/// - `mdv://doc/<absolute path>` serves local files referenced by the document
///   (relative images and links are rewritten to this form by the renderer).
struct MarkdownPreview: NSViewRepresentable {
    let markdown: String
    let baseDirectory: URL?
    let scrollSync: ScrollSync
    let syncEnabled: Bool
    /// False while the preview is collapsed (Source mode): it then gives up focus.
    var isActive = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(LocalSchemeHandler(), forURLScheme: LocalSchemeHandler.scheme)
        configuration.userContentController.add(WeakMessageHandler(context.coordinator), name: "mdv")
        configuration.preferences.isElementFullscreenEnabled = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isInspectable = true
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")
        webView.setAccessibilityIdentifier("MarkdownPreview")
        context.coordinator.webView = webView

        scrollSync.scrollPreview = { [weak coordinator = context.coordinator] line in
            coordinator?.scroll(toLine: line)
        }

        webView.load(URLRequest(url: URL(string: "mdv://app/index.html")!))
        context.coordinator.update(markdown: markdown, baseDirectory: baseDirectory)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if !isActive {
            DispatchQueue.main.async { [weak webView] in
                guard let webView, let window = webView.window,
                      let responder = window.firstResponder as? NSView, responder.isDescendant(of: webView) else { return }
                window.makeFirstResponder(nil)
            }
        }
        context.coordinator.update(markdown: markdown, baseDirectory: baseDirectory)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MarkdownPreview
        weak var webView: WKWebView?

        private var isReady = false
        private var renderedMarkdown: String?
        private var renderedBase: URL?
        private var pendingMarkdown: String?
        private var pendingBase: URL?
        private var debounce: Task<Void, Never>?

        init(_ parent: MarkdownPreview) {
            self.parent = parent
        }

        func update(markdown: String, baseDirectory: URL?) {
            // Compare with the newest requested text, not just the rendered one,
            // so typing and undoing within the debounce still renders the latest.
            let latest = pendingMarkdown ?? renderedMarkdown
            let latestBase = pendingMarkdown != nil ? pendingBase : renderedBase
            guard markdown != latest || baseDirectory != latestBase else { return }
            pendingMarkdown = markdown
            pendingBase = baseDirectory
            guard isReady else { return }
            // Render the first change immediately, then coalesce rapid typing.
            debounce?.cancel()
            let delay: Duration = renderedMarkdown == nil ? .zero : .milliseconds(90)
            debounce = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.flush()
            }
        }

        private func flush() {
            guard isReady, let webView, let markdown = pendingMarkdown else { return }
            let base = pendingBase
            renderedMarkdown = markdown
            renderedBase = base
            pendingMarkdown = nil

            var options: [String: Any] = [:]
            if let base { options["baseURL"] = LocalSchemeHandler.documentURL(for: base, isDirectory: true).absoluteString }
            webView.callAsyncJavaScript(
                "window.mdv.render(markdown, options)",
                arguments: ["markdown": markdown, "options": options],
                in: nil,
                in: .page,
                completionHandler: nil
            )
        }

        func scroll(toLine line: Double) {
            guard parent.syncEnabled, isReady else { return }
            webView?.callAsyncJavaScript("window.mdv.scrollToLine(line)", arguments: ["line": line], in: nil, in: .page, completionHandler: nil)
        }

        // MARK: Messages from the page

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                isReady = true
                if pendingMarkdown == nil, let renderedMarkdown {
                    // The page reloaded (e.g. web content process restart): render again.
                    pendingMarkdown = renderedMarkdown
                    pendingBase = renderedBase
                }
                renderedMarkdown = nil
                flush()
            case "scroll":
                if parent.syncEnabled, let line = body["line"] as? Double {
                    parent.scrollSync.previewDidScroll(toLine: line)
                }
            case "copy":
                if let text = body["text"] as? String {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            case "open":
                if let string = body["url"] as? String, let url = URL(string: string) {
                    open(url)
                }
            default:
                break
            }
        }

        private func open(_ url: URL) {
            if let fileURL = LocalSchemeHandler.fileURL(for: url) {
                openLocalFile(fileURL)
            } else if ["http", "https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            }
        }

        /// Opens Markdown in this app and harmless documents in their default
        /// app. Decides on the resolved file's real type (symlinks followed), so
        /// a link can never launch an app or script; anything else is revealed
        /// in Finder.
        private func openLocalFile(_ fileURL: URL) {
            let resolved = fileURL.resolvingSymlinksInPath()
            let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey, .isPackageKey, .contentTypeKey])
            guard let values, values.isRegularFile == true, values.isPackage != true, let type = values.contentType else {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                return
            }
            let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn"]
            // Opened in their default app only when both the extension and the
            // real content type agree (images, PDF, plain text, common media).
            let openableExtensions: Set<String> = [
                "png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff", "bmp",
                "pdf", "txt", "mp4", "mov", "m4v", "mp3", "m4a", "wav", "aiff",
            ]
            let openableTypes: [UTType] = [.image, .pdf, .plainText, .audiovisualContent]
            let ext = resolved.pathExtension.lowercased()
            if markdownExtensions.contains(ext) {
                NSDocumentController.shared.openDocument(withContentsOf: fileURL, display: true) { _, _, _ in }
            } else if openableExtensions.contains(ext), openableTypes.contains(where: type.conforms(to:)),
                      ![.script, .executable, .application, .bundle, .package, .svg, .html].contains(where: type.conforms(to:)) {
                // Use the type's default app explicitly: a plain open() would
                // honour a per-file "Open With" override stored in the file.
                if let app = NSWorkspace.shared.urlForApplication(toOpen: type) {
                    NSWorkspace.shared.open([resolved], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            }
        }

        // MARK: Navigation

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .cancel }
            // Only the renderer page itself may load in the main frame (initial
            // load and reloads), never as the result of a click in the document.
            if action.navigationType != .linkActivated, action.targetFrame?.isMainFrame == true,
               url.scheme == LocalSchemeHandler.scheme, url.host == "app", url.path == "/index.html" {
                return .allow
            }
            if action.navigationType == .linkActivated { open(url) }
            return .cancel
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            isReady = false
            webView.reload()
        }
    }
}

/// Breaks the retain cycle between WKUserContentController and the coordinator.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// Serves bundled renderer files and local document assets over `mdv:`.
final class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mdv"

    static func documentURL(for fileURL: URL, isDirectory: Bool) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "doc"
        components.path = fileURL.path(percentEncoded: false) + (isDirectory ? "/" : "")
        return components.url!
    }

    static func fileURL(for url: URL) -> URL? {
        guard url.scheme == scheme, url.host == "doc" else { return nil }
        return URL(filePath: url.path(percentEncoded: false))
    }

    private static let rendererRoot = Bundle.main.resourceURL!.appending(path: "Renderer", directoryHint: .isDirectory)

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let fileURL = resolve(url) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": mimeType, "Content-Length": String(data.count), "Cache-Control": "no-cache"]
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    private func resolve(_ url: URL) -> URL? {
        switch url.host {
        case "app":
            let relative = url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let candidate = Self.rendererRoot.appending(path: relative).standardizedFileURL
            // Never serve anything outside the bundled renderer directory.
            guard candidate.path.hasPrefix(Self.rendererRoot.standardizedFileURL.path) else { return nil }
            return candidate
        case "doc":
            return Self.fileURL(for: url)?.standardizedFileURL
        default:
            return nil
        }
    }
}
