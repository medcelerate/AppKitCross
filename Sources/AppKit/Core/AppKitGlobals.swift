// AppKit's global functions and constants that need code (ADR-0033).
//
// Plain constants (function keys, NSOKButton, font-panel masks, error codes, ...) are
// emitted by the generator with the values recorded from the SDK by tools/apigen/probe.sh.
// What is here is listed under `skipMembers` in tools/apigen/config.json, so _Globals.swift
// no longer declares it. The globals left in _Globals.swift call unimplemented(); ADR-0033
// says why each one is out of scope.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - Geometry

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdirectionaledgeinsetszero
@available(macOS 10.15, *)
public var NSDirectionalEdgeInsetsZero: NSDirectionalEdgeInsets { NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0) }

// MARK: - Rect drawing (NSRectFill and friends, spelled as CGRect methods in Swift)

extension CGRect {
    /// Fills the rectangle with the current fill colour using `operation` (NSRectFillUsingOperation).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrectfill(_:)
    public func fill(using operation: NSCompositingOperation = NSGraphicsContext.current?.compositingOperation ?? .sourceOver) {
        _withCompositing(operation) { $0.fill(self) }
    }

    /// Draws a frame `width` points wide just inside the rectangle (NSFrameRectWithWidthUsingOperation).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsframerect(_:)
    public func frame(withWidth width: CGFloat = 1.0, using operation: NSCompositingOperation = NSGraphicsContext.current?.compositingOperation ?? .sourceOver) {
        guard !isEmpty, width > 0 else { return }
        let w = Swift.min(width, self.width / 2, self.height / 2)
        _withCompositing(operation) { ctx in
            // Four bands inside the rect, filled with the fill colour as AppKit does.
            ctx.fill(CGRect(x: minX, y: minY, width: self.width, height: w))
            ctx.fill(CGRect(x: minX, y: maxY - w, width: self.width, height: w))
            ctx.fill(CGRect(x: minX, y: minY + w, width: w, height: self.height - 2 * w))
            ctx.fill(CGRect(x: maxX - w, y: minY + w, width: w, height: self.height - 2 * w))
        }
    }

    /// Intersects the current clip with the rectangle (NSRectClip).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrectclip(_:)
    public func clip() {
        NSGraphicsContext.current?.cgContext.clip(to: self)
    }

    private func _withCompositing(_ operation: NSCompositingOperation, _ body: (CGContext) -> Void) {
        guard let gc = NSGraphicsContext.current else { return }
        let previous = gc.compositingOperation
        if previous != operation { gc.compositingOperation = operation }
        body(gc.cgContext)
        if previous != operation { gc.compositingOperation = previous }
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nseraserect(_:)
public func NSEraseRect(_ rect: NSRect) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.saveGState()
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fill(rect)
    ctx.restoreGState()
}

/// Strokes a one-point dotted line just inside `rect` in the current stroke colour.
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdottedframerect(_:)
public func NSDottedFrameRect(_ rect: NSRect) {
    guard let ctx = NSGraphicsContext.current?.cgContext, rect.width >= 1, rect.height >= 1 else { return }
    ctx.saveGState()
    ctx.setLineWidth(1)
    ctx.setLineDash(phase: 0, lengths: [1, 1])
    ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
    ctx.restoreGState()
}

/// Fills `rect` with the window background colour.
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawwindowbackground(_:)
public func NSDrawWindowBackground(_ rect: NSRect) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.saveGState()
    ctx.setFillColor(NSColor.windowBackgroundColor.cgColor)
    ctx.fill(rect)
    ctx.restoreGState()
}

