// NSTrackingArea (hand-written; seeded from the generated stub, see tools/apigen)
// A rectangle of a view that reports the pointer entering, leaving and moving inside it
// to its owner. The window evaluates every area of its view tree against the backend's
// mouse-move stream (NSWindow._evaluateTrackingAreas) and against changes of the
// activity the options ask for: key window, active application, first responder.
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstrackingarea
open class NSTrackingArea: NSObject, NSCopying, NSCoding {
    private let _rect: NSRect
    private let _options: NSTrackingArea.Options
    // The owner is not retained, as in AppKit: a view owning its own areas would cycle.
    private weak var _owner: AnyObject?
    private let _userInfo: [AnyHashable: Any]?

    // MARK: Tracking state (NSView, NSWindow)

    /// The view the area was added to.
    @MainActor internal weak var _view: NSView?
    /// Whether the pointer was inside at the last evaluation; `assumeInside` starts it true.
    @MainActor internal var _isInside = false

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstrackingarea/init(rect:options:owner:userinfo:)
    public init(rect: NSRect, options: NSTrackingArea.Options = [], owner: Any?, userInfo: [AnyHashable : Any]? = nil) {
        _rect = rect
        _options = options
        _owner = owner as AnyObject?
        _userInfo = userInfo
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstrackingarea/options
    open var options: NSTrackingArea.Options { _options }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstrackingarea/owner
    open var owner: AnyObject? { _owner }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstrackingarea/rect
    open var rect: NSRect { _rect }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstrackingarea/userinfo
    open var userInfo: [AnyHashable : Any]? { _userInfo }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any { NSTrackingArea(rect: _rect, options: _options, owner: _owner, userInfo: _userInfo) }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { unimplemented() }
    // Requirement of NSCoding
    public required init?(coder: NSCoder) { unimplemented() }

    open override var description: String {
        "<NSTrackingArea rect=\(_rect) options=\(_options.rawValue) inside=\(MainActor.assumeIsolated { _isInside })>"
    }

    // MARK: Evaluation helpers (NSWindow)

    /// The activity scope the options ask for; AppKit requires one, here a missing scope
    /// behaves like `activeInKeyWindow`.
    internal var _activity: NSTrackingArea.Options {
        let scopes: NSTrackingArea.Options = [.activeWhenFirstResponder, .activeInKeyWindow, .activeInActiveApp, .activeAlways]
        let s = _options.intersection(scopes)
        return s.isEmpty ? .activeInKeyWindow : s
    }

    /// The responder the owner's messages go to: the owner itself when it is a responder
    /// (a view, a view controller, the window) and the area's view otherwise. An `NSCursor`
    /// owner takes its own entered/exited messages (`_ownerCursor`).
    @MainActor internal var _ownerResponder: NSResponder? {
        if let r = _owner as? NSResponder { return r }
        return _view
    }
    @MainActor internal var _ownerCursor: NSCursor? { _owner as? NSCursor }

    /// The area in window coordinates for the current geometry, or nil when the view is
    /// not in a window, hidden, or the area has no visible part. `inVisibleRect` follows
    /// the view's visible rect; a fixed rect is clipped to it, so the parts a scroll view
    /// hides do not track.
    @MainActor internal var _windowRect: NSRect? {
        guard let v = _view, v.window != nil, !v.isHiddenOrHasHiddenAncestor else { return nil }
        let visible = v.visibleRect
        let r = _options.contains(.inVisibleRect) ? visible : _rect.intersection(visible)
        guard !r.isEmpty else { return nil }
        return v.convert(r, to: nil)
    }
}
extension NSTrackingArea {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstrackingarea/options
    public struct Options: OptionSet, Sendable, Equatable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstrackingarea/options/activealways
        static public var activeAlways: NSTrackingArea.Options { NSTrackingArea.Options(rawValue: 128) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstrackingarea/options/activeinactiveapp
        static public var activeInActiveApp: NSTrackingArea.Options { NSTrackingArea.Options(rawValue: 64) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstrackingarea/options/activeinkeywindow
        static public var activeInKeyWindow: NSTrackingArea.Options { NSTrackingArea.Options(rawValue: 32) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstrackingarea/options/activewhenfirstresponder
        static public var activeWhenFirstResponder: NSTrackingArea.Options { NSTrackingArea.Options(rawValue: 16) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstrackingarea/options/assumeinside
        static public var assumeInside: NSTrackingArea.Options { NSTrackingArea.Options(rawValue: 256) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstrackingarea/options/cursorupdate
        static public var cursorUpdate: NSTrackingArea.Options { NSTrackingArea.Options(rawValue: 4) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstrackingarea/options/enabledduringmousedrag
        static public var enabledDuringMouseDrag: NSTrackingArea.Options { NSTrackingArea.Options(rawValue: 1024) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstrackingarea/options/invisiblerect
        static public var inVisibleRect: NSTrackingArea.Options { NSTrackingArea.Options(rawValue: 512) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstrackingarea/options/mouseenteredandexited
        static public var mouseEnteredAndExited: NSTrackingArea.Options { NSTrackingArea.Options(rawValue: 1) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstrackingarea/options/mousemoved
        static public var mouseMoved: NSTrackingArea.Options { NSTrackingArea.Options(rawValue: 2) }
    }
}
