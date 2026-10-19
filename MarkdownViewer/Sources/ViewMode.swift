import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case split
    case source
    case preview

    var id: Self { self }

    var title: String {
        switch self {
        case .split: "Side by Side"
        case .source: "Source"
        case .preview: "Preview"
        }
    }

    var systemImage: String {
        switch self {
        case .split: "rectangle.split.2x1"
        case .source: "chevron.left.forwardslash.chevron.right"
        case .preview: "eye"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .split: "1"
        case .source: "2"
        case .preview: "3"
        }
    }
}
