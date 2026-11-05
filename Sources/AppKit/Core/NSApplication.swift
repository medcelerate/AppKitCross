// NSApplication (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication
@MainActor open class NSApplication: NSResponder, PlatformMenuHost, NSUserInterfaceValidations, NSMenuItemValidation, NSAccessibilityElementProtocol, NSAccessibilityProtocol, NSAppearanceCustomization {
    @MainActor public override init() {
        super.init()
        _CoreAnimationHost.installIfNeeded()
        if NSApplication._shared == nil { NSApplication._shared = self }
    }

    @MainActor public required init?(coder: NSCoder) { super.init(coder: coder) }
    // MARK: Storage
    internal static var _shared: NSApplication?
    private weak var _delegate: (any NSApplicationDelegate)?
    private var _windows: [NSWindow] = []
    private var _isRunning = false
    private var _isActive = false
    private var _accessibilityLabel: String? = nil
    private var _isHidden = false
    private var _finishedLaunching = false
    private var _currentEvent: NSEvent? = nil
    private var _eventQueue: [NSEvent] = []
    private var _nextWindowNumber = 1
    private var _activationPolicy: NSApplication.ActivationPolicy = .regular
    private var _presentationOptions: NSApplication.PresentationOptions = []
    private var _mainMenu: NSMenu? = nil
    private var _helpMenu: NSMenu? = nil
    private var _windowsMenu: NSMenu? = nil
    private var _servicesMenu: NSMenu? = nil
    private var _servicesProvider: Any? = nil
    private var _applicationIconImage: NSImage? = nil
    private var _appearance: NSAppearance? = nil
    internal final class _ModalSession {
        let window: NSWindow
        var response: NSApplication.ModalResponse? = nil
        init(window: NSWindow) { self.window = window }
    }
    private var _modalStack: [_ModalSession] = []

    internal weak var _keyWindow: NSWindow?
    internal weak var _mainWindow: NSWindow?

    internal func _allocateWindowNumber() -> Int {
        defer { _nextWindowNumber += 1 }
        return _nextWindowNumber
    }

    internal func _register(window: NSWindow) {
        if !_windows.contains(where: { $0 === window }) { _windows.append(window) }
    }

    internal func _unregister(window: NSWindow) {
        _windows.removeAll { $0 === window }
        if _keyWindow === window { _keyWindow = nil }
        if _mainWindow === window { _mainWindow = nil }
        if _windows.isEmpty, _isRunning, delegate?.applicationShouldTerminateAfterLastWindowClosed(self) == true {
            terminate(nil)
        }
    }

    private func post(_ name: NSNotification.Name) -> Notification {
        let n = Notification(name: name, object: self)
        NotificationCenter.default.post(n)
        return n
    }

