import AppKit

/// Lightweight regex-based syntax colouring for the Markdown source.
enum MarkdownHighlighter {
    static let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)

    static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.2
        return style
    }

    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraphStyle]
    }

    private struct Rule {
        let regex: NSRegularExpression
        let attributes: [NSAttributedString.Key: Any]
        var group = 0
    }

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = [.anchorsMatchLines]) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let rules: [Rule] = [
        Rule(regex: regex(#"^#{1,6}[ \t].*$"#), attributes: [.font: boldFont, .foregroundColor: NSColor.systemBlue]),
        Rule(regex: regex(#"^(?:[ \t]*)(?:[-*+]|\d+[.)])(?=[ \t])"#), attributes: [.foregroundColor: NSColor.systemOrange]),
        Rule(regex: regex(#"^[ \t]*>.*$"#), attributes: [.foregroundColor: NSColor.secondaryLabelColor]),
        Rule(regex: regex(#"^\s*(?:[-*_][ \t]*){3,}$"#), attributes: [.foregroundColor: NSColor.tertiaryLabelColor]),
        Rule(regex: regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#), attributes: [.font: boldFont]),
        Rule(regex: regex(#"(?<![*\w])([*_])(?=\S)([^*_\n]+?)(?<=\S)\1(?![*\w])"#), attributes: [.obliqueness: 0.15]),
        Rule(regex: regex(#"~~(?=\S).+?(?<=\S)~~"#), attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: NSColor.secondaryLabelColor]),
        Rule(regex: regex(#"!?\[[^\]\n]*\]\([^)\n]*\)"#), attributes: [.foregroundColor: NSColor.systemPurple]),
        Rule(regex: regex(#"<\/?[a-zA-Z][^>\n]*>"#), attributes: [.foregroundColor: NSColor.systemTeal]),
        Rule(regex: regex(#"`[^`\n]+`"#), attributes: [.foregroundColor: NSColor.systemPink]),
        Rule(regex: regex(#"\$`[^`\n]+`\$|\$\$[\s\S]+?\$\$"#), attributes: [.foregroundColor: NSColor.systemGreen]),
        Rule(regex: regex(#"^[ \t]*(```|~~~).*?$[\s\S]*?^[ \t]*\1[ \t]*$"#), attributes: [.foregroundColor: NSColor.systemBrown]),
    ]

    static func highlight(_ storage: NSTextStorage) {
        let full = NSRange(location: 0, length: storage.length)
        // Very large documents only get base styling to keep typing smooth.
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: full)
        if storage.length < 400_000 {
            let string = storage.string
            for rule in rules {
                rule.regex.enumerateMatches(in: string, range: full) { match, _, _ in
                    guard let range = match?.range(at: rule.group), range.location != NSNotFound else { return }
                    storage.addAttributes(rule.attributes, range: range)
                }
            }
        }
        storage.endEditing()
    }
}
