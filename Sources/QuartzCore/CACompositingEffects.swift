// Offscreen passes of the software compositor: group opacity, blurred shadows and alpha
// masks all need the layer's subtree as pixels first. The pixels come from a bitmap
// CGContext (Apple's on macOS, ours over Direct2D or Cairo elsewhere), so this code is
// the same on every platform and the macOS tests cover it.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum _CAPixels {
    /// A premultiplied BGRA bitmap context, bottom-left origin, in pixel units.
    public static func makeContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                         bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    }

    /// The image's pixels as tightly packed BGRA rows, top row first.
    static func bgra(of image: CGImage) -> [UInt8] {
        #if os(Windows) || os(Linux)
        let data = image.data
        #else
        guard let d = image.dataProvider?.data else { return [] }
        let data = d as Data
        #endif
        let w = image.width, h = image.height, stride = image.bytesPerRow
        if stride == w * 4 { return [UInt8](data.prefix(w * h * 4)) }
        var out = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeBytes { src in
            for row in 0..<h { out.withUnsafeMutableBytes { dst in dst.baseAddress!.advanced(by: row * w * 4).copyMemory(from: src.baseAddress! + row * stride, byteCount: w * 4) } }
        }
        return out
    }

    /// An image over tightly packed premultiplied BGRA rows, top row first.
    static func image(width: Int, height: Int, bgra: [UInt8]) -> CGImage? {
        guard width > 0, height > 0, bgra.count >= width * height * 4 else { return nil }
        #if os(Windows) || os(Linux)
        return CGImage.fromBGRA(width: width, height: height, stride: width * 4, data: Data(bgra))
        #else
        guard let provider = CGDataProvider(data: Data(bgra) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        #endif
    }

    /// Renders `draw` into an offscreen covering `extent` (a layer's oriented bounds space)
    /// at `scale` pixels per point. With `yDown` the extent's minimum y is the top row, as
    /// in a flipped layer; otherwise its maximum y is.
    @MainActor
    public static func render(extent: CGRect, scale: (x: CGFloat, y: CGFloat), yDown: Bool, draw: (CGContext) -> Void) -> CGImage? {
        let pw = Int((extent.width * scale.x).rounded(.up)), ph = Int((extent.height * scale.y).rounded(.up))
        guard pw > 0, ph > 0, pw <= 8192, ph <= 8192, let off = makeContext(width: pw, height: ph) else { return nil }
        if yDown {
            off.translateBy(x: 0, y: CGFloat(ph))
            off.scaleBy(x: scale.x, y: -scale.y)
        } else {
            off.scaleBy(x: scale.x, y: scale.y)
        }
        off.translateBy(x: -extent.minX, y: -extent.minY)
        draw(off)
        return off.makeImage()
    }

    /// Draws an image rendered by `render` back over `rect` in a context of the same orientation.
    public static func blit(_ image: CGImage, into ctx: CGContext, rect: CGRect, yDown: Bool, alpha: CGFloat) {
        ctx.saveGState()
        ctx.setAlpha(alpha)
        if yDown {
            ctx.translateBy(x: 0, y: rect.minY + rect.maxY)
            ctx.scaleBy(x: 1, y: -1)
        }
        ctx.draw(image, in: rect)
        ctx.restoreGState()
    }

    /// Box sizes whose three passes approximate a Gaussian of standard deviation `sigma`.
    private static func boxes(forSigma sigma: Double) -> [Int] {
        let n = 3.0
        let wIdeal = (12 * sigma * sigma / n + 1).squareRoot()
        var wl = Int(wIdeal.rounded(.down))
        if wl % 2 == 0 { wl -= 1 }
        let wu = wl + 2
        let mIdeal = (12 * sigma * sigma - n * Double(wl * wl) - 4 * n * Double(wl) - 3 * n) / (-4 * Double(wl) - 4)
        let m = Int(mIdeal.rounded())
        return (0..<3).map { $0 < m ? wl : wu }
    }

    /// One box-blur pass along rows (running sum), then along columns.
    private static func boxBlur(_ src: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        guard radius > 0 else { return src }
        var tmp = [Float](repeating: 0, count: src.count)
        let norm = 1 / Float(2 * radius + 1)
        for y in 0..<height {
            let row = y * width
            var sum: Float = 0
            for x in -radius...radius { sum += src[row + min(max(x, 0), width - 1)] }
            for x in 0..<width {
                tmp[row + x] = sum * norm
                let leaving = src[row + max(x - radius, 0)]
                let entering = src[row + min(x + radius + 1, width - 1)]
                sum += entering - leaving
            }
        }
        var out = [Float](repeating: 0, count: src.count)
        for x in 0..<width {
            var sum: Float = 0
            for y in -radius...radius { sum += tmp[min(max(y, 0), height - 1) * width + x] }
            for y in 0..<height {
                out[y * width + x] = sum * norm
                let leaving = tmp[max(y - radius, 0) * width + x]
                let entering = tmp[min(y + radius + 1, height - 1) * width + x]
                sum += entering - leaving
            }
        }
        return out
    }

    /// The shadow of `content`: its alpha channel, padded by `pad` pixels on every side,
    /// blurred with standard deviation `sigma` pixels and tinted `color` (r, g, b, 0...1).
    static func shadow(of content: CGImage, pad: Int, sigma: CGFloat, color: (r: CGFloat, g: CGFloat, b: CGFloat)) -> CGImage? {
        let w = content.width, h = content.height
        let pixels = bgra(of: content)
        guard pixels.count >= w * h * 4 else { return nil }
        let w2 = w + 2 * pad, h2 = h + 2 * pad
        var alpha = [Float](repeating: 0, count: w2 * h2)
        for y in 0..<h {
            for x in 0..<w { alpha[(y + pad) * w2 + x + pad] = Float(pixels[(y * w + x) * 4 + 3]) / 255 }
        }
        if sigma > 0.2 {
            for box in boxes(forSigma: Double(sigma)) { alpha = boxBlur(alpha, width: w2, height: h2, radius: (box - 1) / 2) }
        }
        var out = [UInt8](repeating: 0, count: w2 * h2 * 4)
        let (r, g, b) = (Float(color.r), Float(color.g), Float(color.b))
        for i in 0..<(w2 * h2) {
            let a = min(1, max(0, alpha[i]))
            out[i * 4] = UInt8((b * a * 255).rounded())
            out[i * 4 + 1] = UInt8((g * a * 255).rounded())
            out[i * 4 + 2] = UInt8((r * a * 255).rounded())
            out[i * 4 + 3] = UInt8((a * 255).rounded())
        }
        return image(width: w2, height: h2, bgra: out)
    }

    /// `content` with every pixel scaled by the mask's alpha at the same position.
    static func masked(_ content: CGImage, by mask: CGImage) -> CGImage? {
        guard content.width == mask.width, content.height == mask.height else { return content }
        var pixels = bgra(of: content)
        let m = bgra(of: mask)
        guard pixels.count == m.count else { return content }
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = Int(m[i + 3])
            if a == 255 { continue }
            pixels[i] = UInt8(Int(pixels[i]) * a / 255)
            pixels[i + 1] = UInt8(Int(pixels[i + 1]) * a / 255)
            pixels[i + 2] = UInt8(Int(pixels[i + 2]) * a / 255)
            pixels[i + 3] = UInt8(Int(pixels[i + 3]) * a / 255)
        }
        return image(width: content.width, height: content.height, bgra: pixels)
    }
}