    private func _terminateNow() -> Never {
        _ = post(NSApplication.willTerminateNotification)
        delegate?.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification, object: self))
        Platform.backend.stop()
        exit(0)
    }

    private func _drainEventQueue() {
        while !_eventQueue.isEmpty {
            let e = _eventQueue.removeFirst()
            sendEvent(e)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/abortmodal()
    @MainActor open func abortModal() { stopModal(withCode: .abort) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/activate()
    @available(macOS 14.0, *)
    @MainActor open func activate() { activate(ignoringOtherApps: false) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/activate(ignoringotherapps:)
    @MainActor open func activate(ignoringOtherApps ignoreOtherApps: Bool) {
        guard !_isActive else { return }
        delegate?.applicationWillBecomeActive(post(NSApplication.willBecomeActiveNotification))
        _isActive = true
        delegate?.applicationDidBecomeActive(post(NSApplication.didBecomeActiveNotification))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/activatecontexthelpmode(_:)
    @MainActor open func activateContextHelpMode(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy()
    @MainActor open func activationPolicy() -> NSApplication.ActivationPolicy { _activationPolicy }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/addwindowsitem(_:title:filename:)
    @MainActor open func addWindowsItem(_ win: NSWindow, title string: String, filename isFilename: Bool) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/appearance
    @available(macOS 10.14, *)
    @MainActor open var appearance: NSAppearance? {
        get { _appearance }
        set { _appearance = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/applicationiconimage
    @MainActor open var applicationIconImage: NSImage! {
        get { _applicationIconImage }
        set { _applicationIconImage = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/applicationshouldsuppresshighdynamicrangecontent
    @available(macOS 26.0, *)
    @MainActor open var applicationShouldSuppressHighDynamicRangeContent: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/arrangeinfront(_:)
    @MainActor open func arrangeInFront(_ sender: Any?) { for w in _windows where w.isVisible { w.orderFront(nil) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/beginmodalsession(for:)
    @MainActor open func beginModalSession(for window: NSWindow) -> NSApplication.ModalSession {
        let session = _ModalSession(window: window)
        _modalStack.append(session)
        window.makeKeyAndOrderFront(nil)
        return OpaquePointer(Unmanaged.passUnretained(session).toOpaque())
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/beginsheet(_:modalfor:modaldelegate:didend:contextinfo:)
    @MainActor open func beginSheet(_ sheet: NSWindow, modalFor docWindow: NSWindow, modalDelegate: Any?, didEnd didEndSelector: Selector?, contextInfo: UnsafeMutableRawPointer!) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/canceluserattentionrequest(_:)
    @MainActor open func cancelUserAttentionRequest(_ request: Int) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/changewindowsitem(_:title:filename:)
    @MainActor open func changeWindowsItem(_ win: NSWindow, title string: String, filename isFilename: Bool) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/completestaterestoration()
    @MainActor open func completeStateRestoration() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/context
    @MainActor open var context: NSGraphicsContext? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/currentevent
    @MainActor open var currentEvent: NSEvent? { _currentEvent }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/currentsystempresentationoptions
    @MainActor open var currentSystemPresentationOptions: NSApplication.PresentationOptions { _presentationOptions }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/deactivate()
    @MainActor open func deactivate() {
        guard _isActive else { return }
        delegate?.applicationWillResignActive(post(NSApplication.willResignActiveNotification))
        _isActive = false
        delegate?.applicationDidResignActive(post(NSApplication.didResignActiveNotification))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/delegate
    @MainActor open var delegate: (any NSApplicationDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/detachdrawingthread(_:totarget:with:)
    @MainActor public class func detachDrawingThread(_ selector: Selector, toTarget target: Any, with argument: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/didbecomeactivenotification
    static public var didBecomeActiveNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSApplicationDidBecomeActiveNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/didchangeocclusionstatenotification
    static public var didChangeOcclusionStateNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSApplicationDidChangeOcclusionStateNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification
    static public var didChangeScreenParametersNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSApplicationDidChangeScreenParametersNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/didfinishlaunchingnotification
    static public var didFinishLaunchingNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSApplicationDidFinishLaunchingNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/didfinishrestoringwindowsnotification
    static public var didFinishRestoringWindowsNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSApplicationDidFinishRestoringWindowsNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/didhidenotification
    static public var didHideNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSApplicationDidHideNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/didresignactivenotification
    static public var didResignActiveNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSApplicationDidResignActiveNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/didunhidenotification
    static public var didUnhideNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSApplicationDidUnhideNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/didupdatenotification
    static public var didUpdateNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSApplicationDidUpdateNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/disablerelaunchonlogin()
    @MainActor open func disableRelaunchOnLogin() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/discardevents(matching:before:)
    @MainActor open func discardEvents(matching mask: NSEvent.EventTypeMask, before lastEvent: NSEvent?) { _eventQueue.removeAll { mask.contains(NSEvent.EventTypeMask(type: $0.type)) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/displaywindowrunloopordering
    class public var displayWindowRunLoopOrdering: Int { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/docktile
    @MainActor open var dockTile: NSDockTile { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/effectiveappearance
    @available(macOS 10.14, *)
    @MainActor open var effectiveAppearance: NSAppearance { _appearance ?? NSAppearance(named: Platform.backend.systemAppearanceIsDark ? .darkAqua : .aqua)! }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/enablerelaunchonlogin()
    @MainActor open func enableRelaunchOnLogin() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/enabledremotenotificationtypes
    @MainActor open var enabledRemoteNotificationTypes: NSApplication.RemoteNotificationType { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/endmodalsession(_:)
    @MainActor open func endModalSession(_ session: NSApplication.ModalSession) {
        if !_modalStack.isEmpty { _modalStack.removeLast() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/endsheet(_:)
    @MainActor open func endSheet(_ sheet: NSWindow) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/endsheet(_:returncode:)
    @MainActor open func endSheet(_ sheet: NSWindow, returnCode: Int) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/enumeratewindows(options:using:)
    @available(macOS 10.12, *)
    @MainActor open func enumerateWindows(options: NSApplication.WindowListOptions = [], using block: (NSWindow, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop = ObjCBool(false)
        for w in _windows {
            block(w, &stop)
            if stop.boolValue { break }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/extendstaterestoration()
    @MainActor open func extendStateRestoration() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/finishlaunching()
    @MainActor open func finishLaunching() {
        guard !_finishedLaunching else { return }
        delegate?.applicationWillFinishLaunching(post(NSApplication.willFinishLaunchingNotification))
        _finishedLaunching = true
        activate(ignoringOtherApps: true)
        delegate?.applicationDidFinishLaunching(post(NSApplication.didFinishLaunchingNotification))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/helpmenu
    @MainActor open var helpMenu: NSMenu? {
        get { _helpMenu }
        set { _helpMenu = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/hide(_:)
    @MainActor open func hide(_ sender: Any?) {
        guard !_isHidden else { return }
        delegate?.applicationWillHide(post(NSApplication.willHideNotification))
        _isHidden = true
        for w in _windows where w.isVisible && w.canHide { w.orderOut(nil) }
        delegate?.applicationDidHide(post(NSApplication.didHideNotification))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/hideotherapplications(_:)
    @MainActor open func hideOtherApplications(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/isactive
    @MainActor open var isActive: Bool { _isActive }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/isautomaticcustomizetouchbarmenuitemenabled
    @available(macOS 10.12, *)
    @MainActor open var isAutomaticCustomizeTouchBarMenuItemEnabled: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/isfullkeyboardaccessenabled
    @MainActor open var isFullKeyboardAccessEnabled: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/ishidden
    @MainActor open var isHidden: Bool { _isHidden }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/isprotecteddataavailable
    @available(macOS 12.0, *)
    @MainActor open var isProtectedDataAvailable: Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/isregisteredforremotenotifications
    @available(macOS 10.14, *)
    @MainActor open var isRegisteredForRemoteNotifications: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/isrunning
    @MainActor open var isRunning: Bool { _isRunning }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/keywindow
    @MainActor open var keyWindow: NSWindow? { _keyWindow }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/launchisdefaultuserinfokey
    static public var launchIsDefaultUserInfoKey: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/launchusernotificationuserinfokey
    static public var launchUserNotificationUserInfoKey: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/loadapplication()
    @MainActor public static func loadApplication() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/mainmenu
    @MainActor open var mainMenu: NSMenu? {
        get { _mainMenu }
        set {
            _mainMenu = newValue
            _mainMenuDidChange()
        }
    }

    private var _menuRebuildSuppressed = false

    /// Rebuilds the platform menu bar from the main menu tree.
    @MainActor internal func _mainMenuDidChange() {
        guard !_menuRebuildSuppressed else { return }
        Platform.backend.setMainMenu(_mainMenu?._platformMenu(), host: self)
    }

    /// Runs `body` without rebuilding the native menu bar for item changes it makes
    /// (the native side refreshes states in place while a menu is open).
    @MainActor private func _withoutMenuRebuild<T>(_ body: () -> T) -> T {
        let saved = _menuRebuildSuppressed
        _menuRebuildSuppressed = true
        defer { _menuRebuildSuppressed = saved }
        return body()
    }

    /// The object that would receive `action` for a nil target (responder chain from the
    /// key window's first responder, then the application, then its delegate).
    @MainActor internal func _target(forAction action: Selector) -> AnyObject? {
        var r: NSResponder? = keyWindow?.firstResponder
        while let cur = r {
            if ActionRegistry.canPerform(action, on: cur) { return cur }
            r = cur.nextResponder
        }
        if ActionRegistry.canPerform(action, on: self) { return self }
        if let d = delegate, ActionRegistry.canPerform(action, on: d) { return d }
        return nil
    }

    // MARK: PlatformMenuHost

    public func platformMenuWillOpen(_ menuID: Int) -> PlatformMenu? {
        guard let menu = _mainMenu?._menu(withID: menuID) else { return nil }
        _withoutMenuRebuild { menu.update() }
        return menu._platformMenu()
    }

    public func platformMenuItemSelected(_ itemID: Int) {
        guard let item = _mainMenu?._item(withCommandID: itemID), let menu = item.menu else { return }
        _withoutMenuRebuild { menu.update() }
        menu.performActionForItem(at: menu.index(of: item))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/mainwindow
    @MainActor open var mainWindow: NSWindow? { _mainWindow }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/makewindowsperform(_:inorder:)
    @MainActor open func makeWindowsPerform(_ selector: Selector, inOrder: Bool) -> NSWindow? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/miniaturizeall(_:)
    @MainActor open func miniaturizeAll(_ sender: Any?) { for w in _windows where w.isVisible { w.miniaturize(nil) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/modalwindow
    @MainActor open var modalWindow: NSWindow? { _modalStack.last?.window }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/nextevent(matching:until:inmode:dequeue:)
    @MainActor open func nextEvent(matching mask: NSEvent.EventTypeMask, until expiration: Date?, inMode mode: RunLoop.Mode, dequeue deqFlag: Bool) -> NSEvent? {
        // Only the posted-event queue is consulted; the native queue is pumped by run().
        guard let i = _eventQueue.firstIndex(where: { mask.contains(NSEvent.EventTypeMask(type: $0.type)) }) else { return nil }
        let e = _eventQueue[i]
        if deqFlag { _eventQueue.remove(at: i) }
        return e
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/occlusionstate
    @MainActor open var occlusionState: NSApplication.OcclusionState { .visible }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/orderfrontcharacterpalette(_:)
    @MainActor open func orderFrontCharacterPalette(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/orderfrontcolorpanel(_:)
    @MainActor open func orderFrontColorPanel(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/orderfrontstandardaboutpanel(_:)
    @MainActor open func orderFrontStandardAboutPanel(_ sender: Any?) { orderFrontStandardAboutPanel(options: [:]) }
    /// The standard about panel: the application's name and version (from the bundle, or
    /// the options) in an alert.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/orderfrontstandardaboutpanel(options:)
    @MainActor open func orderFrontStandardAboutPanel(options optionsDictionary: [NSApplication.AboutPanelOptionKey : Any] = [:]) {
        let info = Bundle.main.infoDictionary ?? [:]
        let name = (optionsDictionary[NSApplication.AboutPanelOptionKey(rawValue: "ApplicationName")] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? ((CommandLine.arguments.first ?? "App") as NSString).lastPathComponent
        let version = (optionsDictionary[NSApplication.AboutPanelOptionKey(rawValue: "ApplicationVersion")] as? String) ?? (info["CFBundleShortVersionString"] as? String) ?? ""
        let alert = NSAlert()
        alert.messageText = name
        alert.informativeText = version.isEmpty ? "" : "Version \(version)"
        _ = alert.runModal()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/ordereddocuments
    @MainActor open var orderedDocuments: [NSDocument] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/orderedwindows
    @MainActor open var orderedWindows: [NSWindow] { _windows.filter { $0.isVisible } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/postevent(_:atstart:)
    @MainActor open func postEvent(_ event: NSEvent, atStart: Bool) {
        if atStart { _eventQueue.insert(event, at: 0) } else { _eventQueue.append(event) }
        Platform.backend.post { [weak self] in self?._drainEventQueue() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/presentationoptions
    @MainActor open var presentationOptions: NSApplication.PresentationOptions {
        get { _presentationOptions }
        set { _presentationOptions = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/preventwindowordering()
    @MainActor open func preventWindowOrdering() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/registerforremotenotifications()
    @available(macOS 10.14, *)
    @MainActor open func registerForRemoteNotifications() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/registerforremotenotifications(matching:)
    @MainActor open func registerForRemoteNotifications(matching types: NSApplication.RemoteNotificationType) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/registerservicesmenusendtypes(_:returntypes:)
    @MainActor open func registerServicesMenuSendTypes(_ sendTypes: [NSPasteboard.PasteboardType], returnTypes: [NSPasteboard.PasteboardType]) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/registeruserinterfaceitemsearchhandler(_:)
    @MainActor open func registerUserInterfaceItemSearchHandler(_ handler: any NSUserInterfaceItemSearching) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/removewindowsitem(_:)
    @MainActor open func removeWindowsItem(_ win: NSWindow) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/reply(toapplicationshouldterminate:)
    @MainActor open func reply(toApplicationShouldTerminate shouldTerminate: Bool) { if shouldTerminate { _terminateNow() } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/reply(toopenorprint:)
    @MainActor open func reply(toOpenOrPrint reply: NSApplication.DelegateReply) { unimplemented() }
    // SKIPPED (Foundation.NSException not in corelibs): @MainActor func reportException(_ exception: NSException)
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/requestuserattention(_:)
    @MainActor open func requestUserAttention(_ requestType: NSApplication.RequestUserAttentionType) -> Int { 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/resetcursorrectsrunloopordering
    class public var resetCursorRectsRunLoopOrdering: Int { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/restorewindow(withidentifier:state:completionhandler:)
    @MainActor open func restoreWindow(withIdentifier identifier: NSUserInterfaceItemIdentifier, state: NSCoder, completionHandler: @escaping (NSWindow?, (any Error)?) -> Void) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/run()
    @MainActor open func run() {
        if !_finishedLaunching { finishLaunching() }
        _isRunning = true
        Platform.backend.run()
        _isRunning = false
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/runmodal(for:)
    @MainActor open func runModal(for window: NSWindow) -> NSApplication.ModalResponse {
        let session = beginModalSession(for: window)
        defer { endModalSession(session) }
        Platform.backend.runModal(for: window._platformWindow) { [weak self] in
            guard let self else { return true }
            return self._modalStack.last?.response != nil || !window.isVisible
        }
        return _modalStack.last?.response ?? .abort
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/runmodalsession(_:)
    @MainActor open func runModalSession(_ session: NSApplication.ModalSession) -> NSApplication.ModalResponse {
        guard let s = _modalStack.last else { return .abort }
        return s.response ?? .continue
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/runpagelayout(_:)
    @MainActor open func runPageLayout(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/searchstring(_:inuserinterfaceitemstring:range:found:)
    @MainActor open func searchString(_ searchString: String, inUserInterfaceItemString stringToSearch: String, range searchRange: NSRange, found foundRange: UnsafeMutablePointer<NSRange>?) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/sendaction(_:to:from:)
    @MainActor open func sendAction(_ action: Selector, to target: Any?, from sender: Any?) -> Bool {
        // See TargetAction.swift: explicit targets get the action directly; nil walks the
        // responder chain from the key window's first responder, then the main window's,
        // then the application and its delegate.
        if let target {
            return ActionRegistry.perform(action, on: target as AnyObject, with: sender)
        }
        if let key = keyWindow, key.firstResponder?.tryToPerform(action, with: sender) == true { return true }
        if let main = mainWindow, main !== keyWindow, main.firstResponder?.tryToPerform(action, with: sender) == true { return true }
        if tryToPerform(action, with: sender) { return true }
        if let d = delegate { return ActionRegistry.perform(action, on: d, with: sender) }
        return false
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/sendevent(_:)
    @MainActor open func sendEvent(_ event: NSEvent) {
        _currentEvent = event
        // A drag in progress owns the mouse (and Escape) until it drops or cancels.
        if let drag = _NSDragTracker.current {
            switch event.type {
            case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseUp, .rightMouseUp, .otherMouseUp, .flagsChanged, .keyDown, .keyUp:
                drag.handle(event)
                return
            default:
                break
            }
        }
        // An open menu owns the mouse and keyboard until it closes.
        if let tracker = _NSMenuTracker.current {
            switch event.type {
            case .keyDown, .keyUp, .flagsChanged, .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                 .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel:
                tracker.handle(event)
                return
            default:
                break
            }
        }
        // Menu key equivalents take precedence over the key window's handling, as in AppKit.
        if event.type == .keyDown, let menu = _mainMenu, menu.performKeyEquivalent(with: event) { return }
        if let w = event.window { w.sendEvent(event) } else if event.type == .keyDown || event.type == .keyUp || event.type == .flagsChanged {
            keyWindow?.sendEvent(event)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/servicesmenu
    @MainActor open var servicesMenu: NSMenu? {
        get { _servicesMenu }
        set { _servicesMenu = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/servicesprovider
    @MainActor open var servicesProvider: Any? {
        get { _servicesProvider }
        set { _servicesProvider = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/setactivationpolicy(_:)
    @MainActor open func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool { _activationPolicy = activationPolicy; return true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/setwindowsneedupdate(_:)
    @MainActor open func setWindowsNeedUpdate(_ needUpdate: Bool) { if needUpdate { Platform.backend.post { [weak self] in self?.updateWindows() } } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/shared
    @MainActor class public var shared: NSApplication {
        if let s = _shared { return s }
        let app = NSApplication()
        _shared = app
        return app
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/showhelp(_:)
    @MainActor open func showHelp(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/stop(_:)
    @MainActor open func stop(_ sender: Any?) { Platform.backend.stop() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/stopmodal()
    @MainActor open func stopModal() { stopModal(withCode: .stop) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/stopmodal(withcode:)
    @MainActor open func stopModal(withCode returnCode: NSApplication.ModalResponse) { _modalStack.last?.response = returnCode }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/target(foraction:)
    @MainActor open func target(forAction action: Selector) -> Any? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/target(foraction:to:from:)
    @MainActor open func target(forAction action: Selector, to target: Any?, from sender: Any?) -> Any? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/terminate(_:)
    @MainActor open func terminate(_ sender: Any?) {
        let reply = delegate?.applicationShouldTerminate(self) ?? .terminateNow
        switch reply {
        case .terminateCancel: return
        case .terminateLater: return      // the delegate calls reply(toApplicationShouldTerminate:)
        default: _terminateNow()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/toggletouchbarcustomizationpalette(_:)
    @available(macOS 10.12, *)
    @MainActor open func toggleTouchBarCustomizationPalette(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/trytoperform(_:with:)
    @MainActor open override func tryToPerform(_ action: Selector, with object: Any?) -> Bool { super.tryToPerform(action, with: object) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/unhide(_:)
    @MainActor open func unhide(_ sender: Any?) { unhideWithoutActivation(); activate(ignoringOtherApps: true) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/unhideallapplications(_:)
    @MainActor open func unhideAllApplications(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/unhidewithoutactivation()
    @MainActor open func unhideWithoutActivation() {
        guard _isHidden else { return }
        delegate?.applicationWillUnhide(post(NSApplication.willUnhideNotification))
        _isHidden = false
        for w in _windows { w.orderFront(nil) }
        delegate?.applicationDidUnhide(post(NSApplication.didUnhideNotification))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/unregisterforremotenotifications()
    @MainActor open func unregisterForRemoteNotifications() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/unregisteruserinterfaceitemsearchhandler(_:)
    @MainActor open func unregisterUserInterfaceItemSearchHandler(_ handler: any NSUserInterfaceItemSearching) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/updatewindows()
    @MainActor open func updateWindows() {
        _ = post(NSApplication.willUpdateNotification)
        for w in _windows { w.update() }
        _ = post(NSApplication.didUpdateNotification)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/updatewindowsitem(_:)
    @MainActor open func updateWindowsItem(_ win: NSWindow) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/updatewindowsrunloopordering
    class public var updateWindowsRunLoopOrdering: Int { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/userinterfacelayoutdirection
    @MainActor open var userInterfaceLayoutDirection: NSUserInterfaceLayoutDirection { NSApplication._resolvedLayoutDirection }

    /// The application's direction, decided once: `APPKITWIN_LAYOUT_DIRECTION=rtl|ltr`
    /// (demos and tests), then the macOS defaults keys (`AppleTextDirection`,
    /// `NSForceRightToLeftWritingDirection`), then the current locale's language.
    nonisolated(unsafe) internal static var _layoutDirectionOverride: NSUserInterfaceLayoutDirection?
    internal static var _resolvedLayoutDirection: NSUserInterfaceLayoutDirection {
        if let o = _layoutDirectionOverride { return o }
        if let env = ProcessInfo.processInfo.environment["APPKITWIN_LAYOUT_DIRECTION"]?.lowercased() {
            if env == "rtl" || env == "righttoleft" { return .rightToLeft }
            if env == "ltr" || env == "lefttoright" { return .leftToRight }
        }
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "NSForceRightToLeftWritingDirection") != nil, defaults.bool(forKey: "NSForceRightToLeftWritingDirection") { return .rightToLeft }
        if defaults.object(forKey: "AppleTextDirection") != nil { return defaults.bool(forKey: "AppleTextDirection") ? .rightToLeft : .leftToRight }
        return NSApplication._isRightToLeftLanguage(Locale.current.identifier) ? .rightToLeft : .leftToRight
    }
    /// Languages written right to left (the ones ICU marks as such), by locale identifier prefix.
    internal static func _isRightToLeftLanguage(_ identifier: String) -> Bool {
        let code = identifier.split(whereSeparator: { $0 == "_" || $0 == "-" }).first.map(String.init)?.lowercased() ?? ""
        return ["ar", "arc", "ckb", "dv", "fa", "he", "iw", "khw", "ks", "ku", "ps", "sd", "ug", "ur", "yi"].contains(code)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/validrequestor(forsendtype:returntype:)
    @MainActor open override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/willbecomeactivenotification
    static public var willBecomeActiveNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSApplicationWillBecomeActiveNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/willfinishlaunchingnotification
    static public var willFinishLaunchingNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSApplicationWillFinishLaunchingNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/willhidenotification
    static public var willHideNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSApplicationWillHideNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/willresignactivenotification
    static public var willResignActiveNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSApplicationWillResignActiveNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/willterminatenotification
    static public var willTerminateNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSApplicationWillTerminateNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/willunhidenotification
    static public var willUnhideNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSApplicationWillUnhideNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/willupdatenotification
    static public var willUpdateNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSApplicationWillUpdateNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/window(withwindownumber:)
    @MainActor open func window(withWindowNumber windowNum: Int) -> NSWindow? { _windows.first { $0.windowNumber == windowNum } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/windows
    @MainActor open var windows: [NSWindow] { _windows }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/windowsmenu
    @MainActor open var windowsMenu: NSMenu? {
        get { _windowsMenu }
        set { _windowsMenu = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/yieldactivation(to:)
    @available(macOS 14.0, *)
    @MainActor open func yieldActivation(to application: NSRunningApplication) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsapplication/yieldactivation(toapplicationwithbundleidentifier:)
    @available(macOS 14.0, *)
    @MainActor open func yieldActivation(toApplicationWithBundleIdentifier bundleIdentifier: String) { unimplemented() }
    // MARK: Accessibility (ADR-0013)
    //
    // The application is the root of the tree: its children are the windows, its
    // focused window the key window.
    open func accessibilityRole() -> NSAccessibility.Role? { .application }
    open func accessibilityRoleDescription() -> String? { "application" }
    open func accessibilityLabel() -> String? { MainActor.assumeIsolated { _accessibilityLabel } }
    open func setAccessibilityLabel(_ accessibilityLabel: String?) { MainActor.assumeIsolated { _accessibilityLabel = accessibilityLabel } }
    open func accessibilityTitle() -> String? { accessibilityLabel() ?? ProcessInfo.processInfo.processName }
    open func isAccessibilityElement() -> Bool { true }
    /// The union of the windows' frames.
    open func accessibilityFrame() -> NSRect { MainActor.assumeIsolated { _windows.filter(\.isVisible).map(\.frame).reduce(NSRect.null) { $0.union($1) } } }
    open func accessibilityParent() -> Any? { nil }
    open func isAccessibilityFocused() -> Bool { MainActor.assumeIsolated { _isActive } }
    open func isAccessibilityFrontmost() -> Bool { MainActor.assumeIsolated { _isActive } }
    open func setAccessibilityFrontmost(_ accessibilityFrontmost: Bool) { if accessibilityFrontmost { MainActor.assumeIsolated { activate(ignoringOtherApps: true) } } }
    open func accessibilityIdentifier() -> String { Bundle.main.bundleIdentifier ?? "" }
    /// The visible windows, key window first.
    open func accessibilityChildren() -> [Any]? { accessibilityWindows() }
    open func accessibilityVisibleChildren() -> [Any]? { accessibilityWindows() }
    open func accessibilityWindows() -> [Any]? {
        MainActor.assumeIsolated {
            let visible = _windows.filter { $0.isVisible && !$0.isAccessibilityHidden() }
            guard let key = _keyWindow, let i = visible.firstIndex(where: { $0 === key }) else { return visible }
            var ordered = visible
            ordered.remove(at: i)
            return [key] + ordered
        }
    }
    open func accessibilityFocusedWindow() -> Any? { MainActor.assumeIsolated { _keyWindow } }
    open func accessibilityMainWindow() -> Any? { MainActor.assumeIsolated { _mainWindow } }
    /// The focused element of the key window.
    open func accessibilityApplicationFocusedUIElement() -> Any? { MainActor.assumeIsolated { _keyWindow?.accessibilityApplicationFocusedUIElement() ?? _keyWindow } }
    open func accessibilityMenuBar() -> Any? { MainActor.assumeIsolated { mainMenu } }
    open func isAccessibilityHidden() -> Bool { MainActor.assumeIsolated { isHidden } }
    open func isAccessibilityEnabled() -> Bool { true }
    open func accessibilityWindow() -> Any? { nil }
    open func accessibilityTopLevelUIElement() -> Any? { nil }
}
