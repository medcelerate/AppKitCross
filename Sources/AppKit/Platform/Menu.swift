// Menu seam. AppKit's main menu is application-wide; Windows menus belong to a window, so
// the backend applies the same description to every titled window and routes commands
// back by item id.

import Foundation

public struct PlatformMenuItem: Sendable {
    public var id: Int                      // command id, unique per NSMenuItem
    public var title: String                // display title ("" for separators)
    public var isSeparator: Bool
    public var isEnabled: Bool
    public var isChecked: Bool
    public var isHidden: Bool
    public var keyEquivalentLabel: String   // e.g. "Ctrl+S", shown right-aligned
    public var submenu: PlatformMenu?
}

public struct PlatformMenu: Sendable {
    public var id: Int                      // unique per NSMenu
    public var title: String
    public var items: [PlatformMenuItem]
}

/// Implemented by NSApplication: the backend asks it before a menu opens and after an
/// item is chosen.
@MainActor
public protocol PlatformMenuHost: AnyObject {
    /// Called when the native menu with `menuID` is about to open; return the refreshed menu.
    func platformMenuWillOpen(_ menuID: Int) -> PlatformMenu?
    func platformMenuItemSelected(_ itemID: Int)
}
