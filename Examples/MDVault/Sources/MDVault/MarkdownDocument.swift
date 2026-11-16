import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist under UTImportedTypeDeclarations.
    static let markdownText = UTType(importedAs: "net.daringfireball.markdown")
}

struct MarkdownDocument: FileDocument {
    var text: String

    init(text: String = "") { self.text = text }

    static var readableContentTypes: [UTType] { [.markdownText, .plainText, .text] }
    static var writableContentTypes: [UTType] { [.markdownText, .plainText] }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else {
            // Fall back to the platform default before giving up on the file.
            text = String(data: data, encoding: .isoLatin1) ?? ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