/// Slices one-point strips off `boundsRect`, one per entry of `sides`, filling each (clipped to
/// `clipRect`) with the matching colour; returns what is left.
private func _drawTiledRects(_ boundsRect: NSRect, _ clipRect: NSRect, _ count: Int,
                             side: (Int) -> NSRectEdge, color: (Int) -> CGColor) -> NSRect {
    var remainder = boundsRect
    let ctx = NSGraphicsContext.current?.cgContext
    for i in 0..<Swift.max(count, 0) {
        guard remainder.width > 0, remainder.height > 0 else { break }
        let slice: NSRect
        // NSRectEdge raw values: minX 0, minY 1, maxX 2, maxY 3 (CGRectEdge on macOS, the
        // corelibs enum elsewhere; the case names differ, the raw values do not).
        switch Int(side(i).rawValue) {
        case 0: slice = NSRect(x: remainder.minX, y: remainder.minY, width: 1, height: remainder.height)
                remainder = NSRect(x: remainder.minX + 1, y: remainder.minY, width: remainder.width - 1, height: remainder.height)
        case 1: slice = NSRect(x: remainder.minX, y: remainder.minY, width: remainder.width, height: 1)
                remainder = NSRect(x: remainder.minX, y: remainder.minY + 1, width: remainder.width, height: remainder.height - 1)
        case 2: slice = NSRect(x: remainder.maxX - 1, y: remainder.minY, width: 1, height: remainder.height)
                remainder = NSRect(x: remainder.minX, y: remainder.minY, width: remainder.width - 1, height: remainder.height)
        default: slice = NSRect(x: remainder.minX, y: remainder.maxY - 1, width: remainder.width, height: 1)
                remainder = NSRect(x: remainder.minX, y: remainder.minY, width: remainder.width, height: remainder.height - 1)
        }
        let visible = slice.intersection(clipRect)
        if let ctx, !visible.isNull, !visible.isEmpty {
            ctx.saveGState()
            ctx.setFillColor(color(i))
            ctx.fill(visible)
            ctx.restoreGState()
        }
    }
    return remainder
}

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawtiledrects(_:_:_:_:_:)
public func NSDrawTiledRects(_ boundsRect: NSRect, _ clipRect: NSRect, _ sides: UnsafePointer<NSRectEdge>, _ grays: UnsafePointer<CGFloat>, _ count: Int) -> NSRect {
    _drawTiledRects(boundsRect, clipRect, count, side: { sides[$0] }, color: { NSColor(white: grays[$0], alpha: 1).cgColor })
}

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawcolortiledrects(_:_:_:_:_:)
public func NSDrawColorTiledRects(_ boundsRect: NSRect, _ clipRect: NSRect, _ sides: UnsafePointer<NSRectEdge>, _ colors: AutoreleasingUnsafeMutablePointer<NSColor>, _ count: Int) -> NSRect {
    _drawTiledRects(boundsRect, clipRect, count, side: { sides[$0] }, color: { colors[$0].cgColor })
}

/// The classic bevels: strips of grey, outermost first, then a fill. `top` and `bottom` are
/// the visual edges, so they swap in a flipped context.
private enum _Bevel { case top, bottom, left, right }

private func _drawBevel(_ rect: NSRect, _ clipRect: NSRect, _ strips: [(_Bevel, CGFloat)], fill: CGFloat?) {
    let flipped = NSGraphicsContext.current?.isFlipped ?? false
    func edge(_ b: _Bevel) -> Int {
        switch b {
        case .left: return 0
        case .right: return 2
        case .top: return flipped ? 1 : 3
        case .bottom: return flipped ? 3 : 1
        }
    }
    let rest = _drawTiledRects(rect, clipRect, strips.count,
                               side: { _edge(rawValue: edge(strips[$0].0)) },
                               color: { NSColor(white: strips[$0].1, alpha: 1).cgColor })
    if let fill, let ctx = NSGraphicsContext.current?.cgContext {
        let visible = rest.intersection(clipRect)
        guard !visible.isNull, !visible.isEmpty else { return }
        ctx.saveGState()
        ctx.setFillColor(NSColor(white: fill, alpha: 1).cgColor)
        ctx.fill(visible)
        ctx.restoreGState()
    }
}

private func _edge(rawValue: Int) -> NSRectEdge {
    NSRectEdge(rawValue: NSRectEdge.RawValue(rawValue))!
}

private let _black: CGFloat = 0, _dark: CGFloat = 1.0 / 3, _light: CGFloat = 2.0 / 3, _white: CGFloat = 1

/// A raised button bezel: light top/left, dark bottom/right, light grey face.
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawbutton(_:_:)
public func NSDrawButton(_ rect: NSRect, _ clipRect: NSRect) {
    _drawBevel(rect, clipRect, [(.right, _black), (.bottom, _black), (.left, _white), (.top, _white),
                                (.right, _dark), (.bottom, _dark)], fill: _light)
}

/// A sunken bezel with a light grey face.
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawgraybezel(_:_:)
public func NSDrawGrayBezel(_ rect: NSRect, _ clipRect: NSRect) {
    _drawBevel(rect, clipRect, [(.right, _white), (.bottom, _white), (.left, _dark), (.top, _dark),
                                (.right, _light), (.bottom, _light), (.left, _black), (.top, _black)], fill: _light)
}

