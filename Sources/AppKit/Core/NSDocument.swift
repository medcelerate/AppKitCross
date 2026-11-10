// NSDocument (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
//
// The document architecture (ADR-0017): a document owns its file URL and type, a change
// count (kept in step with its undo manager), its window controllers, and the save,
// save-as, revert, autosave and close flows with their panels and alerts. Reading and
// writing have the same override points as on macOS: `read(from:ofType:)` for a URL
// calls the file-wrapper variant, which calls `read(from:ofType:)` for data; writing goes
// `write(to:ofType:for:originalContentsURL:)` → `write(to:ofType:)` → `fileWrapper(ofType:)`
// → `data(ofType:)`. A subclass overrides one level of each chain; the lowest level
// throws when nothing was overridden.
//
// Selector-based completion callbacks (`canClose(withDelegate:shouldClose:contextInfo:)`,
// `save(withDelegate:didSave:contextInfo:)`, ...) cannot be performed without the
// Objective-C runtime; the port delivers them through the target/action registry: the
// delegate receives the selector through `NSSelectorHandling` or `setActionHandler(for:)`
// with the Bool result as the sender argument. The async and closure variants work as
// on macOS.
//
// Without the Objective-C runtime initializers are not inherited as required, so on
// Windows and Linux `init()` is declared `required`: a subclass that overrides it writes
// `required init()` (which macOS accepts as well).

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument
@MainActor open class NSDocument: NSObject, NSEditorRegistration, NSMenuItemValidation, NSUserInterfaceValidations, NSUserActivityRestoring, NSSelectorHandling {
    // MARK: Storage
    private var _fileURL: URL? = nil
    private var _fileType: String? = nil
    private var _fileModificationDate: Date? = nil
    private var _windowControllers: [NSWindowController] = []
    private var _changeCount = 0
    private var _autosavedChangeCount = 0
    private var _changeIsDiscardable = false
    private var _hasUndoManager = true
    private var _undoManager: UndoManager? = nil
    private var _undoObservers: [NSObjectProtocol] = []
    private var _autosavedContentsFileURL: URL? = nil
    private var _autosaveTimer: Timer? = nil
    private var _isClosing = false
    private var _isDraft = false
    private var _fileTypeFromLastRunSavePanel: String? = nil
    private var _fileNameExtensionWasHiddenInLastRunSavePanel = false
    private var _isInViewingMode = false
    private var _isLocked = false
    private var _lastComponentOfFileName = ""
    /// "Untitled", "Untitled 2", ...: given by the document controller on creation.
    internal var _untitledName: String? = nil

