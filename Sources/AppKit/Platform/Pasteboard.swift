// Pasteboard seam: the general pasteboard is the system clipboard; other named
// pasteboards stay in-process.

import Foundation

/// One clipboard entry: a type identifier (AppKit pasteboard type UTI) and its bytes.
public struct PlatformPasteboardEntry: Sendable, Equatable {
    public var type: String
    public var data: Data
    public init(type: String, data: Data) { self.type = type; self.data = data }
}

@MainActor
public protocol PlatformPasteboard: AnyObject {
    /// Replaces the clipboard contents.
    func write(_ entries: [PlatformPasteboardEntry])
    /// Reads every entry the platform can express as an AppKit type.
    func read() -> [PlatformPasteboardEntry]
    /// Increments whenever the contents change (from this or other applications).
    var changeCount: Int { get }
}
