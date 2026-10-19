import Foundation

/// Links the editor and preview scroll positions by source line.
///
/// Each pane registers a closure that scrolls it to a (fractional) line and
/// reports its own user-driven scrolling. A pane ignores the scroll events it
/// receives right after being scrolled programmatically, which prevents the
/// two panes from chasing each other.
final class ScrollSync {
    var scrollEditor: ((Double) -> Void)?
    var scrollPreview: ((Double) -> Void)?

    private var editorQuietUntil = Date.distantPast
    private var previewQuietUntil = Date.distantPast
    private let quietPeriod: TimeInterval = 0.25

    func editorDidScroll(toLine line: Double) {
        guard Date.now > editorQuietUntil else { return }
        previewQuietUntil = .now + quietPeriod
        scrollPreview?(line)
    }

    func previewDidScroll(toLine line: Double) {
        guard Date.now > previewQuietUntil else { return }
        editorQuietUntil = .now + quietPeriod
        scrollEditor?(line)
    }
}
