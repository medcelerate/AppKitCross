// Document-based apps: FileDocument, ReferenceFileDocument, their configurations and
// DocumentGroup, over AppKit's NSDocument architecture (ADR-0017), as SwiftUI does on macOS.
//
// A DocumentGroup registers its document type with a document controller SwiftUI installs
// (`_SwiftUIDocumentController`, the shared NSDocumentController): every document is a
// `_HostingDocument`, an NSDocument whose content is the app's FileDocument value (or
// ReferenceFileDocument object) and whose window hosts the group's view. Everything else is
// NSDocument's: New, Open (the platform's open panel), Open Recent, Save and Save As (the
// save panel with the writable types), Revert, the edited mark in the title bar, the
// unsaved-changes alert on close and on quit, opening files named on the command line, an
// untitled document at launch.
//
// Types: a document's types are its `readableContentTypes` / `writableContentTypes`. The
// Info.plist's `CFBundleDocumentTypes` and UTI declarations are honoured when there is one
// (`APPKITWIN_INFO_PLIST` names it for a bare executable), and they are what gives an
// app-declared type such as `net.daringfireball.markdown` its filename extensions off macOS;
// a DocumentGroup needs no `NSDocumentClass` there.
//
// Change tracking: a write through the configuration's `document` binding marks the
// document edited at the end of the event unless an undo step already did (a text view
// that registers its own undo with the window's undo manager, the document's, counts its
// changes through it, so Undo can take the document back to clean). SwiftUI on macOS also
// makes FileDocument value changes undoable; here they are not (no value undo is
// registered: it would double the text view's own steps). A ReferenceFileDocument is
// edited through the undo manager only, as on macOS. Documents do not autosave in place
// (`autosavesInPlace` is false): saving is explicit and closing an edited document asks.

import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if canImport(Combine)
import Combine
#endif

// MARK: FileDocument

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/filedocument
public protocol FileDocument {
    static var readableContentTypes: [UTType] { get }
    static var writableContentTypes: [UTType] { get }
    typealias ReadConfiguration = FileDocumentReadConfiguration
    typealias WriteConfiguration = FileDocumentWriteConfiguration
    init(configuration: Self.ReadConfiguration) throws
    func fileWrapper(configuration: Self.WriteConfiguration) throws -> FileWrapper
}

extension FileDocument {
    public static var writableContentTypes: [UTType] { readableContentTypes }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/filedocumentreadconfiguration
public struct FileDocumentReadConfiguration {
    /// The type of the file being read.
    public let contentType: UTType
    /// The file's contents.
    public let file: FileWrapper
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/filedocumentwriteconfiguration
public struct FileDocumentWriteConfiguration {
    /// The type to write.
    public let contentType: UTType
    /// The file as it is on disk, when there is one (nil for a new file).
    public let existingFile: FileWrapper?
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/filedocumentconfiguration
public struct FileDocumentConfiguration<Document: FileDocument> {
    @Binding public var document: Document
    public var fileURL: URL?
    public var isEditable: Bool
    init(document: Binding<Document>, fileURL: URL?, isEditable: Bool) {
        _document = document
        self.fileURL = fileURL
        self.isEditable = isEditable
    }
}

// MARK: ReferenceFileDocument

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/referencefiledocument
public protocol ReferenceFileDocument: ObservableObject {
    associatedtype Snapshot
    static var readableContentTypes: [UTType] { get }
    static var writableContentTypes: [UTType] { get }
    typealias ReadConfiguration = FileDocumentReadConfiguration
    typealias WriteConfiguration = FileDocumentWriteConfiguration
    init(configuration: Self.ReadConfiguration) throws
    func snapshot(contentType: UTType) throws -> Self.Snapshot
    func fileWrapper(snapshot: Self.Snapshot, configuration: Self.WriteConfiguration) throws -> FileWrapper
}

extension ReferenceFileDocument {
    public static var writableContentTypes: [UTType] { readableContentTypes }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/referencefiledocumentconfiguration
public struct ReferenceFileDocumentConfiguration<Document: ReferenceFileDocument> {
    @ObservedObject public var document: Document
    public var fileURL: URL?
    public var isEditable: Bool
    init(document: Document, fileURL: URL?, isEditable: Bool) {
        _document = ObservedObject(wrappedValue: document)
        self.fileURL = fileURL
        self.isEditable = isEditable
    }
}

// MARK: DocumentGroup

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/documentgroup
public struct DocumentGroup<Document, Content: View>: Scene, _PrimitiveScene {
    public typealias Body = Never
    let makeEntry: @MainActor () -> _DocumentGroupEntry
    public var body: Never { fatalError() }

