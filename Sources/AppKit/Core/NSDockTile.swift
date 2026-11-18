// NSDockTile (hand-written; ADR-0022). The application's tile is what the taskbar or
// launcher shows for it: the badge becomes a taskbar overlay icon (Windows), a launcher
// count and a badge drawn on the window icon (Linux); a content view replaces the icon
// with its rendering. The core draws the badge and composes the icon so every platform
// shows the same pixels; `PlatformWorkspace.setDockTile` places them. A window's tile
// (`NSWindow.dockTile`, the minimised window) shares the machinery but the platforms show
// no separate tile for it, so only the application's reaches the taskbar.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocktile
open class NSDockTile: NSObject {
    @MainActor private weak var _owner: AnyObject?
    @MainActor private var _badgeLabel: String?
    @MainActor private var _contentView: NSView?
    @MainActor private var _showsApplicationBadge = true
    @MainActor private var _isApplicationTile: Bool { _owner is NSApplication }

    @MainActor internal init(owner: AnyObject?) {
        _owner = owner
        super.init()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocktile/owner
    open var owner: AnyObject? { MainActor.assumeIsolated { _owner } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocktile/size
    open var size: NSSize { NSSize(width: 128, height: 128) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocktile/badgelabel
    open var badgeLabel: String? {
        get { MainActor.assumeIsolated { _badgeLabel } }
        set { MainActor.assumeIsolated { _badgeLabel = newValue; display() } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocktile/contentview
    open var contentView: NSView? {
        get { MainActor.assumeIsolated { _contentView } }
        set { MainActor.assumeIsolated { _contentView = newValue } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocktile/showsapplicationbadge
    open var showsApplicationBadge: Bool {
        get { MainActor.assumeIsolated { _showsApplicationBadge } }
        set { MainActor.assumeIsolated { _showsApplicationBadge = newValue; display() } }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdocktile/display()
    open func display() {
        MainActor.assumeIsolated {
            guard _isApplicationTile else { return }
            Platform.backend.workspace.setDockTile(_render())
        }
    }

    /// The tile as pixels: the badge overlay and, when the tile has a content view or the
    /// application an icon image, the icon with the badge in its top-right corner.
    @MainActor internal func _render() -> PlatformDockTile {
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        let label = _showsApplicationBadge ? _badgeLabel.flatMap { $0.isEmpty ? nil : $0 } : nil
        let overlay = label.flatMap { _NSWorkspaceIcons.badge($0, scale: scale) }
        var icon: CGImage? = nil
        var base: NSImage? = nil
        if let view = _contentView {
            base = NSImage(size: size, flipped: false) { [weak view] rect in
                guard let view, let gc = NSGraphicsContext.current else { return false }
                view.setFrameSize(rect.size)
                view.layoutSubtreeIfNeeded()
                view.displayIgnoringOpacity(view.bounds, in: gc)
                return true
            }
        } else if let app = _owner as? NSApplication, let image = app._applicationIconImageIfSet {
            base = image
        }
        if let base {
            icon = _NSWorkspaceIcons.compose(icon: base, size: size, badge: overlay, scale: scale)
        } else if let overlay, let platformIcon = Platform.backend.workspace.icon(for: .process(ProcessInfo.processInfo.processIdentifier), size: size.width, scale: scale) {
            icon = _NSWorkspaceIcons.compose(icon: NSImage(cgImage: platformIcon, size: size), size: size, badge: overlay, scale: scale)
        }
        return PlatformDockTile(badgeLabel: label, badgeOverlay: overlay, icon: icon, scale: scale)
    }
}
