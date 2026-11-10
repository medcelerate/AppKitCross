// FileWrapper for platforms whose Foundation lacks it (swift-corelibs-foundation on
// Windows and Linux). Apple's Foundation provides the real one on macOS, and this file
// compiles to nothing there. The API follows Foundation's `FileWrapper` (`NSFileWrapper`):
// a regular file holding data, a directory holding wrappers by name, or a symbolic link.
//
// Reading and writing go through FileManager; `serializedRepresentation` (the NeXT
// serialisation used by RTFD pasteboard data) is not provided.

#if !canImport(Darwin)
import Foundation

open class FileWrapper: NSObject {
    public struct ReadingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let immediate = ReadingOptions(rawValue: 1 << 0)
        public static let withoutMapping = ReadingOptions(rawValue: 1 << 1)
    }
    public struct WritingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let atomic = WritingOptions(rawValue: 1 << 0)
        public static let withNameUpdating = WritingOptions(rawValue: 1 << 1)
    }

    private enum Kind { case regularFile(Data), directory([String: FileWrapper]), symbolicLink(URL) }
    private var kind: Kind

    open var preferredFilename: String?
    open var filename: String?
    open var fileAttributes: [String: Any] = [:]

    // MARK: Creation

    public init(regularFileWithContents contents: Data) {
        kind = .regularFile(contents)
        super.init()
    }

    public init(directoryWithFileWrappers childrenByPreferredName: [String: FileWrapper]) {
        var children: [String: FileWrapper] = [:]
        for (name, child) in childrenByPreferredName {
            if child.preferredFilename == nil { child.preferredFilename = name }
            child.filename = name
            children[name] = child
        }
        kind = .directory(children)
        super.init()
    }

    public init(symbolicLinkWithDestinationURL url: URL) {
        kind = .symbolicLink(url)
        super.init()
    }

    public convenience init(url: URL, options: ReadingOptions = []) throws {
        self.init(regularFileWithContents: Data())
        try read(from: url, options: options)
        preferredFilename = url.lastPathComponent
        filename = url.lastPathComponent
    }

    @available(*, unavailable, message: "serialized representations are not supported on this platform")
    public convenience init?(serializedRepresentation serializeRepresentation: Data) { nil }

    // MARK: Kind

    open var isRegularFile: Bool { if case .regularFile = kind { return true }; return false }
    open var isDirectory: Bool { if case .directory = kind { return true }; return false }
    open var isSymbolicLink: Bool { if case .symbolicLink = kind { return true }; return false }

    open var regularFileContents: Data? { if case .regularFile(let d) = kind { return d }; return nil }
    open var fileWrappers: [String: FileWrapper]? { if case .directory(let c) = kind { return c }; return nil }
    open var symbolicLinkDestinationURL: URL? { if case .symbolicLink(let u) = kind { return u }; return nil }

    /// Not supported on this platform (always nil).
    open var serializedRepresentation: Data? { nil }

    // MARK: Directory contents

    /// Adds `child` under its preferred name, made unique as Foundation does
    /// ("name", "name 1", "name 2"...). Returns the key used.
    @discardableResult
    open func addFileWrapper(_ child: FileWrapper) -> String {
        guard case .directory(var children) = kind else { fatalError("FileWrapper.addFileWrapper: not a directory") }
        let base = child.preferredFilename ?? "untitled"
        var name = base
        var n = 1
        while children[name] != nil {
            name = "\(base) \(n)"
            n += 1
        }
        child.filename = name
        children[name] = child
        kind = .directory(children)
        return name
    }

    @discardableResult
    open func addRegularFile(withContents data: Data, preferredFilename fileName: String) -> String {
        let child = FileWrapper(regularFileWithContents: data)
        child.preferredFilename = fileName
        return addFileWrapper(child)
    }

    open func removeFileWrapper(_ child: FileWrapper) {
        guard case .directory(var children) = kind else { return }
        for (name, c) in children where c === child { children[name] = nil }
        kind = .directory(children)
    }

    open func keyForChildFileWrapper(_ child: FileWrapper) -> String? {
        guard case .directory(let children) = kind else { return nil }
        return children.first { $0.value === child }?.key
    }

    // MARK: Reading and writing

    /// Whether the wrapper's contents could differ from what is on disk at `url`: true
    /// when the file's modification date or size differ from the attributes recorded at the
    /// last read or write, or when nothing was recorded.
    open func matchesContents(of url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return false }
        guard let recordedDate = fileAttributes[FileAttributeKey.modificationDate.rawValue] as? Date,
              let date = attrs[.modificationDate] as? Date else { return false }
        if recordedDate != date { return false }
        if let recordedSize = fileAttributes[FileAttributeKey.size.rawValue] as? UInt64, let size = attrs[.size] as? UInt64, recordedSize != size { return false }
        return true
    }

    open func read(from url: URL, options: ReadingOptions = []) throws {
        let fm = FileManager.default
        let attrs = try fm.attributesOfItem(atPath: url.path)
        let type = attrs[.type] as? FileAttributeType
        if type == .typeSymbolicLink {
            let dest = try fm.destinationOfSymbolicLink(atPath: url.path)
            kind = .symbolicLink(URL(fileURLWithPath: dest, relativeTo: url.deletingLastPathComponent()))
        } else if type == .typeDirectory {
            var children: [String: FileWrapper] = [:]
            for name in try fm.contentsOfDirectory(atPath: url.path) {
                let child = try FileWrapper(url: url.appendingPathComponent(name), options: options)
                children[name] = child
            }
            kind = .directory(children)
        } else {
            kind = .regularFile(try Data(contentsOf: url))
        }
        var recorded: [String: Any] = [:]
        for (k, v) in attrs { recorded[k.rawValue] = v }
        fileAttributes = recorded
        if filename == nil { filename = url.lastPathComponent }
        if preferredFilename == nil { preferredFilename = url.lastPathComponent }
    }

    open func write(to url: URL, options: WritingOptions = [], originalContentsURL: URL?) throws {
        let fm = FileManager.default
        switch kind {
        case .regularFile(let data):
            try data.write(to: url, options: options.contains(.atomic) ? [.atomic] : [])
        case .symbolicLink(let dest):
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            try fm.createSymbolicLink(at: url, withDestinationURL: dest)
        case .directory(let children):
            if fm.fileExists(atPath: url.path) {
                // Replace the directory's contents: remove entries that are no longer there.
                for name in (try? fm.contentsOfDirectory(atPath: url.path)) ?? [] where children[name] == nil {
                    try? fm.removeItem(at: url.appendingPathComponent(name))
                }
            } else {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
            for (name, child) in children {
                try child.write(to: url.appendingPathComponent(name), options: options, originalContentsURL: originalContentsURL?.appendingPathComponent(name))
            }
        }
        if options.contains(.withNameUpdating) { filename = url.lastPathComponent }
        if let attrs = try? fm.attributesOfItem(atPath: url.path) {
            var recorded: [String: Any] = [:]
            for (k, v) in attrs { recorded[k.rawValue] = v }
            fileAttributes = recorded
        }
    }
}
#endif
