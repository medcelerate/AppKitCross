// NSWindowController (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller
@MainActor open class NSWindowController: NSResponder, NSSeguePerforming {
    // MARK: Storage
    private var _window: NSWindow? = nil
    private var _windowLoaded = false
    private var _document: AnyObject? = nil
    private var _owner: AnyObject? = nil
    private var _shouldCascadeWindows = true
    private var _shouldCloseDocument = false
    private var _autosaveName: NSWindow.FrameAutosaveName = ""
    private var _windowNibName: NSNib.Name? = nil
    private var _windowNibPath: String? = nil
    private var _pendingContentViewController: NSViewController? = nil

    @MainActor public convenience override init() { self.init(window: nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/init(coder:)
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/init(window:)
    @MainActor public init(window: NSWindow?) {
        _window = window
        _windowLoaded = window != nil
        super.init()
        window?.windowController = self
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/init(windownibname:)
    @MainActor public convenience init(windowNibName: NSNib.Name) {
        self.init(window: nil)
        _windowNibName = windowNibName
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/init(windownibname:owner:)
    @MainActor public convenience init(windowNibName: NSNib.Name, owner: Any) {
        self.init(window: nil)
        _windowNibName = windowNibName
        _owner = owner as AnyObject
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/init(windownibpath:owner:)
    @MainActor public convenience init(windowNibPath: String, owner: Any) {
        self.init(window: nil)
        _windowNibPath = windowNibPath
        _owner = owner as AnyObject
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/close()
    @MainActor open func close() { _window?.close() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/contentviewcontroller
    @available(macOS 10.10, *)
    @MainActor open var contentViewController: NSViewController? {
        get { _window?.contentViewController ?? _pendingContentViewController }
        set {
            if let w = _window { w.contentViewController = newValue } else { _pendingContentViewController = newValue }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/dismisscontroller(_:)
    @available(macOS 10.10, *)
    @MainActor open func dismissController(_ sender: Any?) { close() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/document
    @MainActor open var document: AnyObject? {
        get { _document }
        set { _document = newValue; synchronizeWindowTitleWithDocumentName() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/iswindowloaded
    @MainActor open var isWindowLoaded: Bool { _windowLoaded }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/loadwindow()
    /// Without nibs, the window comes from the content view controller or is a plain
    /// 480x270 titled window.
    @MainActor open func loadWindow() {
        guard _window == nil else { return }
        let w: NSWindow
        if let vc = _pendingContentViewController {
            w = NSWindow(contentViewController: vc)
            _pendingContentViewController = nil
        } else {
            w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 270), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        }
        w.windowController = self
        _window = w
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/owner
    @MainActor open var owner: AnyObject? { _owner ?? self }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/previewrepresentableactivityitems
    @available(macOS 13.2, *)
    @MainActor open var previewRepresentableActivityItems: [any NSPreviewRepresentableActivityItem]? {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/setdocumentedited(_:)
    @MainActor open func setDocumentEdited(_ dirtyFlag: Bool) { window?.isDocumentEdited = dirtyFlag }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/shouldcascadewindows
    @MainActor open var shouldCascadeWindows: Bool {
        get { _shouldCascadeWindows }
        set { _shouldCascadeWindows = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/shouldclosedocument
    @MainActor open var shouldCloseDocument: Bool {
        get { _shouldCloseDocument }
        set { _shouldCloseDocument = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/showwindow(_:)
    @MainActor open func showWindow(_ sender: Any?) { window?.makeKeyAndOrderFront(sender) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/storyboard
    @available(macOS 10.10, *)
    @MainActor open var storyboard: NSStoryboard? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/synchronizewindowtitlewithdocumentname()
    @MainActor open func synchronizeWindowTitleWithDocumentName() {
        // NSDocument is not implemented yet, so there is no display name to take.
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/window
    @MainActor open var window: NSWindow? {
        get {
            if !_windowLoaded {
                _windowLoaded = true
                windowWillLoad()
                loadWindow()
                windowDidLoad()
            }
            return _window
        }
        set {
            _window?.windowController = nil
            _window = newValue
            _windowLoaded = newValue != nil
            newValue?.windowController = self
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/windowdidload()
    @MainActor open func windowDidLoad() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/windowframeautosavename
    @MainActor open var windowFrameAutosaveName: NSWindow.FrameAutosaveName {
        get { _autosaveName }
        set { _autosaveName = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/windownibname
    @MainActor open var windowNibName: NSNib.Name? { _windowNibName }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/windownibpath
    @MainActor open var windowNibPath: String? { _windowNibPath }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/windowtitle(fordocumentdisplayname:)
    @MainActor open func windowTitle(forDocumentDisplayName displayName: String) -> String { displayName }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindowcontroller/windowwillload()
    @MainActor open func windowWillLoad() { }
}
