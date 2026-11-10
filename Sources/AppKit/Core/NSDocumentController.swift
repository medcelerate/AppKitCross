// NSDocumentController (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
//
// The shared controller keeps the open documents, the document types the application
// declares, the recent-documents list and the File menu's New, Open, Open Recent and
// Save All actions (ADR-0017).
//
// Document types come from `CFBundleDocumentTypes` in the application's Info.plist, as
// on macOS. Windows and Linux executables have no bundle, so the dictionary is looked
// up in this order: the file `APPKITWIN_INFO_PLIST` names, `Info.plist` next to the
// executable, then `Bundle.main.infoDictionary` (which on corelibs Foundation is the
// same adjacent file). Each entry's `LSItemContentTypes` (UTIs) name the type;
// `CFBundleTypeExtensions`, `CFBundleTypeRole` (Editor, Viewer), `NSDocumentClass`
// ("Module.Class", resolved through the Swift runtime) and `NSExportableTypes` are
// honoured; `UTExportedTypeDeclarations`/`UTImportedTypeDeclarations` register their
// identifiers and extensions with `UTType`.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(QuartzCore)
import QuartzCore
#endif
#if canImport(CoreText)
import CoreText
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller
@MainActor open class NSDocumentController: NSObject, NSCoding, NSMenuItemValidation, NSUserInterfaceValidations, NSWindowRestoration, NSSelectorHandling {
    // MARK: Storage
    internal static var _shared: NSDocumentController? = nil
    /// Test hook: stands in for the application's Info.plist when set.
    internal static var _infoDictionaryOverride: [String: Any]? = nil

    /// One `CFBundleDocumentTypes` entry.
    internal struct _DocumentType {
        var name: String
        var contentTypes: [String]
        var extensions: [String]
        var role: String
        var className: String?
        var isPackage: Bool
        var exportableTypes: [String]
        /// The name documents use for this type: its first UTI, else the bundle type name.
        var typeName: String { contentTypes.first ?? name }
        var isEditor: Bool { role.caseInsensitiveCompare("Editor") == .orderedSame }
        var isViewerOrEditor: Bool { isEditor || role.caseInsensitiveCompare("Viewer") == .orderedSame }
    }
    internal private(set) var _types: [_DocumentType] = []
    private var _documents: [NSDocument] = []
    private var _autosavingDelay: TimeInterval = 0
    private var _untitledCounter = 0
    private var _recentURLs: [URL] = []
    private var _maximumRecentDocumentCount: Int = 10
    private weak var _recentMenu: NSMenu?
    private static let _recentDefaultsKey = "NSRecentDocumentPaths"
    private static let _recentLimitDefaultsKey = "NSRecentDocumentsLimit"

