// NSSavePanel (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
//
// The panel has two faces (ADR-0017). Where the backend offers a `PlatformFileDialog`
// (the Windows common item dialog, the xdg-desktop-portal FileChooser on Linux) the
// panel's properties become `PlatformFileDialogOptions` and the native dialog runs; the
// delegate's `validate` is applied to what it chose. Elsewhere (the host backend, Linux
// without a portal, `APPKITWIN_FILE_DIALOG=package`) the panel draws itself: a name field
// (save), a directory field with Up, the directory listing in an `NSTableView`, a type
// pop-up, New Folder, Cancel and the prompt button, driven by the keyboard (arrows,
// Return opens or confirms, Escape cancels) and exposed to accessibility through the
// ordinary controls.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel
@MainActor open class NSSavePanel: NSPanel {
    // MARK: Storage
    internal var _prompt: String? = nil
    internal var _message: String? = nil
    internal var _nameFieldLabel: String? = nil
    internal var _nameFieldStringValue = ""
    internal var _directoryURL: URL? = nil
    internal var _allowedFileTypes: [String]? = nil
    internal var _allowedContentTypes: [UTType] = []
    /// Display names by type identifier (a document's `CFBundleTypeName`s, through
    /// `NSDocumentController.displayName(forType:)`), shown instead of the type's description.
    internal var _typeDisplayNames: [String: String] = [:]
    internal var _currentContentType: UTType? = nil
    internal var _allowsOtherFileTypes = false
    internal var _canCreateDirectories = true
    internal var _canSelectHiddenExtension = false
    internal var _isExtensionHidden = false
    internal var _showsHiddenFiles = false
    internal var _showsTagField = false
    internal var _showsContentTypes = true
    internal var _treatsFilePackagesAsDirectories = false
    internal var _accessoryView: NSView? = nil
    internal var _tagNames: [String]? = nil
    internal var _urls: [URL] = []
    private var _isExpanded = false
    /// The directory the last panel ended in: the default for the next one, as on macOS.
    internal static var _lastDirectory: URL? = nil

    /// How the package-drawn panel was started, so `ok`/`cancel` know how to end it.
    internal enum _Mode {
        case modal
        case modeless((NSApplication.ModalResponse) -> Void)
        case sheet(NSWindow, (NSApplication.ModalResponse) -> Void)
    }
    internal var _mode: _Mode? = nil
    internal var _controller: _NSFilePanelController? = nil

    /// Creates a panel. The native dialog is created when run.
    @MainActor public class func savePanel() -> NSSavePanel { NSSavePanel() }

    @MainActor public convenience init() {
        self.init(contentRect: NSRect(x: 0, y: 0, width: 620, height: 440), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        minSize = NSSize(width: 420, height: 300)
    }

    @MainActor public override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }
    @MainActor public required init?(coder: NSCoder) { super.init(coder: coder) }

    // MARK: Options and the native dialog

    /// Extensions the panel accepts (without dots): the deprecated `allowedFileTypes`
    /// and every extension of `allowedContentTypes`. Empty means any file.
    @MainActor internal var _allowedExtensions: [String] {
        var out: [String] = []
        for t in _allowedFileTypes ?? [] where !out.contains(t.lowercased()) { out.append(t.lowercased()) }
        for type in _allowedContentTypes {
            for e in type.tags[.filenameExtension] ?? [] where !out.contains(e.lowercased()) { out.append(e.lowercased()) }
        }
        return out
    }

