// NSStatusItem: one icon in the status area. The button holds what is shown; a primary
// click sends the button's action (or opens the menu when one is set, as AppKit does); a
// secondary click opens the menu. Visibility is remembered under the autosave name, as
// AppKit stores it ("NSStatusItem Visible <name>").

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem
open class NSStatusItem: NSObject {
    @MainActor private weak var _statusBar: NSStatusBar?
    @MainActor private var _button: NSStatusBarButton
    @MainActor private var _menu: NSMenu?
    @MainActor private var _length: CGFloat
    @MainActor private var _isVisible = true
    @MainActor private var _behavior: NSStatusItem.Behavior = []
    @MainActor private var _autosaveName: NSStatusItem.AutosaveName?
    @MainActor private var _view: NSView?
    @MainActor private var _highlightMode = true
    @MainActor private var _doubleAction: Selector?
    @MainActor private var _platform: (any PlatformStatusItem)?
    @MainActor private static var _counter = 0
    @MainActor private var _removed = false

    @MainActor internal init(statusBar: NSStatusBar, length: CGFloat) {
        _statusBar = statusBar
        _length = length
        NSStatusItem._counter += 1
        let b = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: length > 0 ? length : 22, height: statusBar.thickness))
        b.title = ""
        b.isBordered = false
        _button = b
        super.init()
        b._statusItem = self
        _platform = Platform.backend.statusItems?.makeStatusItem(owner: self)
        _syncPlatform()
    }

    open override var description: String { MainActor.assumeIsolated { "<NSStatusItem '\(_button.title)' length=\(_length)\(_isVisible ? "" : " hidden")>" } }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/action
    open var action: Selector? {
        get { MainActor.assumeIsolated { _button.action } }
        set { MainActor.assumeIsolated { _button.action = newValue } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/alternateimage
    open var alternateImage: NSImage? {
        get { MainActor.assumeIsolated { _button.alternateImage } }
        set { MainActor.assumeIsolated { _button.alternateImage = newValue } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/attributedtitle
    open var attributedTitle: NSAttributedString? {
        get { MainActor.assumeIsolated { _button.attributedTitle } }
        set { MainActor.assumeIsolated { _button.attributedTitle = newValue ?? NSAttributedString(string: "") } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/autosavename
    /// Set, the item's visibility is remembered in UserDefaults; unset, a name is made
    /// up per item as AppKit does ("Item-N").
    @available(macOS 10.12, *)
    open var autosaveName: NSStatusItem.AutosaveName! {
        get { MainActor.assumeIsolated { _autosaveName ?? "Item-\(NSStatusItem._counter)" } }
        set {
            MainActor.assumeIsolated {
                _autosaveName = newValue
                if let name = newValue, let saved = UserDefaults.standard.object(forKey: NSStatusItem._visibleKey(name)) as? Bool, saved != _isVisible {
                    _isVisible = saved
                    _syncPlatform()
                }
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/behavior
    @available(macOS 10.12, *)
    open var behavior: NSStatusItem.Behavior {
        get { MainActor.assumeIsolated { _behavior } }
        set { MainActor.assumeIsolated { _behavior = newValue } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/button
    @available(macOS 10.10, *)
    open var button: NSStatusBarButton? { MainActor.assumeIsolated { _removed ? nil : _button } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/doubleaction
    open var doubleAction: Selector? {
        get { MainActor.assumeIsolated { _doubleAction } }
        set { MainActor.assumeIsolated { _doubleAction = newValue } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/drawstatusbarbackground(in:withhighlight:)
    /// The platform draws the status area; there is no background of ours to draw.
    open func drawStatusBarBackground(in rect: NSRect, withHighlight highlight: Bool) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/highlightmode
    open var highlightMode: Bool {
        get { MainActor.assumeIsolated { _highlightMode } }
        set { MainActor.assumeIsolated { _highlightMode = newValue } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/image
    open var image: NSImage? {
        get { MainActor.assumeIsolated { _button.image } }
        set { MainActor.assumeIsolated { _button.image = newValue } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/isenabled
    open var isEnabled: Bool {
        get { MainActor.assumeIsolated { _button.isEnabled } }
        set { MainActor.assumeIsolated { _button.isEnabled = newValue } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/isvisible
    @available(macOS 10.12, *)
    open var isVisible: Bool {
        get { MainActor.assumeIsolated { _isVisible } }
        set {
            MainActor.assumeIsolated {
                guard _isVisible != newValue else { return }
                _isVisible = newValue
                if let name = _autosaveName {
                    UserDefaults.standard.set(newValue, forKey: NSStatusItem._visibleKey(name))
                    UserDefaults.standard.synchronize()     // corelibs Foundation persists only on synchronize()
                }
                _syncPlatform()
                if !newValue, _behavior.contains(.terminationOnRemoval) { NSApplication.shared.terminate(self) }
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/length
    open var length: CGFloat {
        get { MainActor.assumeIsolated { _length } }
        set { MainActor.assumeIsolated { _length = newValue; _button.setFrameSize(NSSize(width: newValue > 0 ? newValue : _button.frame.height, height: _button.frame.height)) } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/menu
    open var menu: NSMenu? {
        get { MainActor.assumeIsolated { _menu } }
        set { MainActor.assumeIsolated { _menu = newValue } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/popupmenu(_:)
    /// Opens `menu` at the pointer (the platform tells us where the item is only on a click).
    open func popUpMenu(_ menu: NSMenu) {
        MainActor.assumeIsolated { _popUp(menu, at: Platform.backend.mouseLocation) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/sendaction(on:)
    open func sendAction(on mask: NSEvent.EventTypeMask) -> Int { MainActor.assumeIsolated { _button.sendAction(on: mask) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/squarelength
    static public var squareLength: CGFloat { -2 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/statusbar
    open var statusBar: NSStatusBar? { MainActor.assumeIsolated { _statusBar } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/target
    open var target: AnyObject? {
        get { MainActor.assumeIsolated { _button.target } }
        set { MainActor.assumeIsolated { _button.target = newValue } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/title
    open var title: String? {
        get { MainActor.assumeIsolated { _button.title.isEmpty ? nil : _button.title } }
        set { MainActor.assumeIsolated { _button.title = newValue ?? "" } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/tooltip
    open var toolTip: String? {
        get { MainActor.assumeIsolated { _button.toolTip } }
        set { MainActor.assumeIsolated { _button.toolTip = newValue } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/variablelength
    static public var variableLength: CGFloat { -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/view
    /// A custom view (deprecated in AppKit): kept, but the platforms' status areas show
    /// icons and text only, so the button is what appears.
    open var view: NSView? {
        get { MainActor.assumeIsolated { _view } }
        set { MainActor.assumeIsolated { _view = newValue } }
    }

    // MARK: Platform

    @MainActor private static func _visibleKey(_ name: String) -> String { "NSStatusItem Visible \(name)" }

    /// The button changed: the platform item follows.
    @MainActor internal func _buttonDidChange() { _syncPlatform() }

    @MainActor private func _syncPlatform() {
        guard let p = _platform else { return }
        p.title = _button.title
        p.toolTip = _button.toolTip
        p.isVisible = _isVisible && !_removed
        p.appearsDisabled = _button.appearsDisabled || !_button.isEnabled
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        p.setImage(_button.image?._cgImage(scale: scale), scale: scale)
    }

    @MainActor internal func _removeFromBar() {
        _removed = true
        _platform?.remove()
        _platform = nil
    }

    /// The platform's click, as `platformStatusItemClicked` delivers it.
    @MainActor internal func _handleClick(_ click: PlatformStatusItemClick, at point: NSPoint) {
        guard _button.isEnabled, !_removed else { return }
        let app = NSApplication.shared
        let type: NSEvent.EventType = click == .secondary ? .rightMouseUp : .leftMouseUp
        if let e = NSEvent.mouseEvent(with: type, location: point, modifierFlags: NSEvent._currentModifierFlags, timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: 0, context: nil, eventNumber: 0, clickCount: click == .doublePrimary ? 2 : 1, pressure: 1) {
            app._setCurrentEvent(e)
        }
        switch click {
        case .primary:
            if let m = _menu { _popUp(m, at: point) } else { _button._fireAction() }
        case .doublePrimary:
            if let d = _doubleAction { _ = app.sendAction(d, to: _button.target, from: _button) }
            else if let m = _menu { _popUp(m, at: point) } else { _button._fireAction() }
        case .secondary:
            if let m = _menu { _popUp(m, at: point) }
            else if _button._sendsActionOnRightMouseUp { _button._fireAction() }
        }
    }

    /// Opens the menu with its top-left at `point` (the pop-up keeps it on the screen).
    @MainActor private func _popUp(_ menu: NSMenu, at point: NSPoint) {
        _ = menu.popUp(positioning: nil, at: point, in: nil)
    }
}

extension NSStatusItem: PlatformStatusItemOwner {
    public func platformStatusItemClicked(_ click: PlatformStatusItemClick, at screenPoint: NSPoint) { _handleClick(click, at: screenPoint) }
}

extension NSStatusItem {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/autosavename
    public typealias AutosaveName = String
}

@available(macOS 10.12, *)
extension NSStatusItem {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/behavior
    @available(macOS 10.12, *)
    public struct Behavior: OptionSet, Sendable, Equatable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/behavior/removalallowed
        static public var removalAllowed: NSStatusItem.Behavior { NSStatusItem.Behavior(rawValue: 2) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusitem/behavior/terminationonremoval
        static public var terminationOnRemoval: NSStatusItem.Behavior { NSStatusItem.Behavior(rawValue: 4) }
    }
}