    // MARK: Creation

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/init()
    /// The first controller created becomes `shared`, as on macOS.
    @MainActor public override init() {
        super.init()
        _types = NSDocumentController._documentTypes(from: NSDocumentController._infoDictionary())
        _loadRecents()
        if NSDocumentController._shared == nil { NSDocumentController._shared = self }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/init(coder:)
    @MainActor public required init?(coder: NSCoder) {
        super.init()
        _types = NSDocumentController._documentTypes(from: NSDocumentController._infoDictionary())
        _loadRecents()
        if NSDocumentController._shared == nil { NSDocumentController._shared = self }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/shared
    @MainActor class public var shared: NSDocumentController {
        if let s = _shared { return s }
        return NSDocumentController()
    }

    // MARK: Info.plist

    /// The application's Info.plist dictionary (see the file comment for the lookup).
    internal static func _infoDictionary() -> [String: Any] {
        if let o = _infoDictionaryOverride { return o }
        let env = ProcessInfo.processInfo.environment
        var candidates: [URL] = []
        if let p = env["APPKITWIN_INFO_PLIST"], !p.isEmpty { candidates.append(URL(fileURLWithPath: p)) }
        if let exe = Bundle.main.executableURL ?? CommandLine.arguments.first.map({ URL(fileURLWithPath: $0) }) {
            candidates.append(exe.deletingLastPathComponent().appendingPathComponent("Info.plist"))
        }
        for url in candidates {
            if let data = try? Data(contentsOf: url),
               let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                return plist
            }
        }
        return Bundle.main.infoDictionary ?? [:]
    }

    /// Whether the application declares document types (NSApplication then creates the
    /// shared controller at launch).
    internal static var _applicationDeclaresDocumentTypes: Bool {
        !((_infoDictionary()["CFBundleDocumentTypes"] as? [[String: Any]]) ?? []).isEmpty
    }

    /// Parses `CFBundleDocumentTypes` and registers the UTI declarations.
    internal static func _documentTypes(from info: [String: Any]) -> [_DocumentType] {
        for key in ["UTExportedTypeDeclarations", "UTImportedTypeDeclarations"] {
            for decl in (info[key] as? [[String: Any]]) ?? [] {
                guard let identifier = decl["UTTypeIdentifier"] as? String else { continue }
                let parents = (decl["UTTypeConformsTo"] as? [String]) ?? []
                let tags = decl["UTTypeTagSpecification"] as? [String: Any]
                let extensions = (tags?["public.filename-extension"] as? [String]) ?? (tags?["public.filename-extension"] as? String).map { [$0] } ?? []
                let mimeTypes = (tags?["public.mime-type"] as? [String]) ?? (tags?["public.mime-type"] as? String).map { [$0] } ?? []
                #if canImport(Darwin)
                // Apple's UTType reads declarations from the bundle; nothing to feed it.
                _ = (identifier, parents, extensions, mimeTypes)
                #else
                UTType._declare(identifier: identifier, conformsTo: parents, extensions: extensions, mimeTypes: mimeTypes,
                                description: decl["UTTypeDescription"] as? String, exported: key == "UTExportedTypeDeclarations")
                #endif
            }
        }
        var types: [_DocumentType] = []
        for entry in (info["CFBundleDocumentTypes"] as? [[String: Any]]) ?? [] {
            let contentTypes = (entry["LSItemContentTypes"] as? [String]) ?? []
            let extensions = ((entry["CFBundleTypeExtensions"] as? [String]) ?? []).map { $0.lowercased() }.filter { $0 != "*" }
            let name = (entry["CFBundleTypeName"] as? String) ?? contentTypes.first ?? extensions.first ?? "Document"
            types.append(_DocumentType(name: name, contentTypes: contentTypes, extensions: extensions,
                                       role: (entry["CFBundleTypeRole"] as? String) ?? "Editor",
                                       className: entry["NSDocumentClass"] as? String,
                                       isPackage: (entry["LSTypeIsPackage"] as? Bool) ?? false,
                                       exportableTypes: (entry["NSExportableTypes"] as? [String]) ?? []))
        }
        return types
    }

    internal func _type(named typeName: String) -> _DocumentType? {
        _types.first { $0.typeName == typeName || $0.contentTypes.contains(typeName) || $0.name == typeName }
    }

    /// Resolves an `NSDocumentClass` name: "Module.Class" through the Swift runtime, a
    /// bare name against the executable's module.
    internal static func _class(named name: String) -> NSDocument.Type? {
        #if canImport(ObjectiveC)
        if let c = NSClassFromString(name) as? NSDocument.Type { return c }
        #endif
        if let t = _typeByName(name) as? NSDocument.Type { return t }
        if !name.contains(".") {
            let module = (_infoDictionary()["CFBundleExecutable"] as? String) ?? (CommandLine.arguments.first.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension } ?? "")
            if !module.isEmpty, let t = _typeByName("\(module).\(name)") as? NSDocument.Type { return t }
        }
        return nil
    }

    internal func _readableTypes(forDocumentClass cls: NSDocument.Type) -> [String] {
        var out: [String] = []
        for t in _types where t.isViewerOrEditor && _documentClass(for: t) == cls {
            for c in t.contentTypes.isEmpty ? [t.typeName] : t.contentTypes where !out.contains(c) { out.append(c) }
        }
        return out
    }

    internal func _writableTypes(forDocumentClass cls: NSDocument.Type) -> [String] {
        var out: [String] = []
        for t in _types where _documentClass(for: t) == cls {
            if t.isEditor { for c in t.contentTypes.isEmpty ? [t.typeName] : t.contentTypes where !out.contains(c) { out.append(c) } }
            for e in t.exportableTypes where !out.contains(e) { out.append(e) }
        }
        return out
    }

