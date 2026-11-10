// NSMenuToolbarItem: an item that drops a menu. Without an action, a click opens the
// menu under the item; with one, the click sends the action and the indicator (the
// small arrow at the trailing edge) opens the menu, as in AppKit.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenutoolbaritem
@available(macOS 10.15, *)
@MainActor open class NSMenuToolbarItem: NSToolbarItem {
    private var _menu = NSMenu(title: "")
    private var _showsIndicator = true

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenutoolbaritem/menu
    @MainActor open var menu: NSMenu {
        get { _menu }
        set { _menu = newValue; _changed(layout: false) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenutoolbaritem/showsindicator
    @MainActor open var showsIndicator: Bool {
        get { _showsIndicator }
        set { _showsIndicator = newValue; _changed() }
    }

    /// Opens the menu below `view` (the toolbar's button for this item).
    internal func _popUpMenu(below view: NSView) {
        let anchor = view.convert(view.bounds, to: nil)
        guard let w = view.window else { return }
        let screen = w.convertToScreen(anchor)
        _ = _NSMenuTracker.begin(menu: _menu, anchor: screen, placement: .besideAnchor(edge: .minY), openedWithMouseDown: false)
    }

    open override func copy(with zone: NSZone? = nil) -> Any {
        MainActor.assumeIsolated {
            let c = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            c._copyProperties(from: self)
            c._menu = _menu
            c._showsIndicator = _showsIndicator
            return c
        }
    }
}
