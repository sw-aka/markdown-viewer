import SwiftUI

/// Editor + preview window content, shared by document windows and the
/// scratch pad.
struct ContentView: View {
    @Binding var text: String
    /// Folder that relative links and images resolve against, if any.
    let baseDirectory: URL?

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
        .frame(minWidth: 640, minHeight: 400)
        // WebKit repaints asynchronously while the split animates. Keep the
        // exposed area the same color as the renderer until its tiles arrive.
        .background(colorScheme == .dark
            ? Color(red: 13 / 255, green: 17 / 255, blue: 23 / 255)
            : Color.white)
        .toolbar {
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