    /// The class of a type: its `NSDocumentClass`, or the one class the application has
    /// when no entry names one (an application with a single `NSDocument` subclass).
    private func _documentClass(for t: _DocumentType) -> NSDocument.Type? {
        if let n = t.className, let c = NSDocumentController._class(named: n) { return c }
        let named = Set(_types.compactMap { $0.className })
        if named.count == 1, let only = named.first { return NSDocumentController._class(named: only) }
        return nil
    }

    internal func _fileNameExtension(forType typeName: String) -> String? {
        if let t = _type(named: typeName), let e = t.extensions.first { return e }
        return UTType(typeName)?.preferredFilenameExtension
    }

    internal var _autosaveDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let app = (NSDocumentController._infoDictionary()["CFBundleName"] as? String) ?? (CommandLine.arguments.first.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension } ?? "AppKitCross")
        return base.appendingPathComponent(app).appendingPathComponent("Autosave Information")
    }

    // MARK: Types

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/defaulttype
    /// The first type with the Editor role.
    @MainActor open var defaultType: String? { _types.first { $0.isEditor }?.typeName ?? _types.first?.typeName }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/displayname(fortype:)
    @MainActor open func displayName(forType typeName: String) -> String? {
        if let t = _type(named: typeName) { return t.name }
        return UTType(typeName)?.localizedDescription
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/documentclass(fortype:)
    @MainActor open func documentClass(forType typeName: String) -> AnyClass? {
        guard let t = _type(named: typeName) else { return nil }
        return _documentClass(for: t)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/documentclassnames
    @MainActor open var documentClassNames: [String] {
        var out: [String] = []
        for t in _types { if let n = t.className, !out.contains(n) { out.append(n) } }
        return out
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/typeforcontents(of:)
    /// The declared type the file's extension conforms to (through `UTType`), else the
    /// one that lists the extension; otherwise an unknown-type error.
    @MainActor open func typeForContents(of url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        var isDir: ObjCBool = false
        let isDirectory = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        if !ext.isEmpty, let fileType = UTType(filenameExtension: ext) {
            // The file's own type first (public.log before the public.plain-text it conforms to).
            for t in _types where t.isViewerOrEditor {
                for c in t.contentTypes where c.caseInsensitiveCompare(fileType.identifier) == .orderedSame { return c }
            }
            // Else a declared type it conforms to: the first in declaration order, unless a
            // later one is a subtype of it (so list specific types before general ones in
            // CFBundleDocumentTypes, as Apple's guidance says).
            var best: UTType? = nil
            for t in _types where t.isViewerOrEditor {
                for c in t.contentTypes {
                    guard let declared = UTType(c), fileType.conforms(to: declared) else { continue }
                    if let b = best { if declared.conforms(to: b) { best = declared } } else { best = declared }
                }
            }
            if let best { return best.identifier }
        }
        for t in _types where t.isViewerOrEditor && t.extensions.contains(ext) { return t.typeName }
        if isDirectory, let folder = _types.first(where: { $0.isViewerOrEditor && $0.contentTypes.contains("public.folder") }) { return folder.typeName }
        throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileReadUnknown.rawValue,
                      userInfo: [NSLocalizedDescriptionKey: "The document \u{201c}\(url.lastPathComponent)\u{201d} could not be opened.",
                                 NSLocalizedFailureReasonErrorKey: ext.isEmpty ? "The file has no extension the application knows." : "The application cannot open files of type \u{201c}\(ext)\u{201d}.",
                                 NSURLErrorKey: url])
    }

    // MARK: Documents

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/documents
    @MainActor open var documents: [NSDocument] { _documents }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/adddocument(_:)
    @MainActor open func addDocument(_ document: NSDocument) {
        guard !_documents.contains(where: { $0 === document }) else { return }
        _documents.append(document)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/removedocument(_:)
    @MainActor open func removeDocument(_ document: NSDocument) {
        _documents.removeAll { $0 === document }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/currentdocument
    /// The main window's document.
    @MainActor open var currentDocument: NSDocument? {
        if let w = NSApplication.shared.mainWindow, let d = document(for: w) { return d }
        if let w = NSApplication.shared.keyWindow, let d = document(for: w) { return d }
        return nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/currentdirectory
    @MainActor open var currentDirectory: String? {
        (currentDocument?.fileURL ?? NSSavePanel._lastDirectory)?.deletingLastPathComponent().path
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/document(for:)
    @MainActor open func document(for url: URL) -> NSDocument? {
        let path = url.standardizedFileURL.path
        return _documents.first { $0.fileURL?.standardizedFileURL.path == path }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/document(for:)
    @MainActor open func document(for window: NSWindow) -> NSDocument? {
        if let d = window.windowController?.document as? NSDocument { return d }
        return _documents.first { $0.windowControllers.contains { $0.isWindowLoaded && $0.window === window } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/hasediteddocuments
    @MainActor open var hasEditedDocuments: Bool { _documents.contains { $0.isDocumentEdited } }

    // MARK: Making documents

    private func _instantiate(_ typeName: String) throws -> NSDocument.Type {
        guard let cls = documentClass(forType: typeName) as? NSDocument.Type else {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileReadUnknown.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "No document class is declared for the type \u{201c}\(typeName)\u{201d}.",
                                     NSLocalizedFailureReasonErrorKey: "Add an NSDocumentClass to the type's CFBundleDocumentTypes entry in Info.plist."])
        }
        return cls
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/makeuntitleddocument(oftype:)
    @MainActor open func makeUntitledDocument(ofType typeName: String) throws -> NSDocument {
        let doc = try _instantiate(typeName).init(type: typeName)
        _untitledCounter += 1
        doc._untitledName = _untitledCounter == 1 ? "Untitled" : "Untitled \(_untitledCounter)"
        return doc
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/makedocument(withcontentsof:oftype:)
    @MainActor open func makeDocument(withContentsOf url: URL, ofType typeName: String) throws -> NSDocument {
        try _instantiate(typeName).init(contentsOf: url, ofType: typeName)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/makedocument(for:withcontentsof:oftype:)
    @MainActor open func makeDocument(for urlOrNil: URL?, withContentsOf contentsURL: URL, ofType typeName: String) throws -> NSDocument {
        try _instantiate(typeName).init(for: urlOrNil, withContentsOf: contentsURL, ofType: typeName)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/openuntitleddocumentanddisplay(_:)
    @MainActor open func openUntitledDocumentAndDisplay(_ displayDocument: Bool) throws -> NSDocument {
        guard let type = defaultType else {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileReadUnknown.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "The application declares no document types.",
                                     NSLocalizedFailureReasonErrorKey: "Add CFBundleDocumentTypes to Info.plist (next to the executable, or named by APPKITWIN_INFO_PLIST)."])
        }
        let doc = try makeUntitledDocument(ofType: type)
        addDocument(doc)
        doc.makeWindowControllers()
        if displayDocument { doc.showWindows() }
        return doc
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/newdocument(_:)
    @MainActor open func newDocument(_ sender: Any?) {
        do { _ = try openUntitledDocumentAndDisplay(true) } catch { _ = presentError(error) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/duplicatedocument(withcontentsof:copying:displayname:)
    @MainActor open func duplicateDocument(withContentsOf url: URL, copying duplicateByCopying: Bool, displayName displayNameOrNil: String?) throws -> NSDocument {
        let type = try typeForContents(of: url)
        let doc = try makeDocument(for: nil, withContentsOf: url, ofType: type)
        _untitledCounter += 1
        doc._untitledName = displayNameOrNil.map { "\($0) copy" } ?? (_untitledCounter == 1 ? "Untitled" : "Untitled \(_untitledCounter)")
        doc.updateChangeCount(.changeDone)
        addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
        return doc
    }

    // MARK: Opening

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/opendocument(withcontentsof:display:completionhandler:)
    /// An already open document is shown again (`documentWasAlreadyOpen` true); otherwise
    /// the type is determined, the document made, added, given windows and noted as recent.
    @MainActor open func openDocument(withContentsOf url: URL, display displayDocument: Bool, completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void) {
        if let existing = document(for: url) {
            if displayDocument { existing.showWindows() }
            completionHandler(existing, true, nil)
            return
        }
        do {
            let type = try typeForContents(of: url)
            let doc = try makeDocument(withContentsOf: url, ofType: type)
            addDocument(doc)
            doc.makeWindowControllers()
            if displayDocument { doc.showWindows() }
            noteNewRecentDocumentURL(url)
            completionHandler(doc, false, nil)
        } catch {
            completionHandler(nil, false, error)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/opendocument(withcontentsof:display:)
    @MainActor open func openDocument(withContentsOf url: URL, display displayDocument: Bool) async throws -> (NSDocument, Bool) {
        try await withCheckedThrowingContinuation { c in
            openDocument(withContentsOf: url, display: displayDocument) { doc, wasOpen, error in
                if let doc { c.resume(returning: (doc, wasOpen)) } else { c.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
            }
        }
    }
    // DUPLICATE: @MainActor open func openDocument(withContentsOf url: URL, display displayDocument: Bool) async throws -> (NSDocument, Bool)
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/reopendocument(for:withcontentsof:display:completionhandler:)
    @MainActor open func reopenDocument(for urlOrNil: URL?, withContentsOf contentsURL: URL, display displayDocument: Bool, completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void) {
        if let url = urlOrNil, let existing = document(for: url) {
            if displayDocument { existing.showWindows() }
            completionHandler(existing, true, nil)
            return
        }
        do {
            let type = try typeForContents(of: urlOrNil ?? contentsURL)
            let doc = try makeDocument(for: urlOrNil, withContentsOf: contentsURL, ofType: type)
            addDocument(doc)
            doc.makeWindowControllers()
            if displayDocument { doc.showWindows() }
            completionHandler(doc, false, nil)
        } catch {
            completionHandler(nil, false, error)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/reopendocument(for:withcontentsof:display:)
    @MainActor open func reopenDocument(for urlOrNil: URL?, withContentsOf contentsURL: URL, display displayDocument: Bool) async throws -> (NSDocument, Bool) {
        try await withCheckedThrowingContinuation { c in
            reopenDocument(for: urlOrNil, withContentsOf: contentsURL, display: displayDocument) { doc, wasOpen, error in
                if let doc { c.resume(returning: (doc, wasOpen)) } else { c.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
            }
        }
    }
    // DUPLICATE: @MainActor open func reopenDocument(for urlOrNil: URL?, withContentsOf contentsURL: URL, display displayDocument: Bool) async throws -> (NSDocument, Bool)

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/opendocument(_:)
    @MainActor open func openDocument(_ sender: Any?) {
        beginOpenPanel { [weak self] urls in
            guard let self, let urls else { return }
            for url in urls {
                self.openDocument(withContentsOf: url, display: true) { _, _, error in
                    if let error { _ = self.presentError(error) }
                }
            }
        }
    }

    /// Opens the files named on the command line (`application(_:openFile:)` first, as
    /// the Finder would) and returns whether any were opened.
    @MainActor internal func _openCommandLineFiles() -> Bool {
        let app = NSApplication.shared
        let paths = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return false }
        var opened = false
        if let d = app.delegate, paths.count > 1 {
            d.application(app, openFiles: paths.map { $0 })
            return true
        }
        for path in paths {
            let url = URL(fileURLWithPath: path)
            if app.delegate?.application(app, openFile: path) == true { opened = true; continue }
            openDocument(withContentsOf: url, display: true) { doc, _, error in
                if doc != nil { opened = true }
                if let error { _ = self.presentError(error) }
            }
        }
        return opened
    }

    /// The readable types' extensions (every class's) for an open panel.
    private var _readableContentTypes: [UTType] {
        var out: [UTType] = []
        for t in _types where t.isViewerOrEditor {
            for c in t.contentTypes { if let u = UTType(c), !out.contains(u) { out.append(u) } }
        }
        return out
    }
    private var _readableExtensions: [String] {
        var out: [String] = []
        for t in _types where t.isViewerOrEditor { for e in t.extensions where !out.contains(e) { out.append(e) } }
        return out
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/beginopenpanel(completionhandler:)
    @MainActor open func beginOpenPanel(completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = _types.contains { $0.isPackage || $0.contentTypes.contains("public.folder") }
        beginOpenPanel(panel, forTypes: _readableExtensions.isEmpty ? nil : _readableExtensions) { result in
            completionHandler(result == NSApplication.ModalResponse.OK.rawValue ? panel.urls : nil)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/beginopenpanel()
    @MainActor open func beginOpenPanel() async -> [URL]? {
        await withCheckedContinuation { c in beginOpenPanel { c.resume(returning: $0) } }
    }
    // DUPLICATE: @MainActor open func beginOpenPanel() async -> [URL]?
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/beginopenpanel(_:fortypes:completionhandler:)
    @MainActor open func beginOpenPanel(_ openPanel: NSOpenPanel, forTypes inTypes: [String]?, completionHandler: @escaping (Int) -> Void) {
        _configureOpenPanel(openPanel, forTypes: inTypes)
        openPanel.begin { completionHandler($0.rawValue) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/beginopenpanel(_:fortypes:)
    @MainActor open func beginOpenPanel(_ openPanel: NSOpenPanel, forTypes inTypes: [String]?) async -> Int {
        await withCheckedContinuation { c in beginOpenPanel(openPanel, forTypes: inTypes) { c.resume(returning: $0) } }
    }
    // DUPLICATE: @MainActor open func beginOpenPanel(_ openPanel: NSOpenPanel, forTypes inTypes: [String]?) async -> Int
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/runmodalopenpanel(_:fortypes:)
    @MainActor open func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
        _configureOpenPanel(openPanel, forTypes: types)
        return openPanel.runModal().rawValue
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/urlsfromrunningopenpanel()
    @MainActor open func urlsFromRunningOpenPanel() -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        return runModalOpenPanel(panel, forTypes: _readableExtensions.isEmpty ? nil : _readableExtensions) == NSApplication.ModalResponse.OK.rawValue ? panel.urls : nil
    }

    /// `types` are extensions (the legacy form) or UTIs; the readable content types are
    /// used when nil.
    private func _configureOpenPanel(_ panel: NSOpenPanel, forTypes types: [String]?) {
        panel.canChooseFiles = true
        if let types, !types.isEmpty {
            let contentTypes = types.compactMap { $0.contains(".") ? UTType($0) : nil }
            if contentTypes.count == types.count { panel.allowedContentTypes = contentTypes } else { panel.allowedFileTypes = types }
        } else {
            let content = _readableContentTypes
            if !content.isEmpty { panel.allowedContentTypes = content } else if !_readableExtensions.isEmpty { panel.allowedFileTypes = _readableExtensions }
        }
        if panel.directoryURL == nil, let dir = currentDirectory { panel.directoryURL = URL(fileURLWithPath: dir) }
    }

    // MARK: Recent documents

    private func _loadRecents() {
        let defaults = UserDefaults.standard
        if let limit = defaults.object(forKey: NSDocumentController._recentLimitDefaultsKey) as? Int, limit >= 0 { _maximumRecentDocumentCount = limit }
        _recentURLs = ((defaults.array(forKey: NSDocumentController._recentDefaultsKey) as? [String]) ?? []).map { URL(fileURLWithPath: $0) }
        if _recentURLs.count > _maximumRecentDocumentCount { _recentURLs = Array(_recentURLs.prefix(_maximumRecentDocumentCount)) }
    }
    private func _saveRecents() {
        UserDefaults.standard.set(_recentURLs.map { $0.path }, forKey: NSDocumentController._recentDefaultsKey)
        _updateRecentMenu()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/recentdocumenturls
    @MainActor open var recentDocumentURLs: [URL] { _recentURLs }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/maximumrecentdocumentcount
    @MainActor open var maximumRecentDocumentCount: Int { _maximumRecentDocumentCount }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/notenewrecentdocument(_:)
    @MainActor open func noteNewRecentDocument(_ document: NSDocument) {
        if let url = document.fileURL { noteNewRecentDocumentURL(url) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/notenewrecentdocumenturl(_:)
    @MainActor open func noteNewRecentDocumentURL(_ url: URL) {
        let path = url.standardizedFileURL.path
        _recentURLs.removeAll { $0.standardizedFileURL.path == path }
        _recentURLs.insert(URL(fileURLWithPath: path), at: 0)
        if _recentURLs.count > _maximumRecentDocumentCount { _recentURLs = Array(_recentURLs.prefix(_maximumRecentDocumentCount)) }
        _saveRecents()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/clearrecentdocuments(_:)
    @MainActor open func clearRecentDocuments(_ sender: Any?) {
        _recentURLs.removeAll()
        _saveRecents()
    }

    /// The Open Recent submenu: the main menu's submenu titled "Open Recent" (found when
    /// the main menu is installed); filled with the recent files and a Clear Menu item.
    @MainActor internal func _mainMenuDidChange() {
        _recentMenu = NSDocumentController._findRecentMenu(in: NSApplication.shared.mainMenu)
        _updateRecentMenu()
    }
    private static func _findRecentMenu(in menu: NSMenu?) -> NSMenu? {
        guard let menu else { return nil }
        for item in menu.items {
            guard let sub = item.submenu else { continue }
            if sub.title == "Open Recent" || item.title == "Open Recent" { return sub }
            if let found = _findRecentMenu(in: sub) { return found }
        }
        return nil
    }
    private var _updatingRecentMenu = false
    private func _updateRecentMenu() {
        guard let menu = _recentMenu, !_updatingRecentMenu else { return }
        // Rebuilding the items notifies the application of a menu change, which asks the
        // controller again: ignore that, and leave a menu that already matches alone.
        let current = menu.items.compactMap { $0.representedObject as? URL }
        if current.map({ $0.path }) == _recentURLs.map({ $0.path }), menu.items.last?.title == "Clear Menu" { return }
        _updatingRecentMenu = true
        defer { _updatingRecentMenu = false }
        menu.removeAllItems()
        for url in _recentURLs {
            let item = NSMenuItem(title: url.lastPathComponent, action: Selector(("_openRecentDocument:")), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.toolTip = url.path
            menu.addItem(item)
        }
        if !_recentURLs.isEmpty { menu.addItem(NSMenuItem.separator()) }
        let clear = NSMenuItem(title: "Clear Menu", action: Selector(("clearRecentDocuments:")), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }

    // MARK: Saving and closing all

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/savealldocuments(_:)
    @MainActor open func saveAllDocuments(_ sender: Any?) {
        for doc in _documents where doc.isDocumentEdited { doc.save(sender) }
    }

    @MainActor private func _deliver(_ selector: Selector?, to delegate: Any?, _ flag: Bool) {
        guard let selector, let delegate else { return }
        _ = ActionRegistry.perform(selector, on: delegate as AnyObject, with: NSNumber(value: flag))
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/closealldocuments(withdelegate:didcloseallselector:contextinfo:)
    @MainActor open func closeAllDocuments(withDelegate delegate: Any?, didCloseAllSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        _closeAllDocuments { [weak self] ok in self?._deliver(didCloseAllSelector, to: delegate, ok) }
    }

    /// Asks each document in turn whether it can close (its unsaved-changes alert) and
    /// closes it; stops at the first Cancel. `completion` gets whether all closed.
    @MainActor internal func _closeAllDocuments(_ completion: @escaping (Bool) -> Void) {
        var remaining = _documents
        func next() {
            guard let doc = remaining.first else { completion(true); return }
            remaining.removeFirst()
            doc._canClose { ok in
                guard ok else { completion(false); return }
                doc.close()
                next()
            }
        }
        next()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/reviewunsaveddocuments(withalerttitle:cancellable:delegate:didreviewallselector:contextinfo:)
    @MainActor open func reviewUnsavedDocuments(withAlertTitle title: String?, cancellable: Bool, delegate: Any?, didReviewAllSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        _reviewUnsavedDocuments(title: title, cancellable: cancellable) { [weak self] ok in self?._deliver(didReviewAllSelector, to: delegate, ok) }
    }

    /// With one edited document its own alert runs; with several, "You have N documents
    /// with unsaved changes" offers Review Changes…, Cancel and Discard Changes.
    /// `completion` gets whether every document was dealt with (saved or discarded).
    @MainActor internal func _reviewUnsavedDocuments(title: String?, cancellable: Bool, completion: @escaping (Bool) -> Void) {
        let edited = _documents.filter { $0.isDocumentEdited }
        guard !edited.isEmpty else { completion(true); return }
        if edited.count == 1 {
            edited[0]._canClose { ok in completion(ok) }
            return
        }
        let alert = NSAlert()
        alert.messageText = "You have \(edited.count) documents with unsaved changes. Do you want to review these changes before \(title?.lowercased() == "quit" ? "quitting" : "closing")?"
        alert.informativeText = "If you don\u{2019}t review your documents, all your changes will be lost."
        alert.addButton(withTitle: "Review Changes\u{2026}")
        if cancellable { alert.addButton(withTitle: "Cancel") }
        let discard = alert.addButton(withTitle: "Discard Changes")
        _ = discard
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            var remaining = edited
            func next() {
                guard let doc = remaining.first else { completion(true); return }
                remaining.removeFirst()
                doc._canClose { ok in
                    guard ok else { completion(false); return }
                    next()
                }
            }
            next()
        case .alertSecondButtonReturn where cancellable:
            completion(false)
        default:
            completion(true)
        }
    }

    // MARK: Errors

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/presenterror(_:)
    @MainActor open func presentError(_ error: any Error) -> Bool {
        _ = NSAlert(error: willPresentError(error)).runModal()
        return false
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/presenterror(_:modalfor:delegate:didpresent:contextinfo:)
    @MainActor open func presentError(_ error: any Error, modalFor window: NSWindow, delegate: Any?, didPresent didPresentSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        NSAlert(error: willPresentError(error)).beginSheetModal(for: window) { [weak self] _ in self?._deliver(didPresentSelector, to: delegate, false) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/willpresenterror(_:)
    @MainActor open func willPresentError(_ error: any Error) -> any Error { error }

    // MARK: Autosaving and sharing

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/autosavingdelay
    /// 0 (the default) means documents are not autosaved on a timer.
    @MainActor open var autosavingDelay: TimeInterval {
        get { _autosavingDelay }
        set { _autosavingDelay = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/allowsautomaticsharemenu
    @available(macOS 10.13, *)
    @MainActor open var allowsAutomaticShareMenu: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/standardsharemenuitem()
    @available(macOS 10.13, *)
    @MainActor open func standardShareMenuItem() -> NSMenuItem { unimplemented() }

    // MARK: Menu actions and validation

    private static let _actions: Set<String> = ["newDocument:", "openDocument:", "clearRecentDocuments:", "saveAllDocuments:", "_openRecentDocument:"]

    open func respondsToSelectorAction(_ action: Selector) -> Bool { NSDocumentController._actions.contains(NSStringFromSelector(action)) }

    open func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch NSStringFromSelector(action) {
        case "newDocument:": newDocument(sender)
        case "openDocument:": openDocument(sender)
        case "clearRecentDocuments:": clearRecentDocuments(sender)
        case "saveAllDocuments:": saveAllDocuments(sender)
        case "_openRecentDocument:":
            guard let url = (sender as? NSMenuItem)?.representedObject as? URL else { return false }
            openDocument(withContentsOf: url, display: true) { [weak self] _, _, error in
                if let error, let self {
                    _ = self.presentError(error)
                    if (error as NSError).code == CocoaError.Code.fileNoSuchFile.rawValue || !FileManager.default.fileExists(atPath: url.path) {
                        self._recentURLs.removeAll { $0.path == url.path }
                        self._saveRecents()
                    }
                }
            }
        default: return false
        }
        return true
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocumentcontroller/validateuserinterfaceitem(_:)
    @MainActor open func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        guard let action = item.action else { return true }
        switch NSStringFromSelector(action) {
        case "newDocument:": return defaultType != nil
        case "clearRecentDocuments:": return !_recentURLs.isEmpty
        case "saveAllDocuments:": return hasEditedDocuments
        default: return true
        }
    }
    // Requirement of NSMenuItemValidation
    @MainActor open func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { validateUserInterfaceItem(menuItem) }

    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { }
    // Requirement of NSWindowRestoration
    @MainActor public static func restoreWindow(withIdentifier identifier: NSUserInterfaceItemIdentifier, state: NSCoder) async throws -> NSWindow { unimplemented() }
}