/// A sunken bezel with a white face (text fields).
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawwhitebezel(_:_:)
public func NSDrawWhiteBezel(_ rect: NSRect, _ clipRect: NSRect) {
    _drawBevel(rect, clipRect, [(.right, _white), (.bottom, _white), (.left, _dark), (.top, _dark),
                                (.right, _light), (.bottom, _light), (.left, _dark), (.top, _dark)], fill: _white)
}

/// A sunken bezel in dark greys.
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawdarkbezel(_:_:)
public func NSDrawDarkBezel(_ rect: NSRect, _ clipRect: NSRect) {
    _drawBevel(rect, clipRect, [(.right, _light), (.bottom, _light), (.left, _black), (.top, _black),
                                (.right, _dark), (.bottom, _dark), (.left, _black), (.top, _black)], fill: _dark)
}

/// A sunken bezel in light greys.
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawlightbezel(_:_:)
public func NSDrawLightBezel(_ rect: NSRect, _ clipRect: NSRect) {
    _drawBevel(rect, clipRect, [(.right, _white), (.bottom, _white), (.left, _dark), (.top, _dark),
                                (.right, _white), (.bottom, _white), (.left, _light), (.top, _light)], fill: _white)
}

/// An etched groove (box borders).
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawgroove(_:_:)
public func NSDrawGroove(_ rect: NSRect, _ clipRect: NSRect) {
    _drawBevel(rect, clipRect, [(.right, _white), (.bottom, _white), (.left, _dark), (.top, _dark),
                                (.right, _dark), (.bottom, _dark), (.left, _white), (.top, _white)], fill: _light)
}

// MARK: - Images

/// Draws a raw bitmap (8 bits per sample, 1 to 4 samples, meshed or planar) into `rect`.
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawbitmap(_:_:_:_:_:_:_:_:_:_:_:)
public func NSDrawBitmap(_ rect: NSRect, _ width: Int, _ height: Int, _ bps: Int, _ spp: Int, _ bpp: Int, _ bpr: Int, _ isPlanar: Bool, _ hasAlpha: Bool, _ colorSpaceName: NSColorSpaceName, _ data: UnsafePointer<UnsafePointer<UInt8>?>) {
    guard let ctx = NSGraphicsContext.current?.cgContext, width > 0, height > 0, bps == 8, (1...5).contains(spp) else { return }
    let colorSamples = spp - (hasAlpha ? 1 : 0)
    let gray = colorSamples == 1
    // CMYK names (and anything else that is neither grey nor RGB) are not converted.
    let rgbNames: Set<String> = [NSColorSpaceName.calibratedRGB.rawValue, NSColorSpaceName.deviceRGB.rawValue]
    let grayNames: Set<String> = [NSColorSpaceName.calibratedWhite.rawValue, NSColorSpaceName.deviceWhite.rawValue]
    let isBlack = colorSpaceName.rawValue.contains("Black")
    guard (gray && (grayNames.contains(colorSpaceName.rawValue) || isBlack)) || (colorSamples == 3 && rgbNames.contains(colorSpaceName.rawValue)) else { return }
    let rowBytes = bpr > 0 ? bpr : (isPlanar ? width : width * (bpp > 0 ? bpp / 8 : spp))
    let pixelBytes = isPlanar ? 1 : (bpp > 0 ? bpp / 8 : spp)
    func sample(_ x: Int, _ y: Int, _ s: Int) -> CGFloat {
        let plane = isPlanar ? data[s] : data[0]
        guard let plane else { return 0 }
        let v = plane[y * rowBytes + x * pixelBytes + (isPlanar ? 0 : s)]
        return CGFloat(v) / 255
    }
    // Premultiplied BGRA, top row first.
    var out = Data(count: width * height * 4)
    out.withUnsafeMutableBytes { raw in
        let p = raw.bindMemory(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                var r: CGFloat, g: CGFloat, b: CGFloat
                if gray {
                    var w = sample(x, y, 0)
                    if isBlack { w = 1 - w }
                    (r, g, b) = (w, w, w)
                } else {
                    (r, g, b) = (sample(x, y, 0), sample(x, y, 1), sample(x, y, 2))
                }
                let a = hasAlpha ? sample(x, y, colorSamples) : 1
                // AppKit bitmaps are premultiplied unless flagged otherwise.
                let i = (y * width + x) * 4
                p[i] = UInt8((b * 255).rounded()); p[i + 1] = UInt8((g * 255).rounded())
                p[i + 2] = UInt8((r * 255).rounded()); p[i + 3] = UInt8((a * 255).rounded())
            }
        }
    }
    guard let image = _cgImageFromBGRA(width: width, height: height, data: out) else { return }
    ctx.draw(image, in: rect)
}

