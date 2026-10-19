import AppKit
import SwiftUI

/// Plain-text Markdown editor backed by NSTextView, with light syntax colouring.
struct SourceEditor: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.isEnabled) private var isEnabled
    let scrollSync: ScrollSync
    let syncEnabled: Bool
    /// False while the editor is collapsed (Preview mode): it then gives up focus.
    var isActive = true
    /// True in Source-only mode: the editor takes focus when shown.
    var takesFocus = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = true

        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 18, height: 20)
        textView.font = MarkdownHighlighter.baseFont
        textView.typingAttributes = MarkdownHighlighter.baseAttributes
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .controlAccentColor
        textView.setAccessibilityIdentifier("SourceEditor")

        textView.string = text
        if let storage = textView.textStorage { MarkdownHighlighter.highlight(storage) }
        context.coordinator.textView = textView

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollSync.scrollEditor = { [weak coordinator = context.coordinator] line in
            coordinator?.scroll(toLine: line)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        textView.isEditable = isEnabled
        if textView.string != text {
            // External change (revert, document undo): the editor's own undo
            // stack no longer matches the text.
            context.coordinator.undoManager.removeAllActions()
            let length = (text as NSString).length
            let selection = textView.selectedRanges.map { value -> NSValue in
                let range = value.rangeValue
                let location = min(range.location, length)
                return NSValue(range: NSRange(location: location, length: min(range.length, length - location)))
            }
            textView.string = text
            if let storage = textView.textStorage { MarkdownHighlighter.highlight(storage) }
            textView.selectedRanges = selection.isEmpty ? [NSValue(range: NSRange(location: length, length: 0))] : selection
        }
        // Keystrokes must not go to a collapsed editor.
        let focus = takesFocus && !context.coordinator.hadFocusRequest
        let active = isActive
        DispatchQueue.main.async { [weak textView] in
            guard let textView, let window = textView.window else { return }
            if !active, window.firstResponder === textView {
                window.makeFirstResponder(nil)
            } else if focus {
                window.makeFirstResponder(textView)
            }
        }
        SessionRecovery.shared.restoreEditor(in: textView)
        context.coordinator.hadFocusRequest = takesFocus
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceEditor
        weak var textView: NSTextView?
        var hadFocusRequest = false
        /// The editor keeps its own undo stack (fine-grained typing undo),
        /// separate from the document's, which SwiftUI also writes to.
        let undoManager = UndoManager()

        func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

        init(_ parent: SourceEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            if let storage = textView.textStorage { MarkdownHighlighter.highlight(storage) }
            parent.text = textView.string
        }

        // MARK: Scroll sync

        @objc func boundsDidChange(_ notification: Notification) {
            guard parent.syncEnabled, let line = topVisibleLine() else { return }
            parent.scrollSync.editorDidScroll(toLine: line)
        }

        /// Fractional source line at the top of the visible area.
        private func topVisibleLine() -> Double? {
            guard let textView, let layoutManager = textView.layoutManager,
                  let container = textView.textContainer else { return nil }
            let visible = textView.visibleRect
            if visible.minY <= 0 { return 0 }
            let point = NSPoint(x: 0, y: visible.minY - textView.textContainerOrigin.y)
            let glyph = layoutManager.glyphIndex(for: point, in: container)
            let charIndex = layoutManager.characterIndexForGlyph(at: glyph)
            let string = textView.string as NSString
            let lineRange = string.lineRange(for: NSRange(location: min(charIndex, string.length), length: 0))
            let line = Double(lineNumber(at: lineRange.location, in: string))
            // Interpolate within a wrapped line for smooth syncing.
            let lineRect = layoutManager.boundingRect(
                forGlyphRange: layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil),
                in: container
            )
            guard lineRect.height > 0 else { return line }
            let progress = (point.y - lineRect.minY) / lineRect.height
            return line + min(max(progress, 0), 1)
        }

        func scroll(toLine line: Double) {
            guard parent.syncEnabled, let textView, let layoutManager = textView.layoutManager,
                  let container = textView.textContainer, let scrollView = textView.enclosingScrollView else { return }
            let string = textView.string as NSString
            let whole = Int(line)
            let start = characterIndex(ofLine: whole, in: string)
            let lineRange = string.lineRange(for: NSRange(location: start, length: 0))
            layoutManager.ensureLayout(forCharacterRange: lineRange)
            let rect = layoutManager.boundingRect(
                forGlyphRange: layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil),
                in: container
            )
            let y = rect.minY + rect.height * (line - Double(whole)) + textView.textContainerOrigin.y
            let maxY = max(0, textView.frame.height - scrollView.contentView.bounds.height)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, y - textView.textContainerOrigin.y), maxY)))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func lineNumber(at location: Int, in string: NSString) -> Int {
            var count = 0
            var index = 0
            while index < location {
                let range = string.range(of: "\n", options: [], range: NSRange(location: index, length: location - index))
                if range.location == NSNotFound { break }
                count += 1
                index = range.location + 1
            }
            return count
        }

        private func characterIndex(ofLine line: Int, in string: NSString) -> Int {
            var index = 0
            var current = 0
            while current < line, index < string.length {
                let range = string.range(of: "\n", options: [], range: NSRange(location: index, length: string.length - index))
                if range.location == NSNotFound { return string.length }
                index = range.location + 1
                current += 1
            }
            return min(index, string.length)
        }
    }
}
