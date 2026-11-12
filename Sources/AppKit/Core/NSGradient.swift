// NSGradient (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// Color stops at locations 0...1, interpolated component-wise between neighbouring stops
// (ADR-0034). The port's CoreGraphics has no shading primitive on Direct2D or Cairo, so
// a gradient is painted as bands through the calls every backend has: the axis (or the
// circles of a radial gradient) is cut into about two bands per point, each filled with
// the colour at its middle, with antialiasing off so neighbouring bands share their edges
// exactly (no seams, no double-painted overlap for translucent colours). The outer edge
// comes from the clip (`draw(in:)` clips to its rect or path), which stays antialiased.
// The macOS host build paints the same bands through Apple's CoreGraphics, so the pixel
// tests check what Windows and Linux draw.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgradient
open class NSGradient: NSObject, NSCopying, NSSecureCoding, NSCoding {
    /// The stops sorted by location; at least two.
    private let _colors: [NSColor]
    private let _locations: [CGFloat]
    /// The space given to `init(colors:atLocations:colorSpace:)`; nil for the convenience
    /// initialisers, whose space is AppKit's generic RGB space.
    private let _colorSpace: NSColorSpace?
    /// The stops' RGBA components, cached for interpolation.
    private let _rgba: [(CGFloat, CGFloat, CGFloat, CGFloat)]

    private typealias _Stops = (colors: [NSColor], locations: [CGFloat], rgba: [(CGFloat, CGFloat, CGFloat, CGFloat)])

    /// The stops in location order (a stable sort keeps equal locations as given: a hard
    /// edge), evenly spaced when no locations are given; nil for fewer than two colours.
    private static func _stops(_ colors: [NSColor], _ locations: [CGFloat]?) -> _Stops? {
        guard colors.count >= 2 else { return nil }
        let locs = locations.map { Array($0.prefix(colors.count)) } ?? (0..<colors.count).map { CGFloat($0) / CGFloat(colors.count - 1) }
        guard locs.count == colors.count else { return nil }
        let order = locs.indices.sorted { locs[$0] < locs[$1] || (locs[$0] == locs[$1] && $0 < $1) }
        let sorted = order.map { colors[$0] }
        let rgba = sorted.map { c -> (CGFloat, CGFloat, CGFloat, CGFloat) in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            return (r, g, b, a)
        }
        return (sorted, order.map { locs[$0] }, rgba)
    }