/// A CGImage over premultiplied BGRA rows, top row first.
internal func _cgImageFromBGRA(width: Int, height: Int, data: Data) -> CGImage? {
    #if os(Windows) || os(Linux)
    return CGImage.fromBGRA(width: width, height: height, stride: width * 4, data: data)
    #else
    guard let provider = CGDataProvider(data: data as CFData) else { return nil }
    let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info, provider: provider,
                   decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    #endif
}

/// The colour of the pixel under `passedPoint` (user space) in the current context, read
/// back from its backing; nil when there is no current context or it has no readable pixels
/// (a Win32 window target outside a bitmap context).
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsreadpixel(_:)
public func NSReadPixel(_ passedPoint: NSPoint) -> NSColor? {
    guard let ctx = NSGraphicsContext.current?.cgContext, let image = ctx.makeImage() else { return nil }
    // Device space is y-up from the bottom-left on every backend; image rows run top first.
    let device = passedPoint.applying(ctx.ctm)
    let x = Int(device.x.rounded(.down)), y = image.height - 1 - Int(device.y.rounded(.down))
    return NSBitmapImageRep(cgImage: image).colorAt(x: x, y: y)
}

/// Draws an image made of two end caps and a stretched centre.
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawthreepartimage(_:_:_:_:_:_:_:_:)
public func NSDrawThreePartImage(_ frame: NSRect, _ startCap: NSImage?, _ centerFill: NSImage?, _ endCap: NSImage?, _ vertical: Bool, _ op: NSCompositingOperation, _ alphaFraction: CGFloat, _ flipped: Bool) {
    guard !frame.isEmpty else { return }
    let start = startCap?.size ?? .zero, end = endCap?.size ?? .zero
    // In a flipped context the start cap (top for vertical images) sits at minY.
    let topDown = flipped || (NSGraphicsContext.current?.isFlipped ?? false)
    func draw(_ image: NSImage?, _ r: NSRect) {
        guard let image, !r.isEmpty else { return }
        image.draw(in: r, from: .zero, operation: op, fraction: alphaFraction, respectFlipped: true, hints: nil)
    }
    if vertical {
        let sh = Swift.min(start.height, frame.height), eh = Swift.min(end.height, frame.height - sh)
        let startRect = NSRect(x: frame.minX, y: topDown ? frame.minY : frame.maxY - sh, width: frame.width, height: sh)
        let endRect = NSRect(x: frame.minX, y: topDown ? frame.maxY - eh : frame.minY, width: frame.width, height: eh)
        draw(startCap, startRect)
        draw(centerFill, NSRect(x: frame.minX, y: frame.minY + (topDown ? sh : eh), width: frame.width, height: frame.height - sh - eh))
        draw(endCap, endRect)
    } else {
        let sw = Swift.min(start.width, frame.width), ew = Swift.min(end.width, frame.width - sw)
        draw(startCap, NSRect(x: frame.minX, y: frame.minY, width: sw, height: frame.height))
        draw(centerFill, NSRect(x: frame.minX + sw, y: frame.minY, width: frame.width - sw - ew, height: frame.height))
        draw(endCap, NSRect(x: frame.maxX - ew, y: frame.minY, width: ew, height: frame.height))
    }
}

