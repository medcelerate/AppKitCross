import Foundation

public struct TodoDocumentStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    public static let privateDirectoryPermissions: Int = 0o700
    public static let privateFilePermissions: Int = 0o600

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() -> TodoDocument {
        guard let data = try? Data(contentsOf: fileURL) else {
            return TodoDocument()
        }

        do {
            return try decoder.decode(TodoDocument.self, from: data)
        } catch {
            let backupURL = fileURL.appendingPathExtension("invalid")
            try? fileManager.removeItem(at: backupURL)
            try? writePrivateFile(data, to: backupURL)
            return TodoDocument()
        }
    }

    public func save(_ document: TodoDocument) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try applyPOSIXPermissions(
            TodoDocumentStore.privateDirectoryPermissions,
            to: directoryURL
        )
        let data = try encoder.encode(document)
        try writePrivateFile(data, to: fileURL)
    }

    private func writePrivateFile(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try applyPOSIXPermissions(TodoDocumentStore.privateFilePermissions, to: url)
    }

    private func applyPOSIXPermissions(_ permissions: Int, to url: URL) throws {
        try fileManager.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: url.path
        )
    }
}