    @MainActor public func _makeWindows(app: _AppRunner) {
        let entry = makeEntry()
        entry.defaultSize = app.pendingDefaultSize
        entry.resizability = app.pendingResizability
        entry.hidesTitleBar = app.pendingHidesTitleBar
        entry.toolbarStyle = app.pendingToolbarStyle
        entry.runner = app
        _DocumentGroupEntry.register(entry)
        app._hasDocumentGroups = true
        _SwiftUIDocumentController.install()
    }
}

extension DocumentGroup where Document: FileDocument {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/documentgroup/init(newdocument:editor:)-9j9hd
    public init(newDocument: @autoclosure @escaping () -> Document, @ViewBuilder editor: @escaping (FileDocumentConfiguration<Document>) -> Content) {
        makeEntry = { _DocumentGroupEntry.value(Document.self, isViewer: false, makeNew: newDocument, view: editor) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/documentgroup/init(viewing:viewer:)-63kxb
    public init(viewing documentType: Document.Type, @ViewBuilder viewer: @escaping (FileDocumentConfiguration<Document>) -> Content) {
        makeEntry = { _DocumentGroupEntry.value(Document.self, isViewer: true, makeNew: nil, view: viewer) }
    }
}

extension DocumentGroup where Document: ReferenceFileDocument {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/documentgroup/init(newdocument:editor:)-4toxv
    public init(newDocument: @escaping () -> Document, @ViewBuilder editor: @escaping (ReferenceFileDocumentConfiguration<Document>) -> Content) {
        makeEntry = { _DocumentGroupEntry.reference(Document.self, isViewer: false, makeNew: newDocument, view: editor) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/documentgroup/init(viewing:viewer:)-55lqb
    public init(viewing documentType: Document.Type, @ViewBuilder viewer: @escaping (ReferenceFileDocumentConfiguration<Document>) -> Content) {
        makeEntry = { _DocumentGroupEntry.reference(Document.self, isViewer: true, makeNew: nil, view: viewer) }
    }
}

extension EnvironmentValues {
    private struct UndoManagerKey: EnvironmentKey { static let defaultValue: UndoManager? = nil }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/environmentvalues/undomanager
    /// A document window's undo manager (the document's); nil elsewhere.
    public var undoManager: UndoManager? { self[UndoManagerKey.self] }
    var _undoManager: UndoManager? { get { self[UndoManagerKey.self] } set { self[UndoManagerKey.self] = newValue } }
}

// MARK: Type-erased group

/// One DocumentGroup: its types and how to make, read, write and show its documents.
@MainActor
public final class _DocumentGroupEntry {
    let readable: [UTType]
    let writable: [UTType]
    let isViewer: Bool
    let isReference: Bool
    let makeNew: (() -> Any)?
    let read: (FileDocumentReadConfiguration) throws -> Any
    let write: (Any, FileDocumentWriteConfiguration) throws -> FileWrapper
    let view: (_DocumentModel) -> AnyView
    var defaultSize: CGSize? = nil
    var resizability: WindowResizability = .automatic
    var hidesTitleBar = false
    var toolbarStyle: NSWindow.ToolbarStyle = .automatic
    /// The runner whose scenes declared the group (it makes the document windows).
    var runner: _AppRunner?

    init(readable: [UTType], writable: [UTType], isViewer: Bool, isReference: Bool, makeNew: (() -> Any)?,
         read: @escaping (FileDocumentReadConfiguration) throws -> Any,
         write: @escaping (Any, FileDocumentWriteConfiguration) throws -> FileWrapper,
         view: @escaping (_DocumentModel) -> AnyView) {
        self.readable = readable; self.writable = writable; self.isViewer = isViewer; self.isReference = isReference
        self.makeNew = makeNew; self.read = read; self.write = write; self.view = view
    }

    static func value<D: FileDocument, C: View>(_ type: D.Type, isViewer: Bool, makeNew: (() -> D)?, view: @escaping (FileDocumentConfiguration<D>) -> C) -> _DocumentGroupEntry {
        _DocumentGroupEntry(
            readable: D.readableContentTypes, writable: isViewer ? [] : D.writableContentTypes, isViewer: isViewer, isReference: false,
            makeNew: makeNew.map { make in { make() } },
            read: { try D(configuration: $0) },
            write: { value, configuration in
                guard let d = value as? D else { throw CocoaError(.fileWriteUnknown) }
                return try d.fileWrapper(configuration: configuration)
            },
            view: { model in
                let binding = Binding<D>(get: { (model.value as? D) ?? (model.lastGood as! D) }, set: { model.userDidSet($0) })
                return AnyView(view(FileDocumentConfiguration(document: binding, fileURL: model.document?.fileURL, isEditable: !isViewer)))
            })
    }

    static func reference<D: ReferenceFileDocument, C: View>(_ type: D.Type, isViewer: Bool, makeNew: (() -> D)?, view: @escaping (ReferenceFileDocumentConfiguration<D>) -> C) -> _DocumentGroupEntry {
        _DocumentGroupEntry(
            readable: D.readableContentTypes, writable: isViewer ? [] : D.writableContentTypes, isViewer: isViewer, isReference: true,
            makeNew: makeNew.map { make in { make() } },
            read: { try D(configuration: $0) },
            write: { value, configuration in
                guard let d = value as? D else { throw CocoaError(.fileWriteUnknown) }
                let snapshot = try d.snapshot(contentType: configuration.contentType)
                return try d.fileWrapper(snapshot: snapshot, configuration: configuration)
            },
            view: { model in
                guard let object = model.value as? D else { return AnyView(EmptyView()) }
                return AnyView(view(ReferenceFileDocumentConfiguration(document: object, fileURL: model.document?.fileURL, isEditable: !isViewer)))
            })
    }

    // MARK: Registry

    static private(set) var all: [_DocumentGroupEntry] = []
    static func register(_ entry: _DocumentGroupEntry) { all.append(entry) }
    /// Test hook: forgets the registered groups.
    static func _reset() { all = [] }

    /// Whether the group reads (or, `writing`, writes) the type named `typeName`: the type
    /// itself or one it conforms to.
    func handles(_ typeName: String, writing: Bool = false) -> Bool {
        guard let t = UTType(typeName) else { return false }
        return (writing ? writable : readable).contains { t == $0 || t.conforms(to: $0) }
    }

    /// The group whose documents a type belongs to: the first that reads it.
    static func entry(forType typeName: String) -> _DocumentGroupEntry? {
        all.first { $0.handles(typeName) } ?? all.first { $0.handles(typeName, writing: true) }
    }
}

/// A document's content as the hosted view sees it, and the publisher that redraws it.
@MainActor
public final class _DocumentModel: ObservableObject {
    public let objectWillChange = ObservableObjectPublisher()
    weak var document: _HostingDocument?
    /// The FileDocument value or the ReferenceFileDocument object.
    var value: Any? { didSet { if value != nil { lastGood = value } } }
    var lastGood: Any?
    private var subscription: AnyCancellable?
    init(document: _HostingDocument) { self.document = document }

    /// Replaces the content (read, revert): views redraw; a reference document's own
    /// changes redraw them too.
    func replace(with newValue: Any) {
        objectWillChange.send()
        value = newValue
        if let object = newValue as? any ObservableObject {
            subscription = _observe(object)
        }
    }
    private func _observe<O: ObservableObject>(_ object: O) -> AnyCancellable {
        object.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// A write through the configuration's binding.
    func userDidSet(_ newValue: Any) {
        objectWillChange.send()
        value = newValue
        document?._contentDidChange()
    }
}

struct _DocumentRootView: View {
    @ObservedObject var model: _DocumentModel
    let entry: _DocumentGroupEntry
    var body: some View {
        entry.view(model).environment(\._undoManager, model.document?.undoManager)
    }
}

// MARK: The document

/// Every DocumentGroup document: an NSDocument holding the app's value.
@MainActor
public final class _HostingDocument: NSDocument {
    lazy var model = _DocumentModel(document: self)
    private var entry: _DocumentGroupEntry? { fileType.flatMap { _DocumentGroupEntry.entry(forType: $0) } ?? _DocumentGroupEntry.all.first }
    private var markScheduled = false

    /// Test hook: the content (the FileDocument value or the ReferenceFileDocument object).
    public var _content: Any? { model.value }

    private func ensureContent() {
        guard model.value == nil, let entry, let make = entry.makeNew else { return }
        model.replace(with: make())
    }

    // MARK: Types

    public override class var readableTypes: [String] {
        var out: [String] = []
        for e in _DocumentGroupEntry.all { for t in e.readable where !out.contains(t.identifier) { out.append(t.identifier) } }
        return out
    }
    public override class var writableTypes: [String] {
        var out: [String] = []
        for e in _DocumentGroupEntry.all { for t in e.writable where !out.contains(t.identifier) { out.append(t.identifier) } }
        return out
    }

    // MARK: Reading and writing

    public override nonisolated func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
        try MainActor.assumeIsolated {
            guard let entry = _DocumentGroupEntry.entry(forType: typeName) ?? _DocumentGroupEntry.all.first else { throw CocoaError(.fileReadUnknown) }
            let type = UTType(typeName) ?? entry.readable.first ?? .data
            let value = try entry.read(FileDocumentReadConfiguration(contentType: type, file: fileWrapper))
            model.replace(with: value)
        }
    }

    public override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        ensureContent()
        guard let entry, let value = model.value else { throw CocoaError(.fileWriteUnknown) }
        let type = UTType(typeName) ?? entry.writable.first ?? .data
        let existing = fileURL.flatMap { try? FileWrapper(url: $0, options: []) }
        return try entry.write(value, FileDocumentWriteConfiguration(contentType: type, existingFile: existing))
    }

    // MARK: Changes

    /// The binding wrote a new value. Undo and redo count themselves (the undo manager's
    /// notifications); otherwise the document is marked edited once the event is over,
    /// unless an undo step closed in it (which counted the change already).
    func _contentDidChange() {
        if let m = undoManager, m.isUndoing || m.isRedoing { return }
        guard !markScheduled else { return }
        markScheduled = true
        let check: @Sendable () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.markScheduled = false
                if !self.isDocumentEdited { self.updateChangeCount(.changeDone) }
            }
        }
        #if canImport(Darwin)
        // Foundation's undo manager closes the event's group from a run-loop observer,
        // after the main queue's blocks: the check waits one more pass.
        DispatchQueue.main.async { DispatchQueue.main.async(execute: check) }
        #else
        // The port's undo manager closes it from a main-queue block queued when the step
        // was registered, so a block queued now runs after it. One hop: the Win32 pump
        // drains the queue once per wake, and a second hop waited for the next input (the
        // File menu showed Save disabled right after typing).
        DispatchQueue.main.async(execute: check)
        #endif
    }

    // MARK: Windows

    public override func makeWindowControllers() {
        ensureContent()
        guard let entry, let runner = entry.runner ?? _AppRunner._current else { return }
        let window = runner._makeDocumentWindow(content: _DocumentRootView(model: model, entry: entry), entry: entry)
        let controller = NSWindowController(window: window)
        addWindowController(controller)
    }
}

// MARK: The document controller

/// The shared document controller of an app with DocumentGroups: it makes their documents
/// `_HostingDocument`s and knows their types without an Info.plist.
@MainActor
final class _SwiftUIDocumentController: NSDocumentController {
    static var installed: _SwiftUIDocumentController?

