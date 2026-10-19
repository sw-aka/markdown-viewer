import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The scratch pad's text, saved automatically to Application Support so it
/// survives quitting without ever asking to save.
@Observable
final class ScratchPadStore {
    static let shared = ScratchPadStore()

    var text: String {
        didSet { scheduleSave() }
    }

    let fileURL: URL
    private var saveTask: Task<Void, Never>?

    private init() {
        let folder = URL.applicationSupportDirectory.appending(path: "Markdown Viewer", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appending(path: "Scratch Pad.md")
        if let data = try? Data(contentsOf: fileURL), let saved = try? MarkdownDocument.decode(data) {
            text = saved
        } else {
            text = ""
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        try? Data(text.utf8).write(to: fileURL, options: .atomic)
    }
}

struct ScratchPadView: View {
    static let windowID = "scratch-pad"

    @State private var store = ScratchPadStore.shared

    var body: some View {
        ContentView(text: $store.text, baseDirectory: nil)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Save as File…", systemImage: "square.and.arrow.down", action: saveAsFile)
                        .help("Save the scratch pad as a Markdown file")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                store.saveNow()
            }
    }

    /// Writes the scratch pad to a file of the user's choice and opens that
    /// file as a document. The scratch pad itself keeps its text.
    private func saveAsFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.markdownText]
        panel.nameFieldStringValue = "Untitled.md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(store.text.utf8).write(to: url, options: .atomic)
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
