import SwiftUI
import UniformTypeIdentifiers

@main
enum Main {
    static func main() {
        // Headless rendering skips SwiftUI: DocumentGroup's launch Open panel
        // would otherwise block the main queue.
        if let options = SnapshotRenderer.options(from: CommandLine.arguments) {
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)
            SnapshotRenderer.run(options)
            app.run()
        } else {
            // Launch into the scratch pad instead of DocumentGroup's Open panel.
            UserDefaults.standard.register(defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false])
            MarkdownViewerApp.main()
        }
    }
}

struct MarkdownViewerApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        // First scene: opened at launch. Files are optional (File > New / Open).
        Window("Scratch Pad", id: ScratchPadView.windowID) {
            ScratchPadView()
        }
        .defaultSize(width: 1280, height: 820)
        .keyboardShortcut("0", modifiers: .command)

        Settings { UpdateSettingsView() }

        Window("Software Update", id: "software-update") {
            UpdatePopover(updates: UpdateController.shared)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentContentView(text: file.$document.text, fileURL: file.fileURL)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            ViewModeCommands()
            UpdateCommands()
            CommandGroup(replacing: .help) {
                Button("Markdown Feature Tour") { FeatureTour.open() }
            }
        }
    }
}

struct UpdateCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                openWindow(id: "software-update")
                UpdateController.shared.checkFromMenu()
            }
        }
    }
}

/// An opened file takes the place of an empty launch scratch pad.
private struct DocumentContentView: View {
    @Binding var text: String
    let fileURL: URL?
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ContentView(text: $text, baseDirectory: fileURL?.deletingLastPathComponent(), fileURL: fileURL)
            .onAppear(perform: dismissEmptyScratchPad)
            .onChange(of: fileURL) { dismissEmptyScratchPad() }
    }

    private func dismissEmptyScratchPad() {
        // Wait for a real file to open successfully. New untitled documents
        // and a cancelled Open panel should leave the scratch pad alone.
        guard !SessionRecovery.shared.isRestoring, fileURL != nil, ScratchPadStore.shared.text.isEmpty else { return }
        dismissWindow(id: ScratchPadView.windowID)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await SessionRecovery.shared.restoreIfNeeded()
            UpdateController.shared.launch()
        }
    }

    /// The scratch pad is the launch window; never add an untitled document.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
}

/// View menu items mirroring the segmented control, with ⌘1 / ⌘2 / ⌘3.
struct ViewModeCommands: Commands {
    @FocusedValue(\.viewMode) private var viewMode

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            ForEach(ViewMode.allCases) { mode in
                Button(mode.title) {
                    withAnimation(.smooth(duration: 0.35)) { viewMode?.wrappedValue = mode }
                }
                .keyboardShortcut(mode.shortcut, modifiers: .command)
                .disabled(viewMode == nil)
            }
            Divider()
        }
    }
}

extension FocusedValues {
    @Entry var viewMode: Binding<ViewMode>?
}

enum FeatureTour {
    /// Opens a writable copy of the bundled sample that exercises every
    /// GitHub Markdown feature the preview supports.
    static func open() {
        guard let source = Bundle.main.url(forResource: "Feature Tour", withExtension: "md", subdirectory: "Samples") else { return }
        let directory = FileManager.default.temporaryDirectory.appending(path: "MarkdownViewerSamples", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory)
        do {
            try FileManager.default.copyItem(at: source.deletingLastPathComponent(), to: directory)
        } catch {
            NSSound.beep()
            return
        }
        NSDocumentController.shared.openDocument(
            withContentsOf: directory.appending(path: "Feature Tour.md"),
            display: true
        ) { _, _, _ in }
    }
}