    @MainActor internal func _options() -> PlatformFileDialogOptions {
        var o = PlatformFileDialogOptions()
        o.isSave = !(self is NSOpenPanel)
        o.title = title.isEmpty ? nil : title
        o.prompt = _prompt
        o.message = _message
        o.directory = _directoryURL ?? NSSavePanel._lastDirectory
        o.defaultName = _nameFieldStringValue.isEmpty ? nil : _nameFieldStringValue
        o.allowedExtensions = _allowedExtensions
        o.allowedTypeDescriptions = _allowedContentTypes.isEmpty ? [] : o.allowedExtensions.map { ext in
            let type = _allowedContentTypes.first { ($0.tags[.filenameExtension] ?? []).contains(ext) }
            return type.flatMap { _typeDisplayNames[$0.identifier] ?? $0.localizedDescription } ?? ext.uppercased()
        }
        o.allowsOtherTypes = _allowsOtherFileTypes || o.allowedExtensions.isEmpty
        o.canCreateDirectories = _canCreateDirectories
        o.showsHiddenFiles = _showsHiddenFiles
        o.treatsFilePackagesAsDirectories = _treatsFilePackagesAsDirectories
        return o
    }

    @MainActor internal var _panelDelegate: (any NSOpenSavePanelDelegate)? { delegate as? NSOpenSavePanelDelegate }

    /// Runs the native dialog and records its answer; nil when the backend has none.
    @MainActor internal func _runNative(parent: NSWindow?) -> NSApplication.ModalResponse? {
        guard let dialog = Platform.backend.fileDialog else { return nil }
        guard let result = dialog.run(_options(), parent: parent?._platformWindow) else {
            _urls = []
            return .cancel
        }
        if let d = _panelDelegate {
            for url in result {
                do { try d.panel(self, validate: url) } catch {
                    _ = NSAlert(error: error).runModal()
                    _urls = []
                    return .cancel
                }
            }
        }
        _accept(result)
        return .OK
    }

    /// Records a choice: the URLs, the directory for next time and the name field.
    @MainActor internal func _accept(_ urls: [URL]) {
        _urls = urls
        if let first = urls.first {
            let dir = first.deletingLastPathComponent()
            _directoryURL = dir
            NSSavePanel._lastDirectory = dir
            _nameFieldStringValue = first.lastPathComponent
        }
    }

    // MARK: The package-drawn panel

    /// Builds the package panel's content if the backend has no native dialog.
    @MainActor internal func _preparePackagePanel() {
        if _controller == nil { _controller = _NSFilePanelController(panel: self) }
        _controller?.prepare()
    }

    /// Ends the package-drawn panel with `response` and reports to whoever started it.
    @MainActor internal func _finish(_ response: NSApplication.ModalResponse) {
        guard let mode = _mode else { return }
        _mode = nil
        switch mode {
        case .modal:
            NSApplication.shared.stopModal(withCode: response)
        case .modeless(let completion):
            orderOut(nil)
            completion(response)
        case .sheet(let parent, let completion):
            parent.endSheet(self, returnCode: response)
            completion(response)
        }
    }

    public override func platformWindowDidChangeFrame(_ frame: NSRect) {
        super.platformWindowDidChangeFrame(frame)
        _controller?.layoutIfBuilt()
    }

