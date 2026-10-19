import Foundation

@main
struct UpdateModelTests {
    static func main() throws {
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message)
        }
        expect(AppVersion("0.1.10")! > AppVersion("0.1.9")!, "Numeric versions must not sort lexically")
        expect(AppVersion("1.0.1")! > AppVersion("0.99.999")!, "Release series must order before build")
        expect(AppVersion("1.2") == nil && AppVersion("1..2") == nil && AppVersion("1.2.-1") == nil, "Reject malformed versions")
        let asset = GitHubRelease.Asset(name: "MarkdownViewer-0.1.10-development.zip", browser_download_url: URL(string: "https://github.com/example/app/releases/download/dev-0.1.10/MarkdownViewer-0.1.10-development.zip")!)
        let feed = GitHubRelease.Asset(name: "appcast.xml", browser_download_url: URL(string: "https://github.com/example/app/releases/download/dev-0.1.10/appcast.xml")!)
        let preview = GitHubRelease(tag_name: "dev-0.1.10", name: nil, body: nil, draft: false, prerelease: true, assets: [asset, feed])
        expect(preview.candidate(repository: "example/app", channel: .stable) == nil, "Stable must exclude previews")
        expect(preview.candidate(repository: "example/app", channel: .development)?.version == "0.1.10", "Development accepts complete previews")
        expect(preview.candidate(repository: "other/app", channel: .development) == nil, "Reject cross-repository asset URLs")
        let incomplete = GitHubRelease(tag_name: preview.tag_name, name: nil, body: nil, draft: false, prerelease: true, assets: [feed])
        expect(incomplete.candidate(repository: "example/app", channel: .development) == nil, "A feed without the archive is not an update")
        let draft = GitHubRelease(tag_name: preview.tag_name, name: nil, body: nil, draft: true, prerelease: true, assets: [asset, feed])
        expect(draft.candidate(repository: "example/app", channel: .development) == nil, "Exclude draft releases")
        let saved = SavedWindowSession(kind: .document, fileURL: URL(fileURLWithPath: "/tmp/example.md"),
            text: "Unsaved text 📝\n", mode: "preview", fraction: 0.37, frame: CGRect(x: 10, y: 20, width: 1100, height: 700),
            selectionLocation: 3, selectionLength: 2, editorScroll: CGPoint(x: 0, y: 123), previewScroll: 456,
            minimized: false, key: true)
        let data = try JSONEncoder().encode(SavedUpdateSession(format: 1, windows: [saved]))
        let restored = try JSONDecoder().decode(SavedUpdateSession.self, from: data).windows[0]
        expect(restored.text == saved.text && restored.fileURL == saved.fileURL, "Preserve unsaved text and original destination")
        expect(restored.frame == saved.frame && restored.mode == saved.mode && restored.selectionLocation == 3 && restored.previewScroll == 456, "Preserve window and editor state")
        let original = Data("original saved text".utf8)
        UpdateWriteProtection.setActive(true)
        expect(UpdateWriteProtection.dataForWrite(text: "unsaved edits", existing: original) == original, "Update termination must not save over original file bytes")
        expect(UpdateWriteProtection.dataForWrite(text: "new draft", existing: nil) == Data("new draft".utf8), "Untitled recovery drafts retain their text")
        UpdateWriteProtection.setActive(false)
        expect(UpdateWriteProtection.dataForWrite(text: "explicit save", existing: original) == Data("explicit save".utf8), "Normal saves must retain their ordinary behavior")
        print("Update selection and session snapshot tests passed.")
    }
}
