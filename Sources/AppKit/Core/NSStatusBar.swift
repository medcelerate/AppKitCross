// NSStatusBar: the system status area. `system` is the one bar; its items go to the
// platform's notification area through `PlatformStatusItemHost` (Platform/StatusItem.swift).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusbar
open class NSStatusBar: NSObject {
    @MainActor private static var _system: NSStatusBar?
    @MainActor internal var _items: [NSStatusItem] = []

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusbar/isvertical
    open var isVertical: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusbar/removestatusitem(_:)
    open func removeStatusItem(_ item: NSStatusItem) {
        MainActor.assumeIsolated {
            guard let i = _items.firstIndex(where: { $0 === item }) else { return }
            _items.remove(at: i)
            item._removeFromBar()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusbar/statusitem(withlength:)
    open func statusItem(withLength length: CGFloat) -> NSStatusItem {
        MainActor.assumeIsolated {
            let item = NSStatusItem(statusBar: self, length: length)
            _items.append(item)
            return item
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusbar/system
    class public var system: NSStatusBar {
        MainActor.assumeIsolated {
            if let s = _system { return s }
            let s = NSStatusBar()
            _system = s
            return s
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstatusbar/thickness
    /// The menu bar's 22 points on macOS; what the platform's status area reports here.
    open var thickness: CGFloat { MainActor.assumeIsolated { Platform.backend.statusItems?.thickness ?? 22 } }
}
