// NSStatusBarButton: the button inside an NSStatusItem. Its title, image and tool tip are
// what the platform's status area shows; a click there sends its action, or opens the
// item's menu.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusbarbutton
@available(macOS 10.10, *)
@MainActor open class NSStatusBarButton: NSButton {
    private var _appearsDisabled = false
    internal weak var _statusItem: NSStatusItem?

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusbarbutton/appearsdisabled
    @MainActor open var appearsDisabled: Bool {
        get { _appearsDisabled }
        set { _appearsDisabled = newValue; _statusItem?._buttonDidChange() }
    }

    /// Whether `sendAction(on:)` included right mouse ups (the status area's secondary click).
    internal var _sendsActionOnRightMouseUp: Bool {
        let mask = sendAction(on: [])
        _ = sendAction(on: NSEvent.EventTypeMask(rawValue: UInt64(mask)))
        return mask & Int(NSEvent.EventTypeMask.rightMouseUp.rawValue) != 0
    }

    open override var title: String {
        get { super.title }
        set { super.title = newValue; _statusItem?._buttonDidChange() }
    }
    open override var image: NSImage? {
        get { super.image }
        set { super.image = newValue; _statusItem?._buttonDidChange() }
    }
    open override var toolTip: String? {
        get { super.toolTip }
        set { super.toolTip = newValue; _statusItem?._buttonDidChange() }
    }
    open override var isEnabled: Bool {
        get { super.isEnabled }
        set { super.isEnabled = newValue; _statusItem?._buttonDidChange() }
    }
}