    private init?(_colors colors: [NSColor], locations: [CGFloat]?, colorSpace: NSColorSpace?) {
        guard let stops = NSGradient._stops(colors, locations) else { return nil }
        (_colors, _locations, _rgba) = stops
        _colorSpace = colorSpace
        super.init()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgradient/init(coder:)
    public required init?(coder: NSCoder) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgradient/init(colors:)
    public convenience init?(colors colorArray: [NSColor]) {
        self.init(_colors: colorArray, locations: nil, colorSpace: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgradient/init(colors:atlocations:colorspace:)
    public init?(colors colorArray: [NSColor], atLocations locations: UnsafePointer<CGFloat>?, colorSpace: NSColorSpace) {
        let locs = locations.map { p in (0..<colorArray.count).map { p[$0] } }
        guard let stops = NSGradient._stops(colorArray, locs) else { return nil }
        (_colors, _locations, _rgba) = stops
        _colorSpace = colorSpace
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgradient/init(colorsandlocations:)
    public convenience init?(colorsAndLocations objects: (NSColor, CGFloat)...) {
        self.init(_colors: objects.map { $0.0 }, locations: objects.map { $0.1 }, colorSpace: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgradient/init(starting:ending:)
    public convenience init?(starting startingColor: NSColor, ending endingColor: NSColor) {
        self.init(_colors: [startingColor, endingColor], locations: [0, 1], colorSpace: nil)
    }
    /// The space given at initialisation; AppKit's generic RGB space otherwise (which the
    /// port's `NSColorSpace` does not model yet).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgradient/colorspace
    open var colorSpace: NSColorSpace { _colorSpace ?? NSColorSpace.genericRGB }

    // MARK: Drawing

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgradient/draw(from:to:options:)
    open func draw(from startingPoint: NSPoint, to endingPoint: NSPoint, options: NSGradient.DrawingOptions = []) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        _drawLinear(ctx, from: startingPoint, to: endingPoint, options: options, extent: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgradient/draw(fromcenter:radius:tocenter:radius:options:)
    open func draw(fromCenter startCenter: NSPoint, radius startRadius: CGFloat, toCenter endCenter: NSPoint, radius endRadius: CGFloat, options: NSGradient.DrawingOptions = []) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        _drawRadial(ctx, c0: startCenter, r0: max(0, startRadius), c1: endCenter, r1: max(0, endRadius), options: options, extent: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgradient/draw(in:angle:)
    open func draw(in rect: NSRect, angle: CGFloat) {
        guard let ctx = NSGraphicsContext.current?.cgContext, !rect.isEmpty else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        let (s, e) = NSGradient._axis(for: rect, angle: angle)
        _drawLinear(ctx, from: s, to: e, options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation], extent: rect)
        ctx.restoreGState()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgradient/draw(in:angle:)
    open func draw(in path: NSBezierPath, angle: CGFloat) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let box = path.bounds
        guard !box.isEmpty else { return }
        ctx.saveGState()
        path.addClip()
        let (s, e) = NSGradient._axis(for: box, angle: angle)
        _drawLinear(ctx, from: s, to: e, options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation], extent: box)
        ctx.restoreGState()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgradient/draw(in:relativecenterposition:)
    open func draw(in rect: NSRect, relativeCenterPosition: NSPoint) {
        guard let ctx = NSGraphicsContext.current?.cgContext, !rect.isEmpty else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        let (c0, c1, r1) = NSGradient._radialGeometry(for: rect, relativeCenterPosition: relativeCenterPosition)
        _drawRadial(ctx, c0: c0, r0: 0, c1: c1, r1: r1, options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation], extent: rect)
        ctx.restoreGState()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgradient/draw(in:relativecenterposition:)
    open func draw(in path: NSBezierPath, relativeCenterPosition: NSPoint) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let box = path.bounds
        guard !box.isEmpty else { return }
        ctx.saveGState()
        path.addClip()
        let (c0, c1, r1) = NSGradient._radialGeometry(for: box, relativeCenterPosition: relativeCenterPosition)
        _drawRadial(ctx, c0: c0, r0: 0, c1: c1, r1: r1, options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation], extent: box)
        ctx.restoreGState()
    }

    // MARK: Stops

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgradient/getcolor(_:location:at:)
    open func getColor(_ color: AutoreleasingUnsafeMutablePointer<NSColor>?, location: UnsafeMutablePointer<CGFloat>?, at index: Int) {
        precondition(index >= 0 && index < _colors.count, "NSGradient: color stop index \(index) out of range")
        color?.pointee = _colors[index]
        location?.pointee = _locations[index]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgradient/interpolatedcolor(atlocation:)
    open func interpolatedColor(atLocation location: CGFloat) -> NSColor {
        let (r, g, b, a) = _components(at: location)
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgradient/numberofcolorstops
    open var numberOfColorStops: Int { _colors.count }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any { self }   // immutable, as AppKit's
    // Requirement of NSSecureCoding
    class public var supportsSecureCoding: Bool { true }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { unimplemented() }

    // MARK: Geometry (internal so the tests can check it)

    /// The colour at `location`: the first stop's before it, the last stop's after it, and
    /// a straight blend between the two stops around it in between.
    internal func _components(at location: CGFloat) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        if location <= _locations[0] { return _rgba[0] }
        if location >= _locations[_locations.count - 1] { return _rgba[_rgba.count - 1] }
        var i = 1
        while i < _locations.count - 1 && _locations[i] < location { i += 1 }
        let l0 = _locations[i - 1], l1 = _locations[i]
        let f = l1 > l0 ? (location - l0) / (l1 - l0) : 1
        let a = _rgba[i - 1], b = _rgba[i]
        return (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f, a.2 + (b.2 - a.2) * f, a.3 + (b.3 - a.3) * f)
    }

    /// The axis of `draw(in:angle:)`: through the rect's centre at `angle` degrees
    /// (0 = left to right, 90 = bottom to top in an unflipped space), from the rect's
    /// first corner to its last along that direction, so the stops span the whole rect.
    internal static func _axis(for rect: NSRect, angle: CGFloat) -> (NSPoint, NSPoint) {
        let rad = angle * .pi / 180
        var dx = cos(rad), dy = sin(rad)
        if abs(dx) < 1e-12 { dx = 0 }
        if abs(dy) < 1e-12 { dy = 0 }
        let half = abs(dx) * rect.width / 2 + abs(dy) * rect.height / 2
        let c = NSPoint(x: rect.midX, y: rect.midY)
        return (NSPoint(x: c.x - dx * half, y: c.y - dy * half), NSPoint(x: c.x + dx * half, y: c.y + dy * half))
    }

    /// `draw(in:relativeCenterPosition:)`: the start circle is a point at the relative
    /// position ((-1, -1) is the rect's minimum corner, (1, 1) its maximum), the end circle
    /// is centred on the rect and just encloses it.
    internal static func _radialGeometry(for rect: NSRect, relativeCenterPosition p: NSPoint) -> (NSPoint, NSPoint, CGFloat) {
        let px = min(max(p.x, -1), 1), py = min(max(p.y, -1), 1)
        let c0 = NSPoint(x: rect.midX + px * rect.width / 2, y: rect.midY + py * rect.height / 2)
        let c1 = NSPoint(x: rect.midX, y: rect.midY)
        let r1 = (rect.width * rect.width + rect.height * rect.height).squareRoot() / 2
        return (c0, c1, r1)
    }

    /// The area extension bands may cover: the given extent, else the clip's box (when it
    /// is a usable finite rect), else a generous square around `around`.
    private func _paintExtent(_ ctx: CGContext, extent: NSRect?, around: NSPoint, reach: CGFloat) -> NSRect {
        if let extent { return extent }
        let box = ctx.boundingBoxOfClipPath
        let near = NSRect(x: around.x - reach, y: around.y - reach, width: 2 * reach, height: 2 * reach)
        if box.isNull || box.isInfinite || box.isEmpty || abs(box.minX) > 1e5 || abs(box.maxX) > 1e5 || abs(box.minY) > 1e5 || abs(box.maxY) > 1e5 {
            return near
        }
        return box.union(near)
    }

    private func _setFill(_ ctx: CGContext, at t: CGFloat) {
        let (r, g, b, a) = _components(at: t)
        ctx.setFillColor(red: r, green: g, blue: b, alpha: a)
    }

    /// Bands across the axis: in a space rotated so the axis runs along +x from 0 to its
    /// length, each band is a rect spanning the paint extent across the axis.
    private func _drawLinear(_ ctx: CGContext, from p0: NSPoint, to p1: NSPoint, options: NSGradient.DrawingOptions, extent: NSRect?) {
        let dx = p1.x - p0.x, dy = p1.y - p0.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return }
        let area = _paintExtent(ctx, extent: extent, around: NSPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2), reach: max(2048, length))
        // The extent's corners in the rotated space bound the bands across the axis and the
        // extensions along it.
        let ux = dx / length, uy = dy / length
        var minA = CGFloat.infinity, maxA = -CGFloat.infinity, minB = CGFloat.infinity, maxB = -CGFloat.infinity
        for c in [NSPoint(x: area.minX, y: area.minY), NSPoint(x: area.maxX, y: area.minY), NSPoint(x: area.minX, y: area.maxY), NSPoint(x: area.maxX, y: area.maxY)] {
            let rx = c.x - p0.x, ry = c.y - p0.y
            let a = rx * ux + ry * uy, b = -rx * uy + ry * ux
            minA = min(minA, a); maxA = max(maxA, a); minB = min(minB, b); maxB = max(maxB, b)
        }
        // A pixel of slack so the band edges never fall exactly on the extent's.
        minB -= 1; maxB += 1
        ctx.saveGState()
        ctx.setShouldAntialias(false)
        ctx.translateBy(x: p0.x, y: p0.y)
        ctx.rotate(by: atan2(dy, dx))
        if options.contains(.drawsBeforeStartingLocation), minA < 0 {
            _setFill(ctx, at: _locations[0])
            ctx.fill(CGRect(x: minA - 1, y: minB, width: -minA + 1, height: maxB - minB))
        }
        if options.contains(.drawsAfterEndingLocation), maxA > length {
            _setFill(ctx, at: _locations[_locations.count - 1])
            ctx.fill(CGRect(x: length, y: minB, width: maxA - length + 1, height: maxB - minB))
        }
        let n = NSGradient._bandCount(length)
        // Only the bands inside the extent are painted.
        let first = max(0, Int(floor(minA / length * CGFloat(n))))
        let last = min(n, Int(ceil(maxA / length * CGFloat(n))))
        if first < last {
            for i in first..<last {
                let t0 = CGFloat(i) / CGFloat(n), t1 = CGFloat(i + 1) / CGFloat(n)
                _setFill(ctx, at: (t0 + t1) / 2)
                ctx.fill(CGRect(x: t0 * length, y: minB, width: (t1 - t0) * length, height: maxB - minB))
            }
        }
        ctx.restoreGState()
    }

    /// About two bands per point of the axis, at most 1024.
    internal static func _bandCount(_ length: CGFloat) -> Int { min(1024, max(2, Int((length * 2).rounded(.up)))) }

    /// Rings between the circles at successive locations, each the even-odd area between
    /// two circles, painted with the colour at its middle. Exact for nested circles (the
    /// common highlight and spot shapes); circles that are not nested are approximated by
    /// the same rings.
    private func _drawRadial(_ ctx: CGContext, c0: NSPoint, r0: CGFloat, c1: NSPoint, r1: CGFloat, options: NSGradient.DrawingOptions, extent: NSRect?) {
        let dist = ((c1.x - c0.x) * (c1.x - c0.x) + (c1.y - c0.y) * (c1.y - c0.y)).squareRoot()
        let span = max(abs(r1 - r0), dist)
        guard span > 0 || r0 != r1 else { return }
        func center(_ t: CGFloat) -> NSPoint { NSPoint(x: c0.x + (c1.x - c0.x) * t, y: c0.y + (c1.y - c0.y) * t) }
        func radius(_ t: CGFloat) -> CGFloat { max(0, r0 + (r1 - r0) * t) }
        func circle(_ t: CGFloat) -> CGRect {
            let c = center(t), r = radius(t)
            return CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        }
        let area = _paintExtent(ctx, extent: extent, around: c1, reach: max(2048, r0, r1))
        let bigIsEnd = r1 >= r0
        ctx.saveGState()
        ctx.setShouldAntialias(false)
        // The extension past the large circle covers everything outside it; the one past
        // the small circle fills its disc.
        let outerOption: NSGradient.DrawingOptions = bigIsEnd ? .drawsAfterEndingLocation : .drawsBeforeStartingLocation
        let innerOption: NSGradient.DrawingOptions = bigIsEnd ? .drawsBeforeStartingLocation : .drawsAfterEndingLocation
        let outerT: CGFloat = bigIsEnd ? 1 : 0, innerT: CGFloat = bigIsEnd ? 0 : 1
        if options.contains(outerOption) {
            _setFill(ctx, at: bigIsEnd ? _locations[_locations.count - 1] : _locations[0])
            ctx.beginPath()
            ctx.addRect(area.insetBy(dx: -1, dy: -1))
            ctx.addEllipse(in: circle(outerT))
            ctx.fillPath(using: .evenOdd)
        }
        let n = min(512, NSGradient._bandCount(max(span, r0, r1)))
        for i in 0..<n {
            let t0 = CGFloat(i) / CGFloat(n), t1 = CGFloat(i + 1) / CGFloat(n)
            _setFill(ctx, at: (t0 + t1) / 2)
            ctx.beginPath()
            if radius(t0) > 0 { ctx.addEllipse(in: circle(t0)) }
            if radius(t1) > 0 { ctx.addEllipse(in: circle(t1)) }
            ctx.fillPath(using: .evenOdd)
        }
        if options.contains(innerOption), radius(innerT) > 0 {
            _setFill(ctx, at: bigIsEnd ? _locations[0] : _locations[_locations.count - 1])
            ctx.fillEllipse(in: circle(innerT))
        }
        ctx.restoreGState()
    }
}