/// Draws an image made of four corners at their natural size, four stretched edges and a
/// stretched centre.
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawninepartimage(_:_:_:_:_:_:_:_:_:_:_:_:_:)
public func NSDrawNinePartImage(_ frame: NSRect, _ topLeftCorner: NSImage?, _ topEdgeFill: NSImage?, _ topRightCorner: NSImage?, _ leftEdgeFill: NSImage?, _ centerFill: NSImage?, _ rightEdgeFill: NSImage?, _ bottomLeftCorner: NSImage?, _ bottomEdgeFill: NSImage?, _ bottomRightCorner: NSImage?, _ op: NSCompositingOperation, _ alphaFraction: CGFloat, _ flipped: Bool) {
    guard !frame.isEmpty else { return }
    let topDown = flipped || (NSGraphicsContext.current?.isFlipped ?? false)
    let tl = topLeftCorner?.size ?? .zero, br = bottomRightCorner?.size ?? .zero
    let left = Swift.min(tl.width, frame.width), right = Swift.min(br.width, frame.width - left)
    let top = Swift.min(tl.height, frame.height), bottom = Swift.min(br.height, frame.height - top)
    let midW = frame.width - left - right, midH = frame.height - top - bottom
    // Row origins in this context's y direction.
    let topY = topDown ? frame.minY : frame.maxY - top
    let midY = topDown ? frame.minY + top : frame.minY + bottom
    let bottomY = topDown ? frame.maxY - bottom : frame.minY
    let cols: [(CGFloat, CGFloat)] = [(frame.minX, left), (frame.minX + left, midW), (frame.maxX - right, right)]
    let rows: [(CGFloat, CGFloat)] = [(topY, top), (midY, midH), (bottomY, bottom)]
    let images: [[NSImage?]] = [[topLeftCorner, topEdgeFill, topRightCorner],
                                [leftEdgeFill, centerFill, rightEdgeFill],
                                [bottomLeftCorner, bottomEdgeFill, bottomRightCorner]]
    for (ri, row) in rows.enumerated() {
        for (ci, col) in cols.enumerated() {
            guard let image = images[ri][ci], col.1 > 0, row.1 > 0 else { continue }
            image.draw(in: NSRect(x: col.0, y: row.0, width: col.1, height: row.1), from: .zero,
                       operation: op, fraction: alphaFraction, respectFlipped: true, hints: nil)
        }
    }
}

// MARK: - Screen updates

/// Nesting count of NSDisableScreenUpdates calls not yet balanced.
nonisolated(unsafe) internal var _NSScreenUpdatesDisabledCount = 0

/// Holds back screen updates until the matching NSEnableScreenUpdates. Every backend here
/// presents a window's frame in one piece after its display pass, so there are no partial
/// updates to hold back: the calls only keep count (as on macOS 10.11 and later, where the
/// window server coalesces updates itself).
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdisablescreenupdates()
public func NSDisableScreenUpdates() { _NSScreenUpdatesDisabledCount += 1 }

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsenablescreenupdates()
public func NSEnableScreenUpdates() { _NSScreenUpdatesDisabledCount = Swift.max(0, _NSScreenUpdatesDisabledCount - 1) }

// MARK: - Glyphs

/// Packs 32-bit glyphs into 16-bit native-endian shorts (the only packing, `.nativeShortGlyphPacking`);
/// returns the number of bytes written.
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsconvertglyphstopackedglyphs(_:_:_:_:)
public func NSConvertGlyphsToPackedGlyphs(_ glBuf: UnsafeMutablePointer<NSGlyph>, _ count: Int, _ packing: NSMultibyteGlyphPacking, _ packedGlyphs: UnsafeMutablePointer<CChar>) -> Int {
    var written = 0
    let raw = UnsafeMutableRawPointer(packedGlyphs)
    for i in 0..<Swift.max(count, 0) {
        let g = UInt16(truncatingIfNeeded: glBuf[i])
        raw.storeBytes(of: g, toByteOffset: written, as: UInt16.self)
        written += 2
    }
    return written
}

// MARK: - Alert panels

/// Disposes of a panel from NSGetAlertPanel: closes it if it is still around.
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsreleasealertpanel(_:)
public func NSReleaseAlertPanel(_ panel: Any!) {
    guard let panel = panel as? NSWindow else { return }
    MainActor.assumeIsolated { panel.close() }
}

// MARK: - Bindings markers

/// The selection markers a controller hands out in place of a value.
private final class _NSBindingsMarker: NSObject, @unchecked Sendable {
    let name: String
    init(_ name: String) { self.name = name }
    override var description: String { name }
    static let multipleValues = _NSBindingsMarker("<MULTIPLE VALUES MARKER>")
    static let noSelection = _NSBindingsMarker("<NO SELECTION MARKER>")
    static let notApplicable = _NSBindingsMarker("<NOT APPLICABLE MARKER>")
}

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmultiplevaluesmarker
public var NSMultipleValuesMarker: AnyObject { _NSBindingsMarker.multipleValues }
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsnoselectionmarker
public var NSNoSelectionMarker: AnyObject { _NSBindingsMarker.noSelection }
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsnotapplicablemarker
public var NSNotApplicableMarker: AnyObject { _NSBindingsMarker.notApplicable }

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsiscontrollermarker(_:)
public func NSIsControllerMarker(_ object: Any?) -> Bool {
    guard let object = object as AnyObject? else { return false }
    return object === _NSBindingsMarker.multipleValues || object === _NSBindingsMarker.noSelection
        || object === _NSBindingsMarker.notApplicable
}
