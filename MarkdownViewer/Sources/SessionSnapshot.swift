import Foundation
import CoreGraphics

nonisolated enum SessionWindowKind: String, Codable { case scratch, document }

nonisolated struct SavedWindowSession: Codable {
    var kind: SessionWindowKind
    var fileURL: URL?
    var text: String
    var mode: String
    var fraction: Double
    var frame: CGRect
    var selectionLocation: Int
    var selectionLength: Int
    var editorScroll: CGPoint
    var previewScroll: Double
    var minimized: Bool
    var key: Bool
}

nonisolated struct SavedUpdateSession: Codable {
    let format: Int
    let windows: [SavedWindowSession]
}
