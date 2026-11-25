// Template image tinting: AppKit draws a template image's alpha in the control's colour.
// The port's CoreGraphics backends have no transparency layers or source-atop blending on
// every platform, so the tint is applied to the pixels: the image is rendered once at the
// destination's pixel size and each pixel keeps its alpha and takes the colour. Hand-written
// support code, not AppKit API.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension NSImage {
    /// A bitmap image of this image's alpha filled with `color`, sized for `size` points at
    /// the current context's device scale (its user-to-device transform, which carries the
    /// window's backing scale); cached per colour and pixel size, so a backing-scale change
    /// renders afresh. Nil when it cannot be rendered.
    @MainActor internal func _tintedForTemplate(_ color: NSColor, size: NSSize) -> NSImage? {
        let backing = NSGraphicsContext.current.map { NSImage._deviceScale($0.cgContext, hints: nil) }
            ?? NSView.focusView?.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let base = self.size
        guard base.width > 0, base.height > 0, size.width > 0, size.height > 0 else { return nil }
        let scale = backing * max(size.width / base.width, size.height / base.height)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        let rgb = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) ?? NSColor.black
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        let key = "\(Int((r * 255).rounded())),\(Int((g * 255).rounded())),\(Int((b * 255).rounded())),\(Int((a * 255).rounded()))@\(Int((base.width * scale).rounded()))x\(Int((base.height * scale).rounded()))"
        if let cached = _tintCache[key] { return cached }
        guard let cg = _cgImage(scale: backing, fitting: size) else { return nil }
        let px = NSBitmapImageRep._rgbaPixels(of: cg)
        var bgra = [UInt8](repeating: 0, count: px.width * px.height * 4)
        let cr = Int((r * 255).rounded()), cgn = Int((g * 255).rounded()), cb = Int((b * 255).rounded())
        for p in 0..<(px.width * px.height) {
            let alpha = Int((Double(px.bytes[p * 4 + 3]) * Double(a)).rounded())
            bgra[p * 4] = UInt8((cb * alpha + 127) / 255)
            bgra[p * 4 + 1] = UInt8((cgn * alpha + 127) / 255)
            bgra[p * 4 + 2] = UInt8((cr * alpha + 127) / 255)
            bgra[p * 4 + 3] = UInt8(alpha)
        }
        guard let tinted = NSBitmapImageRep._makeBGRAImage(width: px.width, height: px.height, bytes: bgra) else { return nil }
        let image = NSImage(cgImage: tinted, size: base)
        if _tintCache.count > 16 { _tintCache.removeAll() }
        _tintCache[key] = image
        return image
    }
}
