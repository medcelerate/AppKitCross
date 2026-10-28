// NSSavePanel (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel
@MainActor open class NSSavePanel: NSPanel {
    // MARK: Storage
    internal var _title: String? = nil
    internal var _prompt: String? = nil
    internal var _message: String? = nil
    internal var _nameFieldLabel: String? = nil
    internal var _nameFieldStringValue = ""
    internal var _directoryURL: URL? = nil
    internal var _allowedFileTypes: [String]? = nil
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

    /// Creates a panel. The native dialog is created when run.
    @MainActor public class func savePanel() -> NSSavePanel { NSSavePanel() }

    @MainActor internal func _options() -> PlatformFileDialogOptions {
        var o = PlatformFileDialogOptions()
        o.isSave = !(self is NSOpenPanel)
        o.title = _title
        o.prompt = _prompt
        o.message = _message
        o.directory = _directoryURL
        o.defaultName = _nameFieldStringValue.isEmpty ? nil : _nameFieldStringValue
        o.allowedExtensions = _allowedFileTypes ?? []
        o.allowsOtherTypes = _allowsOtherFileTypes || (_allowedFileTypes ?? []).isEmpty
        o.canCreateDirectories = _canCreateDirectories
        o.showsHiddenFiles = _showsHiddenFiles
        return o
    }

    @MainActor internal func _run(parent: NSWindow?) -> NSApplication.ModalResponse {
        guard let result = Platform.backend.runFileDialog(_options(), parent: parent?._platformWindow) else {
            _urls = []
            return .cancel
        }
        _urls = result
        if let first = result.first { _directoryURL = first.deletingLastPathComponent(); _nameFieldStringValue = first.lastPathComponent }
        return .OK
    }

    @MainActor open func begin(completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) { handler(_run(parent: NSApplication.shared.keyWindow)) }
    @MainActor open func beginSheetModal(for window: NSWindow, completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) { handler(_run(parent: window)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/accessoryview
    @MainActor open var accessoryView: NSView? {
        get { _accessoryView }
        set { _accessoryView = newValue }
    }
    // SKIPPED (UniformTypeIdentifiers.UTType): @MainActor var allowedContentTypes: [UTType] { get set }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/allowedfiletypes
    @MainActor open var allowedFileTypes: [String]? {
        get { _allowedFileTypes }
        set { _allowedFileTypes = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/allowsotherfiletypes
    @MainActor open var allowsOtherFileTypes: Bool {
        get { _allowsOtherFileTypes }
        set { _allowsOtherFileTypes = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/begin()
    @MainActor open func begin() async -> NSApplication.ModalResponse { _run(parent: NSApplication.shared.keyWindow) }
    // DUPLICATE: @MainActor open func begin() async -> NSApplication.ModalResponse
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/beginsheetmodal(for:)
    @MainActor open func beginSheetModal(for window: NSWindow) async -> NSApplication.ModalResponse { _run(parent: window) }
    // DUPLICATE: @MainActor open func beginSheetModal(for window: NSWindow) async -> NSApplication.ModalResponse
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/cancreatedirectories
    @MainActor open var canCreateDirectories: Bool {
        get { _canCreateDirectories }
        set { _canCreateDirectories = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/canselecthiddenextension
    @MainActor open var canSelectHiddenExtension: Bool {
        get { _canSelectHiddenExtension }
        set { _canSelectHiddenExtension = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/cancel(_:)
    @MainActor open func cancel(_ sender: Any?) { _urls = [] }
    // SKIPPED (UniformTypeIdentifiers.UTType): @MainActor var currentContentType: UTType? { get set }
    // SKIPPED (override type (any NSOpenSavePanelDelegate)? differs from superclass (any NSWindowDelegate)?): @MainActor var delegate: (any NSOpenSavePanelDelegate)? { get set }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/directoryurl
    @MainActor open var directoryURL: URL? {
        get { _directoryURL }
        set { _directoryURL = newValue }
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
        set { _message = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/namefieldlabel
    @MainActor open var nameFieldLabel: String! {
        get { _nameFieldLabel }
        set { _nameFieldLabel = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/namefieldstringvalue
    @MainActor open var nameFieldStringValue: String {
        get { _nameFieldStringValue }
        set { _nameFieldStringValue = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/ok(_:)
    @MainActor open func ok(_ sender: Any?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/prompt
    @MainActor open var prompt: String! {
        get { _prompt }
        set { _prompt = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/runmodal()
    @MainActor open func runModal() -> NSApplication.ModalResponse { _run(parent: NSApplication.shared.keyWindow) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/showscontenttypes
    @available(macOS 15.0, *)
    @MainActor open var showsContentTypes: Bool {
        get { _showsContentTypes }
        set { _showsContentTypes = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/showshiddenfiles
    @MainActor open var showsHiddenFiles: Bool {
        get { _showsHiddenFiles }
        set { _showsHiddenFiles = newValue }
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
        set { _treatsFilePackagesAsDirectories = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/url
    @MainActor open var url: URL? { _urls.first }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssavepanel/validatevisiblecolumns()
    @MainActor open func validateVisibleColumns() { }
}
