// NSRulerMarker (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// A marker sits on its ruler's baseline at `markerLocation`, a coordinate along the ruler
// axis in the client view's space (ADR-0034). Its image is placed so that `imageOrigin`
// (in the image's own unflipped coordinates) lands on the baseline at that location; the
// part of the image on the outer side of the baseline is the thickness it needs. Dragging
// runs on the ruler's mouse events (`NSRulerView` keeps the drag state): the port has no
// modal event loop, so `trackMouse(with:adding:)` starts the drag and returns whether it
// started, and the drag finishes with the mouse-up the ruler receives.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulermarker
open class NSRulerMarker: NSObject, NSCopying, NSCoding {
    private weak var _ruler: NSRulerView?
    private var _location: CGFloat
    private var _image: NSImage
    private var _imageOrigin: NSPoint
    private var _isMovable = true
    private var _isRemovable = false
    private var _representedObject: (any NSCopying)?
    /// Set by the ruler while it drags this marker.
    internal var _isDragging = false

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulermarker/init(coder:)
    public required init(coder: NSCoder) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulermarker/init(rulerview:markerlocation:image:imageorigin:)
    public init(rulerView ruler: NSRulerView, markerLocation location: CGFloat, image: NSImage, imageOrigin: NSPoint) {
        _ruler = ruler
        _location = location
        _image = image
        _imageOrigin = imageOrigin
        super.init()
    }
    /// A copy's: its ruler may be gone.
    private init(_ruler ruler: NSRulerView?, location: CGFloat, image: NSImage, imageOrigin: NSPoint) {
        _ruler = ruler
        _location = location
        _image = image
        _imageOrigin = imageOrigin
        super.init()
    }
    /// Draws the image at `imageRectInRuler` (the ruler's current context).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulermarker/draw(_:)
    open func draw(_ rect: NSRect) {
        let r = imageRectInRuler
        guard r.intersects(rect) else { return }
        _image.draw(in: r, from: .zero, operation: .sourceOver, fraction: _isDragging ? 0.7 : 1, respectFlipped: true, hints: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulermarker/image
    open var image: NSImage {
        get { _image }
        set { _image = newValue; _redisplay() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulermarker/imageorigin
    open var imageOrigin: NSPoint {
        get { _imageOrigin }
        set { _imageOrigin = newValue; _redisplay() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulermarker/imagerectinruler
    open var imageRectInRuler: NSRect {
        guard let ruler = _ruler else { return NSRect(origin: .zero, size: _image.size) }
        let size = _image.size, origin = _imageOrigin, location = _location
        return MainActor.assumeIsolated {
            let at = ruler._rulerLocation(forClientLocation: location)
            let base = ruler.baselineLocation
            if ruler.orientation == .horizontalRuler {
                // The horizontal ruler is flipped: the image's bottom is its maximum y.
                return NSRect(x: at - origin.x, y: base - size.height + origin.y, width: size.width, height: size.height)
            }
            let y = ruler.isFlipped ? at - (size.height - origin.y) : at - origin.y
            return NSRect(x: base - origin.x, y: y, width: size.width, height: size.height)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulermarker/isdragging
    open var isDragging: Bool { _isDragging }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulermarker/ismovable
    open var isMovable: Bool {
        get { _isMovable }
        set { _isMovable = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulermarker/isremovable
    open var isRemovable: Bool {
        get { _isRemovable }
        set { _isRemovable = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulermarker/markerlocation
    open var markerLocation: CGFloat {
        get { _location }
        set {
            guard newValue != _location else { return }
            _redisplay()
            _location = newValue
            _redisplay()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulermarker/representedobject
    open var representedObject: (any NSCopying)? {
        get { _representedObject }
        set { _representedObject = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulermarker/ruler
    open var ruler: NSRulerView? { _ruler }
    /// The image's extent on the outer side of the baseline.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulermarker/thicknessrequiredinruler
    open var thicknessRequiredInRuler: CGFloat {
        guard let ruler = _ruler else { return _image.size.height - _imageOrigin.y }
        let horizontal = MainActor.assumeIsolated { ruler.orientation == .horizontalRuler }
        return horizontal ? _image.size.height - _imageOrigin.y : _imageOrigin.x
    }
    /// Starts dragging the marker from `mouseDownEvent` (adding it to the ruler when
    /// `isAdding`), asking the client view first. The drag continues on the ruler's mouse
    /// events; returns whether it started.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulermarker/trackmouse(with:adding:)
    open func trackMouse(with mouseDownEvent: NSEvent, adding isAdding: Bool) -> Bool {
        guard let ruler = _ruler else { return false }
        nonisolated(unsafe) let event = mouseDownEvent
        return MainActor.assumeIsolated { ruler._beginTracking(self, adding: isAdding, event: event) }
    }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any {
        let c = NSRulerMarker(_ruler: _ruler, location: _location, image: _image, imageOrigin: _imageOrigin)
        c._isMovable = _isMovable
        c._isRemovable = _isRemovable
        c._representedObject = _representedObject.map { $0.copy(with: nil) as! any NSCopying }
        return c
    }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { unimplemented() }

    private func _redisplay() {
        guard let ruler = _ruler else { return }
        let rect = imageRectInRuler.insetBy(dx: -1, dy: -1)
        MainActor.assumeIsolated {
            guard ruler.markers?.contains(where: { $0 === self }) == true || self._isDragging else { return }
            ruler.setNeedsDisplay(rect)
        }
    }
}
