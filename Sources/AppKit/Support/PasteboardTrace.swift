// Pasteboard diagnostics (ADR-0030). `APPKITWIN_TRACE_PASTEBOARD=1` logs to stderr every
// system clipboard read (raw platform formats, the AppKit types they resolve to), the
// general pasteboard's sync decisions, menu validation of the paste items (which target was
// asked and its answer) and NSTextView's paste validation. Any other value is a file path
// the lines are appended to (for GUI launches without a console).

import Foundation

enum _PasteboardTrace {
    static let destination: String? = {
        guard let v = ProcessInfo.processInfo.environment["APPKITWIN_TRACE_PASTEBOARD"], !v.isEmpty, v != "0" else { return nil }
        return v
    }()
    static var enabled: Bool { destination != nil }

    static func log(_ message: @autoclosure () -> String) {
        guard let destination else { return }
        let line = Data("[pasteboard] \(message())\n".utf8)
        if destination == "1" {
            FileHandle.standardError.write(line)
        } else if let h = FileHandle(forWritingAtPath: destination) ?? {
            FileManager.default.createFile(atPath: destination, contents: nil)
            return FileHandle(forWritingAtPath: destination)
        }() {
            h.seekToEndOfFile()
            h.write(line)
            h.closeFile()
        }
    }
}
