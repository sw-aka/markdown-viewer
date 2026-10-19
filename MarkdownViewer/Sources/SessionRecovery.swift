import AppKit
import SwiftUI
import WebKit

/// A durable snapshot is completed before Sparkle is allowed to terminate.
/// Text is kept in Application Support, never written over the user's files.
final class SessionRecovery {
    static let shared = SessionRecovery()
    final class Entry {
        let id: UUID
        weak var window: NSWindow?
        var kind: SessionWindowKind
        var fileURL: URL?
        var text: Binding<String>
        var mode: Binding<ViewMode>
        var fraction: Binding<Double>
        init(id: UUID, window: NSWindow, kind: SessionWindowKind, fileURL: URL?, text: Binding<String>, mode: Binding<ViewMode>, fraction: Binding<Double>) {
            self.id = id; self.window = window; self.kind = kind; self.fileURL = fileURL
            self.text = text; self.mode = mode; self.fraction = fraction
        }
    }
    private var entries: [UUID: Entry] = [:]
    private var pending: [SavedWindowSession] = []
    private var editorRestorations: [ObjectIdentifier: SavedWindowSession] = [:]
    private var previewRestorations: [ObjectIdentifier: Double] = [:]
    private var editedDocuments: [NSDocument] = []
    private var restoringCount = 0
    private var startedRestore = false
    private(set) var isRestoring = false
    private(set) var installationPrepared = false
    private init() {
        isRestoring = FileManager.default.fileExists(atPath: recoveryURL.path)
    }

    var recoveryURL: URL {
        URL.applicationSupportDirectory.appending(path: "Markdown Viewer/Update Session.json")
    }

    func register(_ entry: Entry) {
        entries[entry.id] = entry
        guard isRestoring, let index = pending.firstIndex(where: { saved in
            saved.kind == entry.kind && saved.fileURL == entry.fileURL
        }) else { return }
        let saved = pending.remove(at: index)
        restoringCount += 1
        Task { [weak self] in
            await Task.yield()
            guard let self, let window = entry.window else { return }
            let windowID = ObjectIdentifier(window)
            editorRestorations[windowID] = saved
            previewRestorations[windowID] = saved.previewScroll
            entry.mode.wrappedValue = ViewMode(rawValue: saved.mode) ?? .split
            entry.fraction.wrappedValue = min(0.9, max(0.1, saved.fraction))
            entry.text.wrappedValue = saved.text
            window.setFrame(window.constrainFrameRect(saved.frame, to: nil), display: true)
            if saved.minimized { window.miniaturize(nil) }
            else if saved.key { window.makeKeyAndOrderFront(nil) }
            // An unchanged file may not otherwise trigger another renderer pass.
            await Task.yield()
            descendant(NSTextView.self, in: window.contentView).map { restoreEditor(in: $0) }
            descendant(WKWebView.self, in: window.contentView)?.evaluateJavaScript("window.mdv?.rerender()", completionHandler: nil)
            restoringCount -= 1
            finishRestoringIfPossible()
        }
    }

    func unregister(_ id: UUID) { entries.removeValue(forKey: id) }

    func prepareForInstallation() async throws {
        UpdateWriteProtection.setActive(true)
        let order = NSApp.orderedWindows
        let active = entries.values.filter { $0.window != nil }.sorted {
            (order.firstIndex(of: $0.window!) ?? Int.max) > (order.firstIndex(of: $1.window!) ?? Int.max)
        }
        // Stop native text editing immediately, before the first WebKit await.
        // SwiftUI's disabled environment is applied on the next view update.
        for entry in active {
            descendant(NSTextView.self, in: entry.window?.contentView)?.isEditable = false
        }
        var windows: [SavedWindowSession] = []
        for entry in active {
            guard let window = entry.window else { continue }
            let editor = descendant(NSTextView.self, in: window.contentView)
            let selection = editor?.selectedRange() ?? NSRange(location: 0, length: 0)
            // Capture all text synchronously before awaiting WebKit.
            var saved = SavedWindowSession(
                kind: entry.kind, fileURL: entry.fileURL, text: entry.text.wrappedValue,
                mode: entry.mode.wrappedValue.rawValue, fraction: entry.fraction.wrappedValue,
                frame: window.frame, selectionLocation: selection.location, selectionLength: selection.length,
                editorScroll: editor?.enclosingScrollView?.contentView.bounds.origin ?? .zero,
                previewScroll: 0, minimized: window.isMiniaturized, key: window.isKeyWindow)
            if let webView = descendant(WKWebView.self, in: window.contentView) {
                saved.previewScroll = await withCheckedContinuation { continuation in
                    webView.evaluateJavaScript("window.scrollY") { value, _ in
                        continuation.resume(returning: value as? Double ?? 0)
                    }
                }
            }
            windows.append(saved)
        }
        // Failing to save must stop the update, rather than close dirty files.
        let data = try JSONEncoder().encode(SavedUpdateSession(format: 1, windows: windows))
        try FileManager.default.createDirectory(at: recoveryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: recoveryURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recoveryURL.path)
        ScratchPadStore.shared.saveNow()
        installationPrepared = true
        editedDocuments = NSDocumentController.shared.documents.filter(\.isDocumentEdited)
        for document in editedDocuments { document.updateChangeCount(.changeCleared) }
    }