    // MARK: Running

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/runmodal()
    @MainActor open func runModal() -> NSApplication.ModalResponse {
        if let native = _runNative(parent: NSApplication.shared.keyWindow) { return native }
        _preparePackagePanel()
        _mode = .modal
        center()
        let response = NSApplication.shared.runModal(for: self)
        _mode = nil
        orderOut(nil)
        return response
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/begin(completionhandler:)
    @MainActor open func begin(completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {
        if let native = _runNative(parent: NSApplication.shared.keyWindow) { handler(native); return }
        _preparePackagePanel()
        _mode = .modeless(handler)
        center()
        makeKeyAndOrderFront(nil)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/beginsheetmodal(for:completionhandler:)
    @MainActor open func beginSheetModal(for window: NSWindow, completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {
        if let native = _runNative(parent: window) { handler(native); return }
        _preparePackagePanel()
        _mode = .sheet(window, handler)
        window.beginSheet(self)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/begin()
    @MainActor open func begin() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { c in begin { c.resume(returning: $0) } }
    }
    // DUPLICATE: @MainActor open func begin() async -> NSApplication.ModalResponse
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/beginsheetmodal(for:)
    @MainActor open func beginSheetModal(for window: NSWindow) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { c in beginSheetModal(for: window) { c.resume(returning: $0) } }
    }
    // DUPLICATE: @MainActor open func beginSheetModal(for window: NSWindow) async -> NSApplication.ModalResponse

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/ok(_:)
    /// The package panel's confirm action: validates the name or selection and ends the
    /// panel with `.OK`.
    @MainActor open func ok(_ sender: Any?) {
        guard _mode != nil, let c = _controller else { return }
        c.confirm()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/cancel(_:)
    @MainActor open func cancel(_ sender: Any?) {
        _urls = []
        if _mode != nil { _finish(.cancel) }
    }

    // MARK: Properties

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/accessoryview
    @MainActor open var accessoryView: NSView? {
        get { _accessoryView }
        set { _accessoryView = newValue; _controller?.layoutIfBuilt() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/allowedcontenttypes
    @available(macOS 11.0, *)
    @MainActor open var allowedContentTypes: [UTType] {
        get { _allowedContentTypes }
        set { _allowedContentTypes = newValue; _controller?.reloadIfBuilt() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/allowedfiletypes
    @MainActor open var allowedFileTypes: [String]? {
        get { _allowedFileTypes }
        set { _allowedFileTypes = newValue; _controller?.reloadIfBuilt() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/allowsotherfiletypes
    @MainActor open var allowsOtherFileTypes: Bool {
        get { _allowsOtherFileTypes }
        set { _allowsOtherFileTypes = newValue; _controller?.reloadIfBuilt() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/cancreatedirectories
    @MainActor open var canCreateDirectories: Bool {
        get { _canCreateDirectories }
        set { _canCreateDirectories = newValue; _controller?.layoutIfBuilt() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/canselecthiddenextension
    @MainActor open var canSelectHiddenExtension: Bool {
        get { _canSelectHiddenExtension }
        set { _canSelectHiddenExtension = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/currentcontenttype
    @available(macOS 11.0, *)
    @MainActor open var currentContentType: UTType? {
        get { _currentContentType ?? _allowedContentTypes.first }
        set { _currentContentType = newValue; _controller?.reloadIfBuilt() }
    }
    // The delegate: `NSOpenSavePanelDelegate` refines `NSWindowDelegate`, so it lives in
    // `NSWindow.delegate` (see NSOpenSavePanelDelegate.swift).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/directoryurl
    @MainActor open var directoryURL: URL? {
        get { _directoryURL }
        set { _directoryURL = newValue; _controller?.reloadIfBuilt() }
    }
    // INHERITED (identical redeclaration): @MainActor var identifier: NSUserInterfaceItemIdentifier? { get set }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/isexpanded
    @MainActor open var isExpanded: Bool {
        get { _isExpanded }
        set { _isExpanded = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/isextensionhidden
    @MainActor open var isExtensionHidden: Bool {
        get { _isExtensionHidden }
        set { _isExtensionHidden = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/message
    @MainActor open var message: String! {
        get { _message }
        set { _message = newValue; _controller?.layoutIfBuilt() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/namefieldlabel
    @MainActor open var nameFieldLabel: String! {
        get { _nameFieldLabel }
        set { _nameFieldLabel = newValue; _controller?.layoutIfBuilt() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/namefieldstringvalue
    @MainActor open var nameFieldStringValue: String {
        get { _controller?.nameFieldValueIfBuilt ?? _nameFieldStringValue }
        set { _nameFieldStringValue = newValue; _controller?.setNameFieldIfBuilt(newValue) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/prompt
    @MainActor open var prompt: String! {
        get { _prompt }
        set { _prompt = newValue; _controller?.layoutIfBuilt() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/showscontenttypes
    @available(macOS 15.0, *)
    @MainActor open var showsContentTypes: Bool {
        get { _showsContentTypes }
        set { _showsContentTypes = newValue; _controller?.layoutIfBuilt() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/showshiddenfiles
    @MainActor open var showsHiddenFiles: Bool {
        get { _showsHiddenFiles }
        set { _showsHiddenFiles = newValue; _controller?.reloadIfBuilt() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/showstagfield
    @MainActor open var showsTagField: Bool {
        get { _showsTagField }
        set { _showsTagField = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/tagnames
    @MainActor open var tagNames: [String]? {
        get { _tagNames }
        set { _tagNames = newValue }
    }
    // SKIPPED (override type String! differs from superclass String): @MainActor var title: String! { get set }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/treatsfilepackagesasdirectories
    @MainActor open var treatsFilePackagesAsDirectories: Bool {
        get { _treatsFilePackagesAsDirectories }
        set { _treatsFilePackagesAsDirectories = newValue; _controller?.reloadIfBuilt() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/url
    @MainActor open var url: URL? { _urls.first }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/validatevisiblecolumns()
    @MainActor open func validateVisibleColumns() { _controller?.reloadIfBuilt() }
}

// MARK: - The package-drawn panel

/// Builds and drives the views of a package-drawn `NSSavePanel`/`NSOpenPanel`.
@MainActor
final class _NSFilePanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSelectorHandling {
    struct Entry {
        var url: URL
        var name: String
        var isDirectory: Bool
        var modified: Date?
        var size: Int?
        /// Passes the type filter and the delegate; otherwise shown dimmed and unselectable.
        var isEnabled: Bool
    }

    private unowned let panel: NSSavePanel
    private var isOpenPanel: Bool { panel is NSOpenPanel }
    private var openPanel: NSOpenPanel? { panel as? NSOpenPanel }
    private(set) var built = false
    private(set) var directory: URL
    private(set) var entries: [Entry] = []

    private let messageLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "Save As:")
    let nameField = NSTextField(string: "")
    private let whereLabel = NSTextField(labelWithString: "Where:")
    let pathField = NSTextField(string: "")
    let upButton = NSButton(title: "Up", target: nil, action: nil)
    let table = NSTableView(frame: .zero)
    private let scroll = NSScrollView(frame: .zero)
    private let typeLabel = NSTextField(labelWithString: "File Format:")
    let typePopUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 24), pullsDown: false)
    let newFolderButton = NSButton(title: "New Folder\u{2026}", target: nil, action: nil)
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    let okButton = NSButton(title: "Save", target: nil, action: nil)
    private var accessoryContainer: NSView? = nil
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    init(panel: NSSavePanel) {
        self.panel = panel
        self.directory = panel._directoryURL ?? NSSavePanel._lastDirectory ?? URL(fileURLWithPath: NSHomeDirectory())
        super.init()
    }

    // MARK: Building

    /// Builds the views on first use, then refreshes everything from the panel's properties.
    func prepare() {
        if !built { build() }
        if let d = panel._directoryURL { directory = d }
        nameField.stringValue = panel._isExtensionHidden ? Self.hidingExtension(panel._nameFieldStringValue) : panel._nameFieldStringValue
        layout()
        reloadTypes()
        load(directory)
        panel.makeFirstResponder(isOpenPanel ? table : nameField)
        if !isOpenPanel { nameField.selectText(nil) }
    }

    private func build() {
        built = true
        guard let content = panel.contentView else { return }
        messageLabel.font = NSFont.systemFont(ofSize: 12)
        messageLabel.setAccessibilityLabel("Message")
        nameField.target = self
        nameField.action = Selector(("confirm:"))
        nameField.setAccessibilityLabel("Save As")
        pathField.target = self
        pathField.action = Selector(("pathEntered:"))
        pathField.setAccessibilityLabel("Where")
        upButton.target = self
        upButton.action = Selector(("goUp:"))
        upButton.setAccessibilityLabel("Enclosing folder")
        let name = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        name.title = "Name"
        name.width = 300
        let date = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("modified"))
        date.title = "Date Modified"
        date.width = 150
        let size = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        size.title = "Size"
        size.width = 80
        table.addTableColumn(name)
        table.addTableColumn(date)
        table.addTableColumn(size)
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 20
        table.usesAlternatingRowBackgroundColors = true
        table.allowsEmptySelection = true
        table.target = self
        table.doubleAction = Selector(("rowActivated:"))
        table.setAccessibilityLabel("Files")
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table
        typePopUp.target = self
        typePopUp.action = Selector(("typeChanged:"))
        typePopUp.setAccessibilityLabel("File Format")
        newFolderButton.target = self
        newFolderButton.action = Selector(("newFolder:"))
        cancelButton.target = self
        cancelButton.action = Selector(("cancel:"))
        cancelButton.keyEquivalent = "\u{1b}"
        okButton.target = self
        okButton.action = Selector(("confirm:"))
        okButton.keyEquivalent = "\r"
        for v in [messageLabel, nameLabel, nameField, whereLabel, pathField, upButton, scroll, typeLabel, typePopUp, newFolderButton, cancelButton, okButton] {
            content.addSubview(v)
        }
        // Tab order follows the window's recalculated key-view loop (view order).
        panel.initialFirstResponder = isOpenPanel ? table : nameField
    }

    /// Places the views for the panel's current size and options.
    func layout() {
        guard built, let content = panel.contentView else { return }
        let bounds = content.bounds
        let margin: CGFloat = 20
        let width = bounds.width - 2 * margin
        var top = bounds.maxY - margin

        if panel.title.isEmpty { panel.title = isOpenPanel ? "Open" : "Save" }
        let message = panel._message ?? ""
        messageLabel.isHidden = message.isEmpty
        if !message.isEmpty {
            messageLabel.stringValue = message
            messageLabel.sizeToFit()
            messageLabel.frame = NSRect(x: margin, y: top - messageLabel.frame.height, width: width, height: messageLabel.frame.height)
            top -= messageLabel.frame.height + 10
        }

        let labelWidth: CGFloat = 80
        nameLabel.isHidden = isOpenPanel
        nameField.isHidden = isOpenPanel
        if !isOpenPanel {
            nameLabel.stringValue = panel._nameFieldLabel ?? "Save As:"
            nameLabel.sizeToFit()
            nameLabel.frame = NSRect(x: margin, y: top - 22, width: labelWidth, height: 22)
            nameField.frame = NSRect(x: margin + labelWidth + 8, y: top - 22, width: width - labelWidth - 8, height: 22)
            top -= 22 + 10
        }

        whereLabel.frame = NSRect(x: margin, y: top - 22, width: labelWidth, height: 22)
        upButton.frame = NSRect(x: bounds.maxX - margin - 60, y: top - 24, width: 60, height: 24)
        pathField.frame = NSRect(x: margin + labelWidth + 8, y: top - 22, width: width - labelWidth - 8 - 68, height: 22)
        top -= 22 + 10

        // Bottom row(s), built upwards.
        var bottom = bounds.minY + margin
        okButton.title = panel._prompt ?? (isOpenPanel ? "Open" : "Save")
        okButton.sizeToFit()
        cancelButton.sizeToFit()
        let buttonWidth = max(84, max(okButton.frame.width, cancelButton.frame.width) + 24)
        okButton.frame = NSRect(x: bounds.maxX - margin - buttonWidth, y: bottom, width: buttonWidth, height: 28)
        cancelButton.frame = NSRect(x: okButton.frame.minX - 12 - buttonWidth, y: bottom, width: buttonWidth, height: 28)
        newFolderButton.isHidden = !panel._canCreateDirectories
        newFolderButton.sizeToFit()
        newFolderButton.frame = NSRect(x: margin, y: bottom, width: newFolderButton.frame.width + 24, height: 28)
        bottom += 28 + 12

        let showsTypes = panel._showsContentTypes && !panel._allowedExtensions.isEmpty
        typeLabel.isHidden = !showsTypes
        typePopUp.isHidden = !showsTypes
        if showsTypes {
            typeLabel.stringValue = isOpenPanel ? "Show:" : "File Format:"
            typeLabel.sizeToFit()
            typeLabel.frame = NSRect(x: margin, y: bottom, width: labelWidth, height: 24)
            typePopUp.frame = NSRect(x: margin + labelWidth + 8, y: bottom, width: min(280, width - labelWidth - 8), height: 24)
            bottom += 24 + 10
        }

        if let accessory = panel._accessoryView {
            if accessoryContainer !== accessory {
                accessoryContainer?.removeFromSuperview()
                content.addSubview(accessory)
                accessoryContainer = accessory
            }
            let h = accessory.frame.height
            accessory.frame = NSRect(x: margin + max(0, (width - accessory.frame.width) / 2), y: bottom, width: min(width, accessory.frame.width), height: h)
            bottom += h + 10
        } else if let old = accessoryContainer {
            old.removeFromSuperview()
            accessoryContainer = nil
        }

        scroll.frame = NSRect(x: margin, y: bottom, width: width, height: max(60, top - bottom))
        table.sizeLastColumnToFit()
        table.tile()
    }

    func layoutIfBuilt() { if built { layout() } }
    func reloadIfBuilt() {
        guard built else { return }
        reloadTypes()
        load(panel._directoryURL ?? directory)
    }

    var nameFieldValueIfBuilt: String? {
        guard built, !isOpenPanel else { return nil }
        return nameField.stringValue
    }
    func setNameFieldIfBuilt(_ value: String) { if built { nameField.stringValue = value } }

    // MARK: Types

    private var typeChoices: [(label: String, extensions: [String], type: UTType?)] = []
    private var selectedType: (label: String, extensions: [String], type: UTType?)? {
        let i = typePopUp.indexOfSelectedItem
        return i >= 0 && i < typeChoices.count ? typeChoices[i] : nil
    }

    private func reloadTypes() {
        typeChoices = []
        for type in panel._allowedContentTypes {
            let exts = (type.tags[.filenameExtension] ?? []).map { $0.lowercased() }
            let label = panel._panelDelegate?.panel(panel, displayNameFor: type) ?? panel._typeDisplayNames[type.identifier] ?? type.localizedDescription ?? (exts.first?.uppercased() ?? type.identifier)
            typeChoices.append((label, exts, type))
        }
        for ext in panel._allowedFileTypes ?? [] where !typeChoices.contains(where: { $0.extensions.contains(ext.lowercased()) }) {
            typeChoices.append((ext.uppercased(), [ext.lowercased()], nil))
        }
        if panel._allowsOtherFileTypes && !typeChoices.isEmpty { typeChoices.append(("All Files", [], nil)) }
        typePopUp.removeAllItems()
        for c in typeChoices { typePopUp.addItem(withTitle: c.label) }
        if let current = panel._currentContentType, let i = typeChoices.firstIndex(where: { $0.type == current }) { typePopUp.selectItem(at: i) }
        else if !typeChoices.isEmpty { typePopUp.selectItem(at: 0) }
    }

    /// The extensions the listing shows: the chosen type's, or every allowed one.
    private var visibleExtensions: [String] {
        if let s = selectedType { return s.extensions.isEmpty ? [] : s.extensions }
        return panel._allowedExtensions
    }

    // MARK: Listing

    func load(_ url: URL) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            NSSound.beep()
            return
        }
        let changed = url.standardizedFileURL.path != directory.standardizedFileURL.path
        directory = url
        panel._directoryURL = url
        pathField.stringValue = url.path
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey, .isHiddenKey]
        var options: FileManager.DirectoryEnumerationOptions = []
        if !panel._showsHiddenFiles { options.insert(.skipsHiddenFiles) }
        let children = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options)) ?? []
        let exts = visibleExtensions
        let openOnly = isOpenPanel
        let delegate = panel._panelDelegate
        entries = children.compactMap { child -> Entry? in
            let values = try? child.resourceValues(forKeys: Set(keys))
            let name = child.lastPathComponent
            if !panel._showsHiddenFiles, name.hasPrefix(".") || values?.isHidden == true { return nil }
            let isDirectory = values?.isDirectory ?? false
            var enabled = true
            if !isDirectory {
                if !exts.isEmpty, !exts.contains(child.pathExtension.lowercased()) { enabled = false }
                if openOnly, let o = openPanel, !o._canChooseFiles { enabled = false }
            }
            if enabled, let d = delegate, !d.panel(panel, shouldEnable: child) { enabled = false }
            return Entry(url: child, name: name, isDirectory: isDirectory, modified: values?.contentModificationDate, size: isDirectory ? nil : values?.fileSize, isEnabled: enabled)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        table.reloadData()
        table.deselectAll(nil)
        if changed { delegate?.panel(panel, didChangeToDirectoryURL: url) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row < entries.count else { return nil }
        let e = entries[row]
        switch tableColumn?.identifier.rawValue {
        case "modified": return e.modified.map { Self.dateFormatter.string(from: $0) } ?? ""
        case "size": return e.size.map { Self.formatSize($0) } ?? (e.isDirectory ? "--" : "")
        default: return e.isDirectory ? e.name + "/" : e.name
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < entries.count, !entries[row].isEnabled else { return nil }
        // Dimmed label for items the filter or the delegate rules out.
        let text = (self.tableView(tableView, objectValueFor: tableColumn, row: row) as? String) ?? ""
        let label = NSTextField(labelWithString: text)
        label.textColor = NSColor.tertiaryLabelColor
        return label
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { row < entries.count && entries[row].isEnabled }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if !isOpenPanel, table.selectedRow >= 0, table.selectedRow < entries.count, !entries[table.selectedRow].isDirectory {
            let name = entries[table.selectedRow].name
            nameField.stringValue = panel._isExtensionHidden ? Self.hidingExtension(name) : name
        }
        panel._panelDelegate?.panelSelectionDidChange(panel)
    }

    private static func formatSize(_ bytes: Int) -> String {
        let units = ["bytes", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var i = 0
        while value >= 1000 && i < units.count - 1 { value /= 1000; i += 1 }
        return i == 0 ? "\(bytes) bytes" : String(format: "%.1f %@", value, units[i])
    }

    static func hidingExtension(_ name: String) -> String {
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? name : (name as NSString).deletingPathExtension
    }

    // MARK: Actions

    func respondsToSelectorAction(_ action: Selector) -> Bool {
        ["confirm:", "cancel:", "goUp:", "pathEntered:", "rowActivated:", "typeChanged:", "newFolder:"].contains(NSStringFromSelector(action))
    }

    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch NSStringFromSelector(action) {
        case "confirm:": confirm()
        case "cancel:": panel.cancel(sender)
        case "goUp:": goUp()
        case "pathEntered:": pathEntered()
        case "rowActivated:": rowActivated()
        case "typeChanged:": typeChanged()
        case "newFolder:": newFolder()
        default: return false
        }
        return true
    }

    func goUp() {
        let parent = directory.deletingLastPathComponent()
        guard parent.path != directory.path else { return }
        let previous = directory
        load(parent)
        if let i = entries.firstIndex(where: { $0.url.lastPathComponent == previous.lastPathComponent }) {
            table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
            table.scrollRowToVisible(i)
        }
    }

    private func pathEntered() {
        let typed = (pathField.stringValue as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: typed, isDirectory: &isDir) {
            if isDir.boolValue { load(URL(fileURLWithPath: typed)); return }
            // A file: go to its folder and select it.
            let url = URL(fileURLWithPath: typed)
            load(url.deletingLastPathComponent())
            if let i = entries.firstIndex(where: { $0.url.lastPathComponent == url.lastPathComponent }), entries[i].isEnabled {
                table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
                if !isOpenPanel { nameField.stringValue = url.lastPathComponent }
            }
            return
        }
        NSSound.beep()
        pathField.stringValue = directory.path
    }

    /// Return or a double click on a row: a folder is entered (as on macOS, even when
    /// folders may be chosen), a file confirms.
    private func rowActivated() {
        let row = table.selectedRow
        guard row >= 0, row < entries.count else { return }
        let e = entries[row]
        if e.isDirectory { load(e.url); return }
        confirm()
    }

    private func typeChanged() {
        panel._currentContentType = selectedType?.type
        panel._panelDelegate?.panel(panel, didSelect: selectedType?.type)
        load(directory)
        // A save panel swaps the name's extension to the chosen type's.
        if !isOpenPanel, let ext = selectedType?.extensions.first, !panel._isExtensionHidden {
            let base = (nameField.stringValue as NSString).deletingPathExtension
            if !base.isEmpty { nameField.stringValue = base + "." + ext }
        }
    }

    private func newFolder() {
        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.informativeText = "Name of new folder inside \u{201c}\(directory.lastPathComponent)\u{201d}:"
        let field = NSTextField(string: "untitled folder")
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 22)
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        createFolder(named: field.stringValue)
    }

    /// Creates `name` inside the current directory and enters it (New Folder's work).
    func createFolder(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains("/") else { NSSound.beep(); return }
        let url = directory.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            _ = NSAlert(error: error).runModal()
            return
        }
        load(url)
    }

    /// The name the user typed, through the delegate, with the type's extension added
    /// when it has none (or a hidden one).
    private func resolvedSaveName(confirmed: Bool) -> String? {
        var name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        if let d = panel._panelDelegate {
            guard let replaced = d.panel(panel, userEnteredFilename: name, confirmed: confirmed) else { return nil }
            name = replaced
        }
        guard !name.isEmpty else { return nil }
        let allowed = panel._allowedExtensions
        let ext = (name as NSString).pathExtension.lowercased()
        if !allowed.isEmpty {
            let preferred = selectedType?.extensions.first ?? allowed[0]
            if ext.isEmpty || panel._isExtensionHidden && !allowed.contains(ext) {
                name += "." + preferred
            } else if !allowed.contains(ext) && !panel._allowsOtherFileTypes {
                name += "." + preferred
            }
        }
        return name
    }

    /// OK: a save panel takes the typed name in the current directory (entering a folder
    /// of that name instead, and asking before replacing a file); an open panel takes the
    /// selected rows, or the directory itself when directories may be chosen.
    func confirm() {
        let fm = FileManager.default
        if isOpenPanel, let open = openPanel {
            let rows = table.selectedRowIndexes.filter { $0 < entries.count }.map { entries[$0] }
            if rows.count == 1, rows[0].isDirectory, !open._canChooseDirectories {
                load(rows[0].url)
                return
            }
            var chosen = rows.filter { $0.isEnabled && ($0.isDirectory ? open._canChooseDirectories : open._canChooseFiles) }.map { $0.url }
            if chosen.isEmpty {
                guard open._canChooseDirectories else { NSSound.beep(); return }
                chosen = [directory]
            }
            if chosen.count > 1 && !open._allowsMultipleSelection { chosen = [chosen[0]] }
            if let d = panel._panelDelegate {
                for url in chosen {
                    do { try d.panel(panel, validate: url) } catch { _ = NSAlert(error: error).runModal(); return }
                }
            }
            panel._accept(chosen)
            panel._finish(.OK)
            return
        }
        guard let name = resolvedSaveName(confirmed: true) else { NSSound.beep(); return }
        let url = name.hasPrefix("/") ? URL(fileURLWithPath: name) : directory.appendingPathComponent(name)
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue { load(url); return }
            let alert = NSAlert()
            alert.messageText = "\u{201c}\(url.lastPathComponent)\u{201d} already exists. Do you want to replace it?"
            alert.informativeText = "A file or folder with the same name already exists in the folder \(url.deletingLastPathComponent().lastPathComponent). Replacing it will overwrite its current contents."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        if let d = panel._panelDelegate {
            do { try d.panel(panel, validate: url) } catch { _ = NSAlert(error: error).runModal(); return }
        }
        panel._accept([url])
        panel._finish(.OK)
    }
}
