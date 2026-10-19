import SwiftUI
import UniformTypeIdentifiers

nonisolated extension UTType {
    static let markdownText = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

nonisolated struct MarkdownDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.markdownText, .plainText]
    static let writableContentTypes: [UTType] = [.markdownText, .plainText]

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = try Self.decode(data)
    }

    /// Strict UTF-8 first, then whatever encoding Foundation detects. Never
    /// replaces bytes with U+FFFD, which would corrupt the file on save.
    /// A leading byte order mark is dropped (GitHub ignores it too).
    static func decode(_ data: Data) throws -> String {
        var string: String
        if let utf8 = String(data: data, encoding: .utf8) {
            string = utf8
        } else {
            var converted: NSString?
            let encoding = NSString.stringEncoding(for: data, encodingOptions: [.allowLossyKey: false], convertedString: &converted, usedLossyConversion: nil)
            guard encoding != 0, let converted else { throw CocoaError(.fileReadInapplicableStringEncoding) }
            string = converted as String
        }
        if string.hasPrefix("\u{FEFF}") { string.removeFirst() }
        return string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