    /// Makes the controller (the first one made becomes `shared`, so this runs before
    /// anything asks for `NSDocumentController.shared`).
    static func install() {
        guard installed == nil else { return }
        let controller = _SwiftUIDocumentController()
        installed = controller
        if NSDocumentController.shared !== controller, NSView._traceInvalidation {
            NSView._trace("DocumentGroup: a document controller existed before the scenes ran; SwiftUI documents use it")
        }
    }

    override func documentClass(forType typeName: String) -> AnyClass? {
        if _DocumentGroupEntry.entry(forType: typeName) != nil { return _HostingDocument.self }
        return super.documentClass(forType: typeName)
    }

    /// The first editing group's first writable type (the Info.plist's when it declares
    /// one of the group's types first).
    override var defaultType: String? {
        if let declared = super.defaultType, _DocumentGroupEntry.entry(forType: declared).map({ !$0.isViewer }) == true { return declared }
        return _DocumentGroupEntry.all.first { !$0.isViewer && !$0.writable.isEmpty }?.writable.first?.identifier ?? super.defaultType
    }

    override var documentClassNames: [String] {
        var names = super.documentClassNames
        if !_DocumentGroupEntry.all.isEmpty { names.append(String(reflecting: _HostingDocument.self)) }
        return names
    }

    override func displayName(forType typeName: String) -> String? {
        super.displayName(forType: typeName) ?? UTType(typeName)?.localizedDescription
    }

    /// The Info.plist's type when it declares one, else the file's own type (from its
    /// extension) when a group reads it.
    override func typeForContents(of url: URL) throws -> String {
        let declared: String
        do { declared = try super.typeForContents(of: url) } catch {
            let ext = url.pathExtension
            if !ext.isEmpty, let t = UTType(filenameExtension: ext), _DocumentGroupEntry.entry(forType: t.identifier) != nil { return t.identifier }
            throw error
        }
        return declared
    }

    /// The open panel lists every group's readable types.
    override func beginOpenPanel(completionHandler: @escaping ([URL]?) -> Void) {
        var types: [String] = []
        for e in _DocumentGroupEntry.all { for t in e.readable where !types.contains(t.identifier) { types.append(t.identifier) } }
        guard !types.isEmpty else { super.beginOpenPanel(completionHandler: completionHandler); return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        beginOpenPanel(panel, forTypes: types) { result in
            completionHandler(result == NSApplication.ModalResponse.OK.rawValue ? panel.urls : nil)
        }
    }
}
