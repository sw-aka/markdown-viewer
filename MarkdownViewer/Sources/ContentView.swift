import SwiftUI

/// Editor + preview window content, shared by document windows and the
/// scratch pad.
struct ContentView: View {
    @Binding var text: String
    /// Folder that relative links and images resolve against, if any.
    let baseDirectory: URL?
    var sessionKind: SessionWindowKind = .document
    var fileURL: URL? = nil
    var saveAsFile: (() -> Void)? = nil
    @State private var sessionID = UUID()

    @Environment(\.colorScheme) private var colorScheme
    @SceneStorage("viewMode") private var mode: ViewMode = .split
    @AppStorage("splitFraction") private var splitFraction: Double = 0.5
    @State private var scrollSync = ScrollSync()

    var body: some View {
        EditorPreviewSplit(mode: mode, fraction: $splitFraction) {
            SourceEditor(
                text: $text,
                scrollSync: scrollSync,
                syncEnabled: mode == .split,
                isActive: mode != .preview,
                takesFocus: mode == .source
            )
        } trailing: {
            MarkdownPreview(
                markdown: text,
                baseDirectory: baseDirectory,
                scrollSync: scrollSync,
                syncEnabled: mode == .split,
                isActive: mode != .source
            )
        }
        .disabled(UpdateController.shared.isInstalling)
        .allowsHitTesting(!UpdateController.shared.isInstalling)
        .background {
            SessionWindowAnchor(id: sessionID, kind: sessionKind, fileURL: fileURL,
                                text: $text, mode: $mode, fraction: $splitFraction)
                .frame(width: 0, height: 0)
        }
        .frame(minWidth: 640, minHeight: 400)
        // WebKit repaints asynchronously while the split animates. Keep the
        // exposed area the same color as the renderer until its tiles arrive.
        .background(colorScheme == .dark
            ? Color(red: 13 / 255, green: 17 / 255, blue: 23 / 255)
            : Color.white)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 14) {
                    UpdateToolbarItem()
                    if let saveAsFile {
                        Button(action: saveAsFile) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 16))
                                .frame(width: 28, height: 28)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel("Save as File…")
                        .help("Save the scratch pad as a Markdown file")
                    }
                }
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .principal) {
                GlassSegmentedControl(
                    selection: $mode.animation(.smooth(duration: 0.35)),
                    segments: ViewMode.allCases.map { .init(value: $0, title: $0.title, systemImage: $0.systemImage) }
                )
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .focusedSceneValue(\.viewMode, $mode)
    }
}
