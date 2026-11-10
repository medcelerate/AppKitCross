// Status items (NSStatusBar / NSStatusItem): the seam to the platform's notification area.
//
// The core owns the item's model (button, menu, length, visibility); a backend shows an
// icon with a tool tip where the platform keeps such things (the Windows notification
// area through Shell_NotifyIcon, a StatusNotifierItem on Linux desktops, an in-process
// registry on the host backend) and reports clicks back with their screen position. The
// menu is the package's own pop-up (NSMenuPopUp.swift), opened by the core at that
// position. ADR-0018.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Which part of the pointer the platform saw on the item.
public enum PlatformStatusItemClick: Sendable {
    /// A left click (or the platform's primary activation).
    case primary
    /// A right click (or the platform's secondary activation / context menu request).
    case secondary
    /// A double click of the primary button.
    case doublePrimary
}

/// Implemented by `NSStatusItem`. Callbacks arrive on the main actor.
@MainActor
public protocol PlatformStatusItemOwner: AnyObject {
    /// The user clicked the item. `screenPoint` is in AppKit screen coordinates (the
    /// pointer position, or where the platform wants a menu anchored).
    func platformStatusItemClicked(_ click: PlatformStatusItemClick, at screenPoint: NSPoint)
}

/// One item in the platform's status area.
@MainActor
public protocol PlatformStatusItem: AnyObject {
    /// The text shown next to or instead of the icon where the platform shows text; the
    /// tool tip where it does not (the Windows notification area).
    var title: String { get set }
    var toolTip: String? { get set }
    /// The icon, in pixels at `scale`, premultiplied BGRA as `CGImage` carries it; nil
    /// shows the platform's placeholder (the application icon).
    func setImage(_ image: CGImage?, scale: CGFloat)
    var isVisible: Bool { get set }
    var appearsDisabled: Bool { get set }
    /// Removes the item from the status area. The object is unusable afterwards.
    func remove()
}

/// The platform's status area, when it has one.
@MainActor
public protocol PlatformStatusItemHost: AnyObject {
    func makeStatusItem(owner: PlatformStatusItemOwner) -> PlatformStatusItem
    /// The status area's thickness in points (menu bar height on macOS; the notification
    /// area's icon size elsewhere).
    var thickness: CGFloat { get }
}

extension PlatformBackend {
    /// Nil on platforms without a status area; `NSStatusBar` then keeps the items in
    /// memory and nothing is shown.
    public var statusItems: (any PlatformStatusItemHost)? { nil }
}
