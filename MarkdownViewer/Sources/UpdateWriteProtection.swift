import Foundation
import Synchronization

/// FileDocument may be asked to autosave while AppKit terminates for an update.
/// The current text is already in the durable recovery snapshot at that point;
/// preserve existing on-disk bytes instead of converting unsaved edits to saves.
nonisolated enum UpdateWriteProtection {
    private static let state = Mutex(false)
    static var isActive: Bool { state.withLock { $0 } }
    static func setActive(_ active: Bool) { state.withLock { $0 = active } }
    static func dataForWrite(text: String, existing: Data?) -> Data {
        if isActive, let existing { return existing }
        return Data(text.utf8)
    }
}