    // MARK: Creation

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/init()
    #if canImport(ObjectiveC)
    @MainActor public override init() {
        super.init()
    }
    #else
    @MainActor public required override init() {
        super.init()
    }
    #endif
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/init(contentsof:oftype:)
    @MainActor public required convenience init(contentsOf url: URL, ofType typeName: String) throws {
        self.init()
        _fileType = typeName
        try read(from: url, ofType: typeName)
        _fileURL = url
        _fileModificationDate = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/init(for:withcontentsof:oftype:)
    @MainActor public required convenience init(for urlOrNil: URL?, withContentsOf contentsURL: URL, ofType typeName: String) throws {
        self.init()
        _fileType = typeName
        try read(from: contentsURL, ofType: typeName)
        _fileURL = urlOrNil
        if urlOrNil != nil {
            // Contents came from somewhere else (an autosaved file): they are unsaved changes.
            _autosavedContentsFileURL = contentsURL
            updateChangeCount(.changeDone)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/init(type:)
    @MainActor public required convenience init(type typeName: String) throws {
        self.init()
        _fileType = typeName
    }

    deinit {
        for o in _undoObservers { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: Errors

    /// The error for a reading or writing override point the subclass did not provide.
    nonisolated internal static func _overrideError(_ what: String, reading: Bool) -> NSError {
        NSError(domain: NSCocoaErrorDomain, code: reading ? CocoaError.Code.fileReadUnknown.rawValue : CocoaError.Code.fileWriteUnknown.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "The document could not be \(reading ? "read" : "written").",
                           NSLocalizedFailureReasonErrorKey: "NSDocument subclasses must override \(what)."])
    }

    // MARK: File presenter (the port has no NSFileCoordinator; these are inert)

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/accommodatepresenteditemdeletion()
    open nonisolated func accommodatePresentedItemDeletion() async throws { }
    // DUPLICATE: open nonisolated func accommodatePresentedItemDeletion() async throws
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/presenteditemdidchange()
    open nonisolated func presentedItemDidChange() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/presenteditemdidchangeubiquityattributes(_:)
    open nonisolated func presentedItemDidChangeUbiquityAttributes(_ attributes: Set<URLResourceKey>) { }
    // SKIPPED (Foundation.NSFileVersion not in corelibs): nonisolated func presentedItemDidGain(_ version: NSFileVersion)
    // SKIPPED (Foundation.NSFileVersion not in corelibs): nonisolated func presentedItemDidLose(_ version: NSFileVersion)
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/presenteditemdidmove(to:)
    open nonisolated func presentedItemDidMove(to newURL: URL) { MainActor.assumeIsolated { _fileURL = newURL; _syncWindowTitles() } }
    // SKIPPED (Foundation.NSFileVersion not in corelibs): nonisolated func presentedItemDidResolveConflict(_ version: NSFileVersion)
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/presenteditemurl
    open var presentedItemURL: URL? { _fileURL }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/relinquishpresenteditem(toreader:)
    open nonisolated func relinquishPresentedItem(toReader reader: @escaping ((() -> Void)?) -> Void) { reader(nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/relinquishpresenteditem(towriter:)
    open nonisolated func relinquishPresentedItem(toWriter writer: @escaping ((() -> Void)?) -> Void) { writer(nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/savepresenteditemchanges()
    open nonisolated func savePresentedItemChanges() async throws { }
    // DUPLICATE: open nonisolated func savePresentedItemChanges() async throws
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/observedpresenteditemubiquityattributes
    open var observedPresentedItemUbiquityAttributes: Set<URLResourceKey> { [] }
    // Requirement of NSFilePresenter
    open var presentedItemOperationQueue: OperationQueue { .main }

    // MARK: Window controllers

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/addwindowcontroller(_:)
    @MainActor open func addWindowController(_ windowController: NSWindowController) {
        guard !_windowControllers.contains(where: { $0 === windowController }) else { return }
        if let other = windowController.document as? NSDocument, other !== self { other.removeWindowController(windowController) }
        _windowControllers.append(windowController)
        windowController.document = self
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/removewindowcontroller(_:)
    @MainActor open func removeWindowController(_ windowController: NSWindowController) {
        guard let i = _windowControllers.firstIndex(where: { $0 === windowController }) else { return }
        _windowControllers.remove(at: i)
        if windowController.document === self { windowController._setDocumentWithoutSync(nil) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/windowcontrollers
    @MainActor open var windowControllers: [NSWindowController] { _windowControllers }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/makewindowcontrollers()
    /// Without nibs the default makes one `NSWindowController` for `windowNibName` when
    /// there is one (a plain window; see `NSWindowController.loadWindow`), else nothing:
    /// subclasses override this to create their windows.
    @MainActor open func makeWindowControllers() {
        if let nib = windowNibName {
            let wc = NSWindowController(windowNibName: nib, owner: self)
            windowControllerWillLoadNib(wc)
            addWindowController(wc)
            windowControllerDidLoadNib(wc)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/showwindows()
    @MainActor open func showWindows() {
        for wc in _windowControllers { wc.showWindow(self) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/setwindow(_:)
    @MainActor open func setWindow(_ window: NSWindow?) {
        guard let window else { return }
        if let wc = window.windowController { addWindowController(wc) } else { addWindowController(NSWindowController(window: window)) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/windowcontrollerdidloadnib(_:)
    @MainActor open func windowControllerDidLoadNib(_ windowController: NSWindowController) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/windowcontrollerwillloadnib(_:)
    @MainActor open func windowControllerWillLoadNib(_ windowController: NSWindowController) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/windowforsheet
    @MainActor open var windowForSheet: NSWindow? {
        for wc in _windowControllers where wc.isWindowLoaded { if let w = wc.window, w.isVisible { return w } }
        return _windowControllers.first?.window
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/windownibname
    @MainActor open var windowNibName: NSNib.Name? { nil }

    /// A window controller's window closed: the document drops it and closes itself when
    /// that was its last window (or the controller asked for it).
    @MainActor internal func _windowControllerDidClose(_ wc: NSWindowController) {
        let shouldCloseDocument = wc.shouldCloseDocument || _windowControllers.count <= 1
        removeWindowController(wc)
        if shouldCloseDocument && !_isClosing { close() }
    }

    @MainActor internal func _syncWindowTitles() {
        for wc in _windowControllers { wc.synchronizeWindowTitleWithDocumentName() }
    }

    // MARK: File and type

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/fileurl
    @MainActor open var fileURL: URL? {
        get { _fileURL }
        set { _fileURL = newValue; _syncWindowTitles() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/filetype
    @MainActor open var fileType: String? {
        get { _fileType }
        set { _fileType = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/filemodificationdate
    @MainActor open var fileModificationDate: Date? {
        get { _fileModificationDate }
        set { _fileModificationDate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/displayname
    /// The file's name, or the untitled name the document controller gave ("Untitled",
    /// "Untitled 2", ...).
    @MainActor open var displayName: String! {
        if let url = _fileURL { return url.lastPathComponent }
        return _untitledName ?? "Untitled"
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/defaultdraftname()
    @MainActor open func defaultDraftName() -> String { "Untitled" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/lastcomponentoffilename
    @MainActor open var lastComponentOfFileName: String {
        get { _fileURL?.lastPathComponent ?? _lastComponentOfFileName }
        set { _lastComponentOfFileName = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/isdraft
    @MainActor open var isDraft: Bool {
        get { _isDraft }
        set { _isDraft = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/isentirefileloaded
    @MainActor open var isEntireFileLoaded: Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/isinviewingmode
    @MainActor open var isInViewingMode: Bool { _isInViewingMode }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/islocked
    @MainActor open var isLocked: Bool { _isLocked }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/readabletypes
    @MainActor class public var readableTypes: [String] { NSDocumentController.shared._readableTypes(forDocumentClass: self) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/writabletypes
    @MainActor class public var writableTypes: [String] { NSDocumentController.shared._writableTypes(forDocumentClass: self) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/writabletypes(for:)
    /// The class's writable types; a save (not save-as) of a document of a non-native
    /// type keeps that type.
    open nonisolated func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        MainActor.assumeIsolated {
            var types = type(of: self).writableTypes
            if saveOperation == .saveOperation || saveOperation == .autosaveInPlaceOperation, let t = _fileType, !types.contains(t) { types.append(t) }
            return types
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/isnativetype(_:)
    @MainActor public class func isNativeType(_ type: String) -> Bool {
        readableTypes.contains(type) && writableTypes.contains(type)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/filenameextension(fortype:saveoperation:)
    open nonisolated func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
        MainActor.assumeIsolated { NSDocumentController.shared._fileNameExtension(forType: typeName) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/canconcurrentlyreaddocuments(oftype:)
    @MainActor public class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }

    // MARK: Reading

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/read(from:oftype:)
    open nonisolated func read(from url: URL, ofType typeName: String) throws {
        let wrapper = try FileWrapper(url: url, options: .immediate)
        try read(from: wrapper, ofType: typeName)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/read(from:oftype:)
    open nonisolated func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
        guard fileWrapper.isRegularFile, let data = fileWrapper.regularFileContents else {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileReadCorruptFile.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "The document is a folder; read(from:ofType:) for file wrappers must be overridden to read it."])
        }
        try read(from: data, ofType: typeName)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/read(from:oftype:)
    open nonisolated func read(from data: Data, ofType typeName: String) throws {
        throw NSDocument._overrideError("read(from:ofType:) (data, file wrapper or URL)", reading: true)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/revert(tocontentsof:oftype:)
    @MainActor open func revert(toContentsOf url: URL, ofType typeName: String) throws {
        try read(from: url, ofType: typeName)
        _fileType = typeName
        _fileModificationDate = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        updateChangeCount(.changeCleared)
        _undoManager?.removeAllActions()
        _discardAutosavedContents()
        _syncWindowTitles()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/reverttosaved(_:)
    @MainActor open func revertToSaved(_ sender: Any?) {
        guard let url = _fileURL, let type = _fileType else { return }
        let alert = NSAlert()
        alert.messageText = "Do you want to revert to the most recently saved version of the document \u{201c}\(displayName ?? "")\u{201d}?"
        alert.informativeText = "Your current changes will be lost."
        alert.addButton(withTitle: "Revert")
        alert.addButton(withTitle: "Cancel")
        _runAlert(alert) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            do { try self.revert(toContentsOf: url, ofType: type) } catch { _ = self.presentError(error) }
        }
    }

    // MARK: Writing

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/data(oftype:)
    @MainActor open func data(ofType typeName: String) throws -> Data {
        throw NSDocument._overrideError("data(ofType:), fileWrapper(ofType:) or write(to:ofType:)", reading: false)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/filewrapper(oftype:)
    @MainActor open func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try data(ofType: typeName))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/write(to:oftype:)
    open nonisolated func write(to url: URL, ofType typeName: String) throws {
        let wrapper = try MainActor.assumeIsolated { try fileWrapper(ofType: typeName) }
        try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/write(to:oftype:for:originalcontentsurl:)
    open nonisolated func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, originalContentsURL absoluteOriginalContentsURL: URL?) throws {
        try write(to: url, ofType: typeName)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/writesafely(to:oftype:for:)
    /// Writes to a temporary file beside the destination and swaps it in, so a failed
    /// write leaves the old file intact (the old file is kept as "name~" while
    /// `keepBackupFile`).
    open nonisolated func writeSafely(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) throws {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: directory.path) { try fm.createDirectory(at: directory, withIntermediateDirectories: true) }
        let (original, keepBackup) = MainActor.assumeIsolated { (_fileURL, keepBackupFile) }
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).sb-\(UInt32.random(in: 0...UInt32.max))")
        do {
            try write(to: temporary, ofType: typeName, for: saveOperation, originalContentsURL: original)
            let attributes = try fileAttributesToWrite(to: url, ofType: typeName, for: saveOperation, originalContentsURL: original)
            if !attributes.isEmpty {
                try? fm.setAttributes(attributes.reduce(into: [:]) { $0[FileAttributeKey($1.key)] = $1.value }, ofItemAtPath: temporary.path)
            }
            if fm.fileExists(atPath: url.path) {
                if keepBackup {
                    let backup = directory.appendingPathComponent(url.lastPathComponent + "~")
                    try? fm.removeItem(at: backup)
                    try fm.moveItem(at: url, to: backup)
                } else {
                    try fm.removeItem(at: url)
                }
            }
            try fm.moveItem(at: temporary, to: url)
        } catch {
            try? fm.removeItem(at: temporary)
            throw error
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/fileattributestowrite(to:oftype:for:originalcontentsurl:)
    open nonisolated func fileAttributesToWrite(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, originalContentsURL absoluteOriginalContentsURL: URL?) throws -> [String : Any] { [:] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/keepbackupfile
    @MainActor open var keepBackupFile: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/backupfileurl
    @MainActor open var backupFileURL: URL? {
        guard keepBackupFile, let url = _fileURL else { return nil }
        return url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + "~")
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/canasynchronouslywrite(to:oftype:for:)
    @MainActor open func canAsynchronouslyWrite(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) -> Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/unblockuserinteraction()
    open nonisolated func unblockUserInteraction() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/performasynchronousfileaccess(_:)
    open nonisolated func performAsynchronousFileAccess(_ block: @escaping (@escaping () -> Void) -> Void) { block({}) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/performsynchronousfileaccess(_:)
    open nonisolated func performSynchronousFileAccess(_ block: () -> Void) { block() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/performactivity(withsynchronouswaiting:using:)
    @MainActor open func performActivity(withSynchronousWaiting waitSynchronously: Bool, using block: @escaping (@escaping () -> Void) -> Void) { block({}) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/continueactivity(_:)
    @MainActor open func continueActivity(_ block: () -> Void) { block() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/continueasynchronousworkonmainthread(_:)
    open nonisolated func continueAsynchronousWorkOnMainThread(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async { block() } }
    }

    // MARK: Change count and undo

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/isdocumentedited
    @MainActor open var isDocumentEdited: Bool { _changeCount != 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/hasunautosavedchanges
    @MainActor open var hasUnautosavedChanges: Bool { _changeCount != _autosavedChangeCount }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/updatechangecount(_:)
    @MainActor open func updateChangeCount(_ change: NSDocument.ChangeType) {
        let wasEdited = isDocumentEdited
        switch change {
        case .changeDone, .changeRedone, .changeReadOtherContents: _changeCount += 1
        case .changeUndone: _changeCount -= 1
        case .changeCleared: _changeCount = 0; _autosavedChangeCount = 0; _changeIsDiscardable = false
        case .changeAutosaved: _autosavedChangeCount = _changeCount
        case .changeDiscardable: _changeIsDiscardable = true
        }
        if isDocumentEdited != wasEdited {
            for wc in _windowControllers { wc.setDocumentEdited(isDocumentEdited) }
        }
        if hasUnautosavedChanges { scheduleAutosaving() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/changecounttoken(for:)
    @MainActor open func changeCountToken(for saveOperation: NSDocument.SaveOperationType) -> Any { NSNumber(value: _changeCount) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/updatechangecount(withtoken:for:)
    @MainActor open func updateChangeCount(withToken changeCountToken: Any, for saveOperation: NSDocument.SaveOperationType) {
        guard let saved = (changeCountToken as? NSNumber)?.intValue else { return }
        switch saveOperation {
        case .saveOperation, .saveAsOperation, .autosaveAsOperation:
            let wasEdited = isDocumentEdited
            _changeCount -= saved
            _autosavedChangeCount = _changeCount
            if isDocumentEdited != wasEdited { for wc in _windowControllers { wc.setDocumentEdited(isDocumentEdited) } }
        case .autosaveInPlaceOperation, .autosaveElsewhereOperation:
            _autosavedChangeCount = saved
        case .saveToOperation:
            break
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/hasundomanager
    @MainActor open var hasUndoManager: Bool {
        get { _hasUndoManager }
        set {
            _hasUndoManager = newValue
            if !newValue { _installUndoManager(nil) }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/undomanager
    /// Created on first access while `hasUndoManager`. The document counts closed undo
    /// groups as changes done, undos as changes undone and redos as changes redone, as
    /// AppKit does, so views that register undo actions keep the edited state right.
    @MainActor open var undoManager: UndoManager? {
        get {
            if _undoManager == nil, _hasUndoManager { _installUndoManager(UndoManager()) }
            return _undoManager
        }
        set {
            _installUndoManager(newValue)
            if newValue != nil { _hasUndoManager = true }
        }
    }
    private func _installUndoManager(_ manager: UndoManager?) {
        for o in _undoObservers { NotificationCenter.default.removeObserver(o) }
        _undoObservers = []
        _undoManager = manager
        guard let manager else { return }
        let center = NotificationCenter.default
        func observe(_ name: Notification.Name, _ change: NSDocument.ChangeType, skipWhileUndoing: Bool) {
            _undoObservers.append(center.addObserver(forName: name, object: manager, queue: nil) { [weak self] n in
                MainActor.assumeIsolated {
                    guard let self, let m = n.object as? UndoManager else { return }
                    if skipWhileUndoing && (m.isUndoing || m.isRedoing) { return }
                    self.updateChangeCount(change)
                }
            })
        }
        observe(.NSUndoManagerDidCloseUndoGroup, .changeDone, skipWhileUndoing: true)
        observe(.NSUndoManagerDidUndoChange, .changeUndone, skipWhileUndoing: false)
        observe(.NSUndoManagerDidRedoChange, .changeRedone, skipWhileUndoing: false)
    }

    // MARK: Saving

    /// Shows `alert` as a sheet on the document's window, or modally without one.
    @MainActor internal func _runAlert(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let w = windowForSheet, w.isVisible {
            alert.beginSheetModal(for: w, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    /// Delivers a selector-based completion (`document:shouldClose:contextInfo:`,
    /// `document:didSave:contextInfo:`) through the port's action dispatch, with the Bool
    /// as the sender.
    @MainActor private func _deliver(_ selector: Selector?, to delegate: Any?, _ flag: Bool) {
        guard let selector, let delegate else { return }
        _ = ActionRegistry.perform(selector, on: delegate as AnyObject, with: NSNumber(value: flag))
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/save(_:)
    @MainActor open func save(_ sender: Any?) {
        save(withDelegate: nil, didSave: nil, contextInfo: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/saveas(_:)
    @MainActor open func saveAs(_ sender: Any?) {
        runModalSavePanel(for: .saveAsOperation, delegate: nil, didSave: nil, contextInfo: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/saveto(_:)
    @MainActor open func saveTo(_ sender: Any?) {
        runModalSavePanel(for: .saveToOperation, delegate: nil, didSave: nil, contextInfo: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/save(withdelegate:didsave:contextinfo:)
    @MainActor open func save(withDelegate delegate: Any?, didSave didSaveSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        _saveDocument(with: .saveOperation) { [weak self] saved in self?._deliver(didSaveSelector, to: delegate, saved) }
    }

    /// Save: in place when the document has a file and a type, else through the save panel.
    @MainActor internal func _saveDocument(with operation: NSDocument.SaveOperationType, completion: @escaping (Bool) -> Void) {
        if operation == .saveOperation, let url = _fileURL, let type = _fileType, !isDraft {
            save(to: url, ofType: type, for: .saveOperation) { [weak self] error in
                if let error, let self { _ = self.presentError(error) }
                completion(error == nil)
            }
        } else {
            _runSavePanel(for: operation == .saveOperation ? .saveAsOperation : operation, completion: completion)
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/runmodalsavepanel(for:delegate:didsave:contextinfo:)
    @MainActor open func runModalSavePanel(for saveOperation: NSDocument.SaveOperationType, delegate: Any?, didSave didSaveSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        _runSavePanel(for: saveOperation) { [weak self] saved in self?._deliver(didSaveSelector, to: delegate, saved) }
    }

    /// The save panel for `operation`, as a sheet on the document's window when it has
    /// one: the writable types as its content types, the display name as the suggested
    /// name, then `save(to:ofType:for:completionHandler:)` with the chosen file.
    @MainActor internal func _runSavePanel(for operation: NSDocument.SaveOperationType, completion: @escaping (Bool) -> Void) {
        let panel = NSSavePanel()
        let types = writableTypes(for: operation)
        let contentTypes = types.compactMap { UTType($0) }
        if !contentTypes.isEmpty {
            panel.allowedContentTypes = contentTypes
            for type in types { if let name = NSDocumentController.shared.displayName(forType: type) { panel._typeDisplayNames[type] = name } }
        } else {
            let extensions = types.compactMap { fileNameExtension(forType: $0, saveOperation: operation) }
            if !extensions.isEmpty { panel.allowedFileTypes = extensions }
        }
        if let current = _fileType ?? NSDocumentController.shared.defaultType, let type = UTType(current), contentTypes.contains(type) {
            panel.currentContentType = type
        }
        if let url = _fileURL {
            panel.directoryURL = url.deletingLastPathComponent()
            panel.nameFieldStringValue = url.lastPathComponent
        } else {
            var name = displayName ?? "Untitled"
            if (name as NSString).pathExtension.isEmpty, let type = panel.currentContentType ?? contentTypes.first,
               let ext = type.preferredFilenameExtension ?? fileNameExtension(forType: type.identifier, saveOperation: operation) {
                name += "." + ext
            } else if (name as NSString).pathExtension.isEmpty, let first = types.first, let ext = fileNameExtension(forType: first, saveOperation: operation) {
                name += "." + ext
            }
            panel.nameFieldStringValue = name
        }
        panel.canSelectHiddenExtension = true
        guard prepareSavePanel(panel) else { completion(false); return }
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { completion(false); return }
            guard response == .OK, let url = panel.url else { completion(false); return }
            self._fileNameExtensionWasHiddenInLastRunSavePanel = panel.isExtensionHidden
            let typeName = self._typeName(forSaving: url, chosen: panel.currentContentType, among: types)
            self._fileTypeFromLastRunSavePanel = typeName
            self.save(to: url, ofType: typeName, for: operation) { error in
                if let error { _ = self.presentError(error) }
                completion(error == nil)
            }
        }
        if let w = windowForSheet, w.isVisible { panel.beginSheetModal(for: w, completionHandler: finish) } else { finish(panel.runModal()) }
    }

    /// The type to save `url` as: the panel's chosen type when it is writable, else the
    /// writable type the extension conforms to, else the document's own or the first.
    @MainActor private func _typeName(forSaving url: URL, chosen: UTType?, among types: [String]) -> String {
        if let c = chosen, types.contains(c.identifier) { return c.identifier }
        let ext = url.pathExtension
        if !ext.isEmpty {
            if let byExtension = UTType(filenameExtension: ext), let match = types.first(where: { UTType($0).map { byExtension.conforms(to: $0) } ?? false }) { return match }
            if let match = types.first(where: { fileNameExtension(forType: $0, saveOperation: .saveAsOperation)?.lowercased() == ext.lowercased() }) { return match }
        }
        if let t = _fileType, types.contains(t) { return t }
        return types.first ?? _fileType ?? NSDocumentController.shared.defaultType ?? ""
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/preparesavepanel(_:)
    @MainActor open func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/shouldrunsavepanelwithaccessoryview
    @MainActor open var shouldRunSavePanelWithAccessoryView: Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/savepanelshowsfileformatscontrol
    @MainActor open var savePanelShowsFileFormatsControl: Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/filetypefromlastrunsavepanel
    @MainActor open var fileTypeFromLastRunSavePanel: String? { _fileTypeFromLastRunSavePanel }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/filenameextensionwashiddeninlastrunsavepanel
    @MainActor open var fileNameExtensionWasHiddenInLastRunSavePanel: Bool { _fileNameExtensionWasHiddenInLastRunSavePanel }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/save(to:oftype:for:completionhandler:)
    /// Writes safely, then records the new file for save and save-as (clearing the change
    /// count and noting the document as recent); a save-to leaves the document as it was.
    @MainActor open func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, completionHandler: @escaping ((any Error)?) -> Void) {
        let token = changeCountToken(for: saveOperation)
        do {
            try checkAutosavingSafety()
            try writeSafely(to: url, ofType: typeName, for: saveOperation)
        } catch {
            completionHandler(willPresentError(error))
            return
        }
        switch saveOperation {
        case .saveOperation, .saveAsOperation, .autosaveAsOperation:
            _fileURL = url
            _fileType = typeName
            _isDraft = false
            _fileModificationDate = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            updateChangeCount(withToken: token, for: saveOperation)
            updateChangeCount(.changeCleared)
            _discardAutosavedContents()
            NSDocumentController.shared.noteNewRecentDocument(self)
            _syncWindowTitles()
        case .autosaveInPlaceOperation:
            _fileModificationDate = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            updateChangeCount(withToken: token, for: saveOperation)
        case .autosaveElsewhereOperation:
            _autosavedContentsFileURL = url
            updateChangeCount(withToken: token, for: saveOperation)
        case .saveToOperation:
            break
        }
        completionHandler(nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/save(to:oftype:for:)
    @MainActor open func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
            save(to: url, ofType: typeName, for: saveOperation) { error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            }
        }
    }
    // DUPLICATE: @MainActor open func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) async throws
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/save(to:oftype:for:delegate:didsave:contextinfo:)
    @MainActor open func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, delegate: Any?, didSave didSaveSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            if let error, let self { _ = self.presentError(error) }
            self?._deliver(didSaveSelector, to: delegate, error == nil)
        }
    }

    // MARK: Autosaving

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/autosavesinplace
    @MainActor class public var autosavesInPlace: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/autosavesdrafts
    @MainActor class public var autosavesDrafts: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/preservesversions
    @MainActor class public var preservesVersions: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/usesubiquitousstorage
    @MainActor class public var usesUbiquitousStorage: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/autosavingfiletype
    @MainActor open var autosavingFileType: String? { _fileType }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/autosavedcontentsfileurl
    nonisolated open var autosavedContentsFileURL: URL? {
        get { MainActor.assumeIsolated { _autosavedContentsFileURL } }
        set { MainActor.assumeIsolated { _autosavedContentsFileURL = newValue } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/autosavingisimplicitlycancellable
    @MainActor open var autosavingIsImplicitlyCancellable: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/checkautosavingsafety()
    @MainActor open func checkAutosavingSafety() throws { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/scheduleautosaving()
    /// Arms a timer for `NSDocumentController.autosavingDelay` (nothing when it is 0);
    /// when it fires with unautosaved changes the document autosaves.
    @MainActor open func scheduleAutosaving() {
        let delay = NSDocumentController.shared.autosavingDelay
        guard delay > 0, _autosaveTimer == nil, !_isClosing else { return }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self._autosaveTimer = nil
                guard self.hasUnautosavedChanges else { return }
                self.autosave(withImplicitCancellability: true) { _ in }
            }
        }
        RunLoop.main.add(timer, forMode: .default)
        _autosaveTimer = timer
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/autosave(withimplicitcancellability:completionhandler:)
    /// Autosaves in place when the class `autosavesInPlace` and the document has a file,
    /// else to `autosavedContentsFileURL` in the document controller's autosave directory.
    @MainActor open func autosave(withImplicitCancellability autosavingIsImplicitlyCancellable: Bool, completionHandler: @escaping ((any Error)?) -> Void) {
        guard hasUnautosavedChanges, let typeName = autosavingFileType else { completionHandler(nil); return }
        if Swift.type(of: self).autosavesInPlace, let url = _fileURL {
            save(to: url, ofType: typeName, for: .autosaveInPlaceOperation, completionHandler: completionHandler)
            return
        }
        let url: URL
        if let existing = _autosavedContentsFileURL {
            url = existing
        } else {
            let directory = NSDocumentController.shared._autosaveDirectory
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var name = displayName ?? "Untitled"
            if (name as NSString).pathExtension.isEmpty, let ext = fileNameExtension(forType: typeName, saveOperation: .autosaveElsewhereOperation) { name += "." + ext }
            url = directory.appendingPathComponent("\(name) (Autosaved \(getpid())-\(ObjectIdentifier(self).hashValue & 0xffff))")
        }
        save(to: url, ofType: typeName, for: .autosaveElsewhereOperation, completionHandler: completionHandler)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/autosave(withimplicitcancellability:)
    @MainActor open func autosave(withImplicitCancellability autosavingIsImplicitlyCancellable: Bool) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
            autosave(withImplicitCancellability: autosavingIsImplicitlyCancellable) { error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            }
        }
    }
    // DUPLICATE: @MainActor open func autosave(withImplicitCancellability autosavingIsImplicitlyCancellable: Bool) async throws
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/autosave(withdelegate:didautosave:contextinfo:)
    @MainActor open func autosave(withDelegate delegate: Any?, didAutosave didAutosaveSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        autosave(withImplicitCancellability: false) { [weak self] error in self?._deliver(didAutosaveSelector, to: delegate, error == nil) }
    }
    /// Removes an autosaved-elsewhere file once the document is saved, reverted or closed.
    @MainActor private func _discardAutosavedContents() {
        guard let url = _autosavedContentsFileURL else { return }
        _autosavedContentsFileURL = nil
        if url != _fileURL { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: Closing

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/canclose(withdelegate:shouldclose:contextinfo:)
    /// With unsaved changes, asks "Do you want to save the changes...?" (Save, Cancel,
    /// Don't Save) as a sheet on the document's window; Save goes through the save flow.
    @MainActor open func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        _canClose { [weak self] shouldClose in self?._deliver(shouldCloseSelector, to: delegate, shouldClose) }
    }

    @MainActor internal func _canClose(_ completion: @escaping (Bool) -> Void) {
        guard isDocumentEdited, !_changeIsDiscardable else { completion(true); return }
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to the document \u{201c}\(displayName ?? "")\u{201d}?"
        alert.informativeText = "Your changes will be lost if you don\u{2019}t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don\u{2019}t Save")
        _runAlert(alert) { [weak self] response in
            guard let self else { completion(false); return }
            switch response {
            case .alertFirstButtonReturn: self._saveDocument(with: .saveOperation, completion: completion)
            case .alertThirdButtonReturn: completion(true)
            default: completion(false)
            }
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/shouldclosewindowcontroller(_:delegate:shouldclose:contextinfo:)
    @MainActor open func shouldCloseWindowController(_ windowController: NSWindowController, delegate: Any?, shouldClose shouldCloseSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        _shouldCloseWindowController(windowController) { [weak self] shouldClose in self?._deliver(shouldCloseSelector, to: delegate, shouldClose) }
    }

    /// Closing the last window (or one that closes the document) asks `canClose`.
    @MainActor internal func _shouldCloseWindowController(_ windowController: NSWindowController, completion: @escaping (Bool) -> Void) {
        if windowController.shouldCloseDocument || _windowControllers.filter({ $0 !== windowController }).isEmpty {
            _canClose(completion)
        } else {
            completion(true)
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/close()
    @MainActor open func close() {
        guard !_isClosing else { return }
        _isClosing = true
        _autosaveTimer?.invalidate()
        _autosaveTimer = nil
        for wc in _windowControllers { wc.close() }
        _windowControllers.removeAll()
        _discardAutosavedContents()
        NSDocumentController._shared?.removeDocument(self)
    }

    // MARK: Duplicating, moving, renaming, locking

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/duplicate()
    @MainActor open func duplicate() throws -> NSDocument {
        let dc = NSDocumentController.shared
        let doc: NSDocument
        if let url = _fileURL, let type = _fileType, !isDocumentEdited {
            doc = try dc.duplicateDocument(withContentsOf: url, copying: true, displayName: (displayName as NSString?)?.deletingPathExtension)
            _ = type
        } else {
            doc = try dc.makeUntitledDocument(ofType: _fileType ?? dc.defaultType ?? "")
            dc.addDocument(doc)
            doc.makeWindowControllers()
            doc.showWindows()
        }
        return doc
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/duplicate(_:)
    @MainActor open func duplicate(_ sender: Any?) {
        do { _ = try duplicate() } catch { _ = presentError(error) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/duplicate(withdelegate:didduplicate:contextinfo:)
    @MainActor open func duplicate(withDelegate delegate: Any?, didDuplicate didDuplicateSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        let ok = (try? duplicate()) != nil
        _deliver(didDuplicateSelector, to: delegate, ok)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/move(to:)
    @MainActor open func move(to url: URL) async throws {
        guard let current = _fileURL else {
            guard let type = _fileType ?? NSDocumentController.shared.defaultType else { throw NSDocument._overrideError("fileType", reading: false) }
            try await save(to: url, ofType: type, for: .saveAsOperation)
            return
        }
        try FileManager.default.moveItem(at: current, to: url)
        fileURL = url
    }
    // DUPLICATE: @MainActor open func move(to url: URL) async throws
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/move()
    @MainActor open func move() async -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = displayName ?? "Untitled"
        panel.prompt = "Move"
        if let url = _fileURL { panel.directoryURL = url.deletingLastPathComponent() }
        let response: NSApplication.ModalResponse
        if let w = windowForSheet { response = await panel.beginSheetModal(for: w) } else { response = panel.runModal() }
        guard response == .OK, let url = panel.url else { return false }
        do { try await move(to: url); return true } catch { _ = presentError(error); return false }
    }
    // DUPLICATE: @MainActor open func move() async -> Bool
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/move(_:)
    @MainActor open func move(_ sender: Any?) { Task { @MainActor in _ = await move() } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/movetoubiquitycontainer(_:)
    @MainActor open func moveToUbiquityContainer(_ sender: Any?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/rename(_:)
    @MainActor open func rename(_ sender: Any?) { saveAs(sender) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/lock()
    @MainActor open func lock() async -> Bool { _isLocked = true; return true }
    // DUPLICATE: @MainActor open func lock() async -> Bool
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/lock()
    @MainActor open func lock() async throws { _isLocked = true }
    // DUPLICATE: @MainActor open func lock() async throws
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/lock(_:)
    @MainActor open func lock(_ sender: Any?) { _isLocked = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/unlock()
    @MainActor open func unlock() async -> Bool { _isLocked = false; return true }
    // DUPLICATE: @MainActor open func unlock() async -> Bool
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/unlock()
    @MainActor open func unlock() async throws { _isLocked = false }
    // DUPLICATE: @MainActor open func unlock() async throws
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/unlock(_:)
    @MainActor open func unlock(_ sender: Any?) { _isLocked = false }

    // MARK: Versions, sharing, printing, PDF (not implemented)

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/browseversions(_:)
    @MainActor open func browseVersions(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/isbrowsingversions
    @MainActor open var isBrowsingVersions: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/stopbrowsingversions()
    @MainActor open func stopBrowsingVersions() async { }
    // DUPLICATE: @MainActor open func stopBrowsingVersions() async
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/allowsdocumentsharing
    @available(macOS 10.13, *)
    @MainActor open var allowsDocumentSharing: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/prepare(_:)
    @MainActor open func prepare(_ sharingServicePicker: NSSharingServicePicker) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/share(with:)
    @MainActor open func share(with sharingService: NSSharingService) async -> Bool { false }
    // DUPLICATE: @MainActor open func share(with sharingService: NSSharingService) async -> Bool
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/previewrepresentableactivityitems
    @available(macOS 13.2, *)
    @MainActor open var previewRepresentableActivityItems: [any NSPreviewRepresentableActivityItem]? {
        get { nil }
        set { }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/pdfprintoperation
    @MainActor open var pdfPrintOperation: NSPrintOperation { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/preparepagelayout(_:)
    @MainActor open func preparePageLayout(_ pageLayout: NSPageLayout) -> Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/print(withsettings:showprintpanel:delegate:didprint:contextinfo:)
    @MainActor open func print(withSettings printSettings: [NSPrintInfo.AttributeKey : Any], showPrintPanel: Bool, delegate: Any?, didPrint didPrintSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/printdocument(_:)
    @MainActor open func printDocument(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/printinfo
    @MainActor open var printInfo: NSPrintInfo {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/printoperation(withsettings:)
    @MainActor open func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey : Any]) throws -> NSPrintOperation { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/runmodalpagelayout(with:delegate:didrun:contextinfo:)
    @MainActor open func runModalPageLayout(with printInfo: NSPrintInfo, delegate: Any?, didRun didRunSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/runmodalprintoperation(_:delegate:didrun:contextinfo:)
    @MainActor open func runModalPrintOperation(_ printOperation: NSPrintOperation, delegate: Any?, didRun didRunSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/runpagelayout(_:)
    @MainActor open func runPageLayout(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/savetopdf(_:)
    @MainActor open func saveToPDF(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/shouldchangeprintinfo(_:)
    @MainActor open func shouldChangePrintInfo(_ newPrintInfo: NSPrintInfo) -> Bool { true }

    // MARK: Errors

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/presenterror(_:)
    @MainActor open func presentError(_ error: any Error) -> Bool {
        let shown = willPresentError(error)
        if let w = windowForSheet, w.isVisible {
            NSAlert(error: shown).beginSheetModal(for: w)
        } else {
            _ = NSAlert(error: shown).runModal()
        }
        return false
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/presenterror(_:modalfor:delegate:didpresent:contextinfo:)
    @MainActor open func presentError(_ error: any Error, modalFor window: NSWindow, delegate: Any?, didPresent didPresentSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        NSAlert(error: willPresentError(error)).beginSheetModal(for: window) { [weak self] _ in self?._deliver(didPresentSelector, to: delegate, false) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/willnotpresenterror(_:)
    @MainActor open func willNotPresentError(_ error: any Error) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/willpresenterror(_:)
    @MainActor open func willPresentError(_ error: any Error) -> any Error { error }

    // MARK: State restoration and user activities (not implemented)

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/allowedclasses(forrestorablestatekeypath:)
    @available(macOS 12.0, *)
    @MainActor public class func allowedClasses(forRestorableStateKeyPath keyPath: String) -> [AnyClass] { [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/encoderestorablestate(with:)
    @MainActor open func encodeRestorableState(with coder: NSCoder) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/encoderestorablestate(with:backgroundqueue:)
    @MainActor open func encodeRestorableState(with coder: NSCoder, backgroundQueue queue: OperationQueue) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/invalidaterestorablestate()
    @MainActor open func invalidateRestorableState() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/restorablestatekeypaths
    @MainActor class public var restorableStateKeyPaths: [String] { [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/restorestate(with:)
    @MainActor open func restoreState(with coder: NSCoder) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/restorewindow(withidentifier:state:)
    @MainActor open func restoreWindow(withIdentifier identifier: NSUserInterfaceItemIdentifier, state: NSCoder) async throws -> NSWindow { unimplemented() }
    // DUPLICATE: @MainActor open func restoreWindow(withIdentifier identifier: NSUserInterfaceItemIdentifier, state: NSCoder) async throws -> NSWindow
    // SKIPPED (Foundation.NSUserActivity not in corelibs): @MainActor func updateUserActivityState(_ activity: NSUserActivity)
    // SKIPPED (Foundation.NSUserActivity not in corelibs): @MainActor var userActivity: NSUserActivity? { get set }
    // SKIPPED (Foundation.NSCloseCommand not in corelibs): @MainActor func handleClose(_ command: NSCloseCommand) -> Any?
    // SKIPPED (Foundation.NSScriptCommand not in corelibs): @MainActor func handlePrint(_ command: NSScriptCommand) -> Any?
    // SKIPPED (Foundation.NSScriptCommand not in corelibs): @MainActor func handleSave(_ command: NSScriptCommand) -> Any?
    // SKIPPED (Foundation.NSScriptObjectSpecifier not in corelibs): @MainActor var objectSpecifier: NSScriptObjectSpecifier { get }

    // MARK: Menu actions and validation

    /// The File menu actions a document answers through the responder chain.
    private static let _actions: Set<String> = ["saveDocument:", "saveDocumentAs:", "saveDocumentTo:", "revertDocumentToSaved:", "duplicateDocument:", "renameDocument:", "moveDocument:", "lockDocument:", "unlockDocument:"]

    open func respondsToSelectorAction(_ action: Selector) -> Bool { NSDocument._actions.contains(NSStringFromSelector(action)) }

    open func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch NSStringFromSelector(action) {
        case "saveDocument:": save(sender)
        case "saveDocumentAs:": saveAs(sender)
        case "saveDocumentTo:": saveTo(sender)
        case "revertDocumentToSaved:": revertToSaved(sender)
        case "duplicateDocument:": duplicate(sender)
        case "renameDocument:": rename(sender)
        case "moveDocument:": move(sender)
        case "lockDocument:": lock(sender)
        case "unlockDocument:": unlock(sender)
        default: return false
        }
        return true
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocument/validateuserinterfaceitem(_:)
    @MainActor open func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        guard let action = item.action else { return true }
        switch NSStringFromSelector(action) {
        case "revertDocumentToSaved:": return _fileURL != nil && (isDocumentEdited || _autosavedContentsFileURL != nil)
        case "saveDocument:": return isDocumentEdited || _fileURL == nil || isDraft
        case "lockDocument:": return !_isLocked && _fileURL != nil
        case "unlockDocument:": return _isLocked
        case "renameDocument:", "moveDocument:": return _fileURL != nil
        default: return true
        }
    }
    // Requirement of NSMenuItemValidation
    @MainActor open func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { validateUserInterfaceItem(menuItem) }
}