    func cancelInstallation() {
        UpdateWriteProtection.setActive(false)
        guard installationPrepared else { return }
        for document in editedDocuments { document.updateChangeCount(.changeDone) }
        editedDocuments = []
        installationPrepared = false
        try? FileManager.default.removeItem(at: recoveryURL)
    }

    func restoreIfNeeded() async {
        guard !startedRestore else { return }
        startedRestore = true
        guard FileManager.default.fileExists(atPath: recoveryURL.path) else { isRestoring = false; return }
        do {
            let session = try JSONDecoder().decode(SavedUpdateSession.self, from: Data(contentsOf: recoveryURL))
            guard session.format == 1 else { throw CocoaError(.fileReadCorruptFile) }
            pending = session.windows
            isRestoring = true
            let hadScratch = session.windows.contains { $0.kind == .scratch }
            // Existing launch-scene registrations preceded loading the snapshot.
            for entry in Array(entries.values) { register(entry) }
            for saved in session.windows where saved.kind == .document {
                if let url = saved.fileURL, FileManager.default.fileExists(atPath: url.path) {
                    do {
                        _ = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: true)
                    } catch {
                        // Keep all text even if the file was moved or is unreadable.
                        if let index = pending.firstIndex(where: { $0.fileURL == url }) { pending[index].fileURL = nil }
                        _ = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
                    }
                } else {
                    if let index = pending.firstIndex(where: { $0.kind == .document && $0.fileURL == saved.fileURL }) {
                        pending[index].fileURL = nil
                    }
                    _ = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
                }
            }
            if !hadScratch {
                for entry in entries.values where entry.kind == .scratch { entry.window?.close() }
            }
            finishRestoringIfPossible()
        } catch {
            isRestoring = false
            // Keep the recovery file for a retry; never discard unreadable text.
            NSAlert(error: error).runModal()
        }
    }

    private func finishRestoringIfPossible() {
        guard isRestoring, pending.isEmpty, restoringCount == 0 else { return }
        isRestoring = false
        try? FileManager.default.removeItem(at: recoveryURL)
    }

    func restoreEditor(in editor: NSTextView) {
        guard let window = editor.window, let saved = editorRestorations[ObjectIdentifier(window)],
              editor.string == saved.text else { return }
        editorRestorations.removeValue(forKey: ObjectIdentifier(window))
        let count = (editor.string as NSString).length
        let location = min(count, max(0, saved.selectionLocation))
        editor.setSelectedRange(NSRange(location: location, length: min(max(0, saved.selectionLength), count - location)))
        editor.layoutManager?.ensureLayout(for: editor.textContainer!)
        if let scroll = editor.enclosingScrollView {
            scroll.contentView.scroll(to: saved.editorScroll)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    func restorePreview(in webView: WKWebView) {
        guard let window = webView.window, let y = previewRestorations.removeValue(forKey: ObjectIdentifier(window)) else { return }
        webView.callAsyncJavaScript("window.scrollTo(0, y)", arguments: ["y": y], in: nil, in: .page, completionHandler: nil)
    }
}

private func descendant<T: NSView>(_ type: T.Type, in root: NSView?) -> T? {
    guard let root else { return nil }
    if let match = root as? T { return match }
    for child in root.subviews {
        if let match = descendant(type, in: child) { return match }
    }
    return nil
}

struct SessionWindowAnchor: NSViewRepresentable {
    let id: UUID
    let kind: SessionWindowKind
    let fileURL: URL?
    @Binding var text: String
    @Binding var mode: ViewMode
    @Binding var fraction: Double

    final class AnchorView: NSView {
        var attached: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { attached?(window) }
        }
    }
    func makeNSView(context: Context) -> AnchorView { AnchorView() }
    func updateNSView(_ view: AnchorView, context: Context) {
        view.attached = { window in
            SessionRecovery.shared.register(.init(id: id, window: window, kind: kind, fileURL: fileURL,
                                                  text: $text, mode: $mode, fraction: $fraction))
        }
        if let window = view.window { view.attached?(window) }
        context.coordinator.id = id
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var id: UUID? }
    static func dismantleNSView(_ view: AnchorView, coordinator: Coordinator) {
        if let id = coordinator.id { SessionRecovery.shared.unregister(id) }
        view.attached = nil
    }
}
