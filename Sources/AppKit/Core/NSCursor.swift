// NSCursor (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor
open class NSCursor: NSObject, NSSecureCoding, NSCoding {
    // MARK: Storage
    internal let _kind: PlatformCursor
    private let _image: NSImage
    private let _hotSpot: NSPoint
    private var _setOnEntered = false
    private var _setOnExited = false
    nonisolated(unsafe) private static var _stack: [NSCursor] = []
    nonisolated(unsafe) private static var _current: NSCursor? = nil
    nonisolated(unsafe) private static var _hiddenDepth = 0
    nonisolated(unsafe) private static var _standard: [String: NSCursor] = [:]

    private init(kind: PlatformCursor, name: String) {
        _kind = kind
        _image = NSImage(size: NSSize(width: 16, height: 16))
        _hotSpot = .zero
        super.init()
    }

    private static func standard(_ name: String, _ kind: PlatformCursor) -> NSCursor {
        if let c = _standard[name] { return c }
        let c = NSCursor(kind: kind, name: name)
        _standard[name] = c
        return c
    }

    private func _apply() {
        let kind = _kind
        MainActor.assumeIsolated { Platform.backend.setCursor(kind) }
    }

    open override var description: String { "<NSCursor \(_kind)>" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/init(coder:)
    public required convenience init(coder: NSCoder) { self.init(image: NSImage(size: .zero), hotSpot: .zero) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/init(image:foregroundcolorhint:backgroundcolorhint:hotspot:)
    public convenience init(image newImage: NSImage, foregroundColorHint fg: NSColor?, backgroundColorHint bg: NSColor?, hotSpot: NSPoint) { self.init(image: newImage, hotSpot: hotSpot) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/init(image:hotspot:)
    public init(image newImage: NSImage, hotSpot point: NSPoint) {
        _image = newImage
        _hotSpot = point
        let size = newImage.size
        let scale: CGFloat = 1
        let pixels: [UInt8] = MainActor.assumeIsolated {
            guard let cg = newImage._cgImage(scale: scale) else { return [] }
            #if os(Windows)
            return [UInt8](cg.data.prefix(cg.bytesPerRow * cg.height))
            #else
            return []
            #endif
        }
        if pixels.isEmpty {
            _kind = .arrow
        } else {
            _kind = .custom(width: Int(size.width * scale), height: Int(size.height * scale), hotSpotX: Int(point.x * scale), hotSpotY: Int(point.y * scale), bgraPixels: pixels)
        }
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/arrow
    class public var arrow: NSCursor { standard("arrow", .arrow) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/closedhand
    class public var closedHand: NSCursor { standard("closedHand", .closedHand) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/columnresize
    @available(macOS 15.0, *)
    class public var columnResize: NSCursor { standard("columnResize", .resizeLeftRight) }
    /// Returns the cursor for resizing a column (vertical divider) in the specified direction.
    /// - Parameter directions: The directions in which a column can be resized. This must not be empty.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/columnresize(directions:)
    @available(macOS 15.0, *)
    public class func columnResize(directions: NSHorizontalDirection.Set) -> NSCursor { resizeLeftRight }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/contextualmenu
    class public var contextualMenu: NSCursor { standard("contextualMenu", .contextualMenu) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/crosshair
    class public var crosshair: NSCursor { standard("crosshair", .crosshair) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/current
    class public var current: NSCursor { _current ?? arrow }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/currentsystem
    class public var currentSystem: NSCursor? { _current }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/disappearingitem
    class public var disappearingItem: NSCursor { standard("disappearingItem", .operationNotAllowed) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/dragcopy
    class public var dragCopy: NSCursor { standard("dragCopy", .dragCopy) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/draglink
    class public var dragLink: NSCursor { standard("dragLink", .dragLink) }
    /// Returns the cursor for resizing a rectangular frame from the specified edge or corner.
    /// - Parameters:
    ///   - position: The position along the perimeter of a rectangular frame (its edges and corners) from which it’s resized.
    ///   - directions: The directions in which a rectangular frame can be resized. This must not be empty.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/frameresize(position:directions:)
    @available(macOS 15.0, *)
    public class func frameResize(position: NSCursor.FrameResizePosition, directions: NSCursor.FrameResizeDirection.Set) -> NSCursor { standard("resizeAll", .resizeAll) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/hide()
    public class func hide() {
        _hiddenDepth += 1
        MainActor.assumeIsolated { Platform.backend.setCursorHidden(true) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/hotspot
    open var hotSpot: NSPoint { _hotSpot }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/ibeam
    class public var iBeam: NSCursor { standard("iBeam", .iBeam) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/ibeamcursorforverticallayout
    class public var iBeamCursorForVerticalLayout: NSCursor { standard("iBeamCursorForVerticalLayout", .iBeamVertical) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/image
    open var image: NSImage { _image }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/issetonmouseentered
    open var isSetOnMouseEntered: Bool { _setOnEntered }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/issetonmouseexited
    open var isSetOnMouseExited: Bool { _setOnExited }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/mouseentered(with:)
    open func mouseEntered(with event: NSEvent) { if _setOnEntered { set() } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/mouseexited(with:)
    open func mouseExited(with event: NSEvent) { if _setOnExited { set() } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/openhand
    class public var openHand: NSCursor { standard("openHand", .openHand) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/operationnotallowed
    class public var operationNotAllowed: NSCursor { standard("operationNotAllowed", .operationNotAllowed) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/pointinghand
    class public var pointingHand: NSCursor { standard("pointingHand", .pointingHand) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/pop()
    public class func pop() {
        guard let previous = _stack.popLast() else { return }
        previous.set()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/pop()
    open func pop() { NSCursor.pop() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/push()
    open func push() {
        NSCursor._stack.append(NSCursor.current)
        set()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/resizedown
    class public var resizeDown: NSCursor { standard("resizeDown", .resizeUpDown) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/resizeleft
    class public var resizeLeft: NSCursor { standard("resizeLeft", .resizeLeftRight) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/resizeleftright
    class public var resizeLeftRight: NSCursor { standard("resizeLeftRight", .resizeLeftRight) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/resizeright
    class public var resizeRight: NSCursor { standard("resizeRight", .resizeLeftRight) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/resizeup
    class public var resizeUp: NSCursor { standard("resizeUp", .resizeUpDown) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/resizeupdown
    class public var resizeUpDown: NSCursor { standard("resizeUpDown", .resizeUpDown) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/rowresize
    @available(macOS 15.0, *)
    class public var rowResize: NSCursor { standard("rowResize", .resizeUpDown) }
    /// Returns the cursor for resizing a row (horizontal divider) in the specified direction.
    /// - Parameter directions: The directions in which a row can be resized. This must not be empty.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/rowresize(directions:)
    @available(macOS 15.0, *)
    public class func rowResize(directions: NSVerticalDirection.Set) -> NSCursor { resizeUpDown }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/set()
    open func set() {
        NSCursor._current = self
        _apply()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/sethiddenuntilmousemoves(_:)
    public class func setHiddenUntilMouseMoves(_ flag: Bool) { if flag { hide() } else { unhide() } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/setonmouseentered(_:)
    open func setOnMouseEntered(_ flag: Bool) { _setOnEntered = flag }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/setonmouseexited(_:)
    open func setOnMouseExited(_ flag: Bool) { _setOnExited = flag }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/unhide()
    public class func unhide() {
        guard _hiddenDepth > 0 else { return }
        _hiddenDepth -= 1
        MainActor.assumeIsolated { Platform.backend.setCursorHidden(false) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/zoomin
    @available(macOS 15.0, *)
    class public var zoomIn: NSCursor { standard("zoomIn", .crosshair) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscursor/zoomout
    @available(macOS 15.0, *)
    class public var zoomOut: NSCursor { standard("zoomOut", .crosshair) }
    // Requirement of NSSecureCoding
    class public var supportsSecureCoding: Bool { true }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { }
}
