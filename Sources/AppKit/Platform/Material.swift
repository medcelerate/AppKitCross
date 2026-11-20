// Material backend (ADR-0052, Liquid Glass): the pixel work behind the in-window glass
// pass, in two stages a GPU backend can take over one at a time.
//
// 1. Backdrop stage, `blur`: Core samples what the window drew beneath a glass rectangle
//    (plus a margin) into an offscreen surface at a fraction of the backing scale and hands
//    the pixels here to be blurred (a Gaussian approximation) and saturated.
// 2. Lens stage, `shade`: at the backing scale, every output pixel of the glass shape
//    looks the blurred backdrop up through the lens: a displacement toward the rim where
//    the shape's edge bends the light (refraction), the veil and tint over it, a specular
//    highlight where a fixed light catches the bevel, the thin inner rim (light where the
//    edge faces the light, dark opposite). The shape is a signed distance field: analytic
//    for a rounded rectangle or capsule, a distance transform of a coverage mask for any
//    other outline (SwiftUI's `glassEffect(in:)`).
//
// Every backend ships the software pipeline below; one with a GPU compositor (Direct2D or
// D3D12 on Windows, Vulkan on Linux, Metal on the host) overrides `material` on its
// `PlatformBackend` with the same stages as shader passes without Core knowing. The ADR
// gives the per-pixel program in shader form.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Blurs and shades the pixels behind a glass surface. `blur` is the one requirement; the
/// lens stage and the luminance probe have software defaults a backend may replace.
@MainActor
public protocol PlatformMaterialBackend: AnyObject {
    /// `image` blurred by about `radius` pixels (a Gaussian approximation; the edges clamp
    /// to the border pixels) with its colours saturated by `saturation` (1 leaves them).
    /// Returns `image` itself when there is nothing to do, nil when the pixels cannot be
    /// read back.
    func blur(_ image: CGImage, radius: Int, saturation: CGFloat) -> CGImage?
    /// The glass shape shaded over `backdrop`: an image of `parameters.width` by
    /// `parameters.height` premultiplied pixels (top row first), transparent outside the
    /// shape. `backdropRect` places the backdrop image in the output's pixel space (it
    /// extends beyond the output by the blur margin).
    func shade(_ backdrop: CGImage, in backdropRect: CGRect, shape: PlatformGlassShape, parameters: PlatformGlassParameters) -> CGImage?
    /// The alpha-weighted mean luminance (0 dark, 1 light) of `image`, nil when it has
    /// no opaque pixel.
    func averageLuminance(_ image: CGImage) -> CGFloat?
}

extension PlatformMaterialBackend {
    /// The blur without saturation.
    public func blur(_ image: CGImage, radius: Int) -> CGImage? { blur(image, radius: radius, saturation: 1) }
}

extension PlatformBackend {
    /// The material pass every backend gets unless it provides its own.
    public var material: any PlatformMaterialBackend { SoftwareMaterialBackend.shared }
}

/// The outline of a glass surface in the output's pixel space (top row first).
public enum PlatformGlassShape {
    /// A rounded rectangle; a radius of half the smaller side makes a capsule.
    case roundedRect(CGRect, cornerRadius: CGFloat)
    /// Any outline, as a coverage mask the size of the output: the alpha channel of a
    /// 32-bit image, 255 inside the shape.
    case coverage(CGImage)
}

/// What the lens stage draws. Lengths are in output pixels, colours straight (not
/// premultiplied) sRGB components in 0...1.
public struct PlatformGlassParameters: Hashable, Sendable {
    public struct Color: Hashable, Sendable {
        public var red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat
        public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
            self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
        }
        public static let white = Color(red: 1, green: 1, blue: 1)
    }
    /// The output size.
    public var width: Int
    public var height: Int
    /// The veil over the blurred backdrop and how much of it.
    public var veil = Color.white
    public var veilAlpha: CGFloat = 0.4
    /// A tint mixed in over the veil (its own alpha scales `tintAlpha`).
    public var tint: Color?
    public var tintAlpha: CGFloat = 0.5
    /// The bevel: how far inside the edge the lens bends the backdrop, and by how many
    /// pixels at the rim (0 for a flat material).
    public var edgeWidth: CGFloat = 0
    public var refraction: CGFloat = 0
    /// The inner rim line's width and strength (0 for none).
    public var rimWidth: CGFloat = 0
    public var rimAlpha: CGFloat = 0
    /// The specular sheen on the bevel facing the light (0 for none).
    public var specular: CGFloat = 0
    /// Where the light is, as a direction in output pixel space (y down): the default is
    /// above and a little to the left.
    public var lightX: CGFloat = -0.3
    public var lightY: CGFloat = -1
    /// A lift toward white over the whole shape (interactive hover and press).
    public var brighten: CGFloat = 0

    public init(width: Int, height: Int) { self.width = width; self.height = height }
}

/// The software pipeline: three separable box blurs in place of a Gaussian (the classic
/// approximation) on 32-bit premultiplied pixels, then the lens pass over an analytic or
/// transformed distance field. The backdrop is sampled at a quarter of the backing scale,
/// so a toolbar band or sidebar column is a few hundred by a few dozen pixels there; the
/// lens pass runs at the backing scale over the shape alone.
@MainActor
public final class SoftwareMaterialBackend: PlatformMaterialBackend {
    public static let shared = SoftwareMaterialBackend()
    public init() {}

    public func blur(_ image: CGImage, radius: Int, saturation: CGFloat) -> CGImage? {
        guard radius > 0 || saturation != 1 else { return image }
        guard var pixels = _MaterialPixels(image) else { return nil }
        if radius > 0 {
            // Three passes of radius r approximate a Gaussian of sigma ~ r; `radius` is the
            // visual blur (about 2 sigma), so each pass runs at half of it.
            let r = max(1, (radius + 1) / 2)
            var scratch = [UInt8](repeating: 0, count: pixels.bytes.count)
            for _ in 0..<3 {
                _MaterialPixels.box(pixels.bytes, into: &scratch, width: pixels.width, height: pixels.height, stride: pixels.stride, radius: r, horizontal: true)
                _MaterialPixels.box(scratch, into: &pixels.bytes, width: pixels.width, height: pixels.height, stride: pixels.stride, radius: r, horizontal: false)
            }
        }
        if saturation != 1 { pixels.saturate(by: saturation) }
        return pixels.makeImage()
    }

    public func averageLuminance(_ image: CGImage) -> CGFloat? {
        guard let pixels = _MaterialPixels(image) else { return nil }
        return pixels.averageLuminance()
    }

    public func shade(_ backdrop: CGImage, in backdropRect: CGRect, shape: PlatformGlassShape, parameters p: PlatformGlassParameters) -> CGImage? {
        guard p.width > 0, p.height > 0, let source = _MaterialPixels(backdrop) else { return nil }
        guard let field = _GlassField(shape, width: p.width, height: p.height) else { return nil }
        var out = _MaterialPixels(width: p.width, height: p.height, template: backdrop)
        let lightLength = max(1e-6, (p.lightX * p.lightX + p.lightY * p.lightY).squareRoot())
        let lx = Float(p.lightX / lightLength), ly = Float(p.lightY / lightLength)
        let sx = Float(source.width) / Float(max(1e-6, backdropRect.width)), sy = Float(source.height) / Float(max(1e-6, backdropRect.height))
        let ox = Float(backdropRect.minX), oy = Float(backdropRect.minY)
        let veil = p.veil, veilA = Float(p.veilAlpha)
        let tint = p.tint, tintA = Float(p.tintAlpha) * Float(p.tint?.alpha ?? 0)
        let edge = Float(max(0.001, p.edgeWidth)), refraction = Float(p.refraction)
        let rimW = Float(max(0.001, p.rimWidth)), rimA = Float(p.rimAlpha), spec = Float(p.specular), lift = Float(p.brighten)
        source.bytes.withUnsafeBufferPointer { src in
            out.bytes.withUnsafeMutableBufferPointer { dst in
                for y in 0..<p.height {
                    for x in 0..<p.width {
                        let (d, nx, ny) = field.sample(x, y)
                        // Antialiased coverage of the shape at this pixel: 1 inside, 0 outside.
                        let cover = min(1, max(0, 0.5 - d))
                        let o = y * out.stride + x * 4
                        if cover <= 0 { dst[o] = 0; dst[o + 1] = 0; dst[o + 2] = 0; dst[o + 3] = 0; continue }
                        // The bevel: t is 1 at the rim, 0 edgeWidth inside; the lens looks
                        // outward through it, so content beyond the edge bends into the rim.
                        let t = p.edgeWidth > 0 ? min(1, max(0, 1 + d / edge)) : 0
                        let bend = refraction * t * t
                        let px = Float(x) + 0.5 + nx * bend, py = Float(y) + 0.5 + ny * bend
                        var (b, g, r, a) = _MaterialPixels.bilinear(src, width: source.width, height: source.height, stride: source.stride, x: (px - ox) * sx - 0.5, y: (py - oy) * sy - 0.5)
                        if a > 0.001 { b /= a; g /= a; r /= a }
                        // Veil, then tint, over the backdrop.
                        r += (Float(veil.red) - r) * veilA; g += (Float(veil.green) - g) * veilA; b += (Float(veil.blue) - b) * veilA
                        a += (1 - a) * veilA
                        if let tint, tintA > 0 {
                            r += (Float(tint.red) - r) * tintA; g += (Float(tint.green) - g) * tintA; b += (Float(tint.blue) - b) * tintA
                            a += (1 - a) * tintA
                        }
                        // Lighting on the bevel: the rim line and the specular sheen.
                        let facing = nx * lx + ny * ly
                        if rimA > 0 {
                            let rim = min(1, max(0, 1 + d / rimW)) * rimA
                            if facing > 0 {
                                let k = rim * facing
                                r += (1 - r) * k; g += (1 - g) * k; b += (1 - b) * k
                            } else {
                                let k = rim * -facing * 0.45
                                r *= 1 - k; g *= 1 - k; b *= 1 - k
                            }
                            a += (1 - a) * rim
                        }
                        if spec > 0, facing > 0, t > 0 {
                            let f2 = facing * facing
                            let k = f2 * f2 * t * spec
                            r += (1 - r) * k; g += (1 - g) * k; b += (1 - b) * k
                        }
                        if lift > 0 { r += (1 - r) * lift; g += (1 - g) * lift; b += (1 - b) * lift }
                        let outA = min(1, a) * cover
                        dst[o] = _MaterialPixels.byte(b * outA); dst[o + 1] = _MaterialPixels.byte(g * outA)
                        dst[o + 2] = _MaterialPixels.byte(r * outA); dst[o + 3] = _MaterialPixels.byte(outA)
                    }
                }
            }
        }
        return out.makeImage()
    }
}

/// The signed distance to a glass outline, in output pixels (negative inside), with the
/// outward normal: analytic for a rounded rectangle, a chamfer distance transform of the
/// coverage mask for any other shape.
struct _GlassField {
    private let rect: CGRect?
    private let radius: Float
    private let distances: [Float]
    private let width: Int, height: Int

    init?(_ shape: PlatformGlassShape, width: Int, height: Int) {
        self.width = width; self.height = height
        switch shape {
        case .roundedRect(let r, let cornerRadius):
            rect = r; radius = Float(min(cornerRadius, r.width / 2, r.height / 2)); distances = []
        case .coverage(let image):
            guard let mask = _MaterialPixels(image), mask.width == width, mask.height == height else { return nil }
            rect = nil; radius = 0
            distances = _GlassField.distanceTransform(mask)
        }
    }

    /// Distance and normal at the centre of pixel (x, y).
    @inline(__always)
    func sample(_ x: Int, _ y: Int) -> (Float, Float, Float) {
        if let rect {
            let cx = Float(rect.midX), cy = Float(rect.midY), hx = Float(rect.width) / 2 - radius, hy = Float(rect.height) / 2 - radius
            let dx = Float(x) + 0.5 - cx, dy = Float(y) + 0.5 - cy
            let qx = abs(dx) - hx, qy = abs(dy) - hy
            let ox = max(qx, 0), oy = max(qy, 0)
            let outside = (ox * ox + oy * oy).squareRoot()
            let d = outside + min(max(qx, qy), 0) - radius
            var nx: Float, ny: Float
            if outside > 1e-5 {
                nx = ox / outside * (dx < 0 ? -1 : 1); ny = oy / outside * (dy < 0 ? -1 : 1)
            } else if qx > qy {
                nx = dx < 0 ? -1 : 1; ny = 0
            } else {
                nx = 0; ny = dy < 0 ? -1 : 1
            }
            return (d, nx, ny)
        }
        let d = distances[y * width + x]
        // The normal from central differences of the field.
        let l = distances[y * width + max(0, x - 1)], r = distances[y * width + min(width - 1, x + 1)]
        let u = distances[max(0, y - 1) * width + x], b = distances[min(height - 1, y + 1) * width + x]
        var nx = r - l, ny = b - u
        let n = (nx * nx + ny * ny).squareRoot()
        if n > 1e-5 { nx /= n; ny /= n } else { nx = 0; ny = -1 }
        return (d, nx, ny)
    }

    /// The signed distance (negative inside) from the mask's alpha with a two-pass
    /// chamfer transform (3-4 weights over 3), good to a fraction of a pixel at the rim; a
    /// partly covered boundary pixel takes its coverage as the distance.
    static func distanceTransform(_ mask: _MaterialPixels) -> [Float] {
        let w = mask.width, h = mask.height
        let far: Float = 1e6
        // `toOutside` seeds the outside pixels with 0 and grows inward; `toInside` the reverse.
        var toOutside = [Float](repeating: far, count: w * h), toInside = [Float](repeating: far, count: w * h)
        var alpha = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let a = mask.bytes[y * mask.stride + x * 4 + 3]
                alpha[y * w + x] = a
                if a >= 128 { toInside[y * w + x] = 0 } else { toOutside[y * w + x] = 0 }
            }
        }
        func chamfer(_ f: inout [Float]) {
            let d1: Float = 1, d2: Float = 4.0 / 3.0
            for y in 0..<h {
                for x in 0..<w {
                    var v = f[y * w + x]
                    if x > 0 { v = min(v, f[y * w + x - 1] + d1) }
                    if y > 0 {
                        v = min(v, f[(y - 1) * w + x] + d1)
                        if x > 0 { v = min(v, f[(y - 1) * w + x - 1] + d2) }
                        if x < w - 1 { v = min(v, f[(y - 1) * w + x + 1] + d2) }
                    }
                    f[y * w + x] = v
                }
            }
            for y in stride(from: h - 1, through: 0, by: -1) {
                for x in stride(from: w - 1, through: 0, by: -1) {
                    var v = f[y * w + x]
                    if x < w - 1 { v = min(v, f[y * w + x + 1] + d1) }
                    if y < h - 1 {
                        v = min(v, f[(y + 1) * w + x] + d1)
                        if x > 0 { v = min(v, f[(y + 1) * w + x - 1] + d2) }
                        if x < w - 1 { v = min(v, f[(y + 1) * w + x + 1] + d2) }
                    }
                    f[y * w + x] = v
                }
            }
        }
        chamfer(&toOutside); chamfer(&toInside)
        var d = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let a = alpha[i]
            if a > 0 && a < 255 { d[i] = 0.5 - Float(a) / 255 }
            else if a >= 128 { d[i] = -(min(toOutside[i], far) - 0.5) }
            else { d[i] = min(toInside[i], far) - 0.5 }
        }
        return d
    }
}

/// The 32-bit pixel rows of a bitmap image, top row first, with the layout the offscreen
/// surfaces produce on every backend: premultiplied BGRA (Direct2D, cairo and the macOS
/// host's bitmap context alike).
struct _MaterialPixels {
    var bytes: [UInt8]
    let width: Int
    let height: Int
    let stride: Int
    let template: CGImage

    init(bytes: [UInt8], width: Int, height: Int, stride: Int, template: CGImage) {
        self.bytes = bytes; self.width = width; self.height = height; self.stride = stride; self.template = template
    }

    init?(_ image: CGImage) {
        guard image.bitsPerPixel == 32, image.width > 0, image.height > 0 else { return nil }
        #if os(Windows) || os(Linux)
        let data = image.data
        #else
        guard let provider = image.dataProvider, let cf = provider.data else { return nil }
        let data = cf as Data
        #endif
        guard data.count >= image.bytesPerRow * image.height else { return nil }
        bytes = [UInt8](data.prefix(image.bytesPerRow * image.height))
        width = image.width; height = image.height; stride = image.bytesPerRow
        template = image
    }

    /// Blank pixels of `template`'s format.
    init(width: Int, height: Int, template: CGImage) {
        self.width = width; self.height = height; stride = width * 4
        bytes = [UInt8](repeating: 0, count: stride * height)
        self.template = template
    }

    /// The pixels as an image of the template's format.
    func makeImage() -> CGImage? {
        #if os(Windows) || os(Linux)
        return CGImage.fromBGRA(width: width, height: height, stride: stride, data: Data(bytes))
        #else
        guard let space = template.colorSpace,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: template.bitsPerComponent, bytesPerRow: stride, space: space, bitmapInfo: template.bitmapInfo.rawValue),
              let dst = ctx.data else { return nil }
        bytes.withUnsafeBytes { src in
            _ = memcpy(dst, src.baseAddress, min(src.count, ctx.bytesPerRow * height))
        }
        return ctx.makeImage()
        #endif
    }

    @inline(__always) static func byte(_ v: Float) -> UInt8 { UInt8(min(255, max(0, (v * 255).rounded()))) }

    /// The premultiplied (b, g, r, a) in 0...1 at a fractional pixel position, bilinear,
    /// clamped to the border.
    @inline(__always)
    static func bilinear(_ s: UnsafeBufferPointer<UInt8>, width: Int, height: Int, stride: Int, x: Float, y: Float) -> (Float, Float, Float, Float) {
        let cx = min(Float(width - 1), max(0, x)), cy = min(Float(height - 1), max(0, y))
        let x0 = Int(cx), y0 = Int(cy)
        let x1 = min(width - 1, x0 + 1), y1 = min(height - 1, y0 + 1)
        let fx = cx - Float(x0), fy = cy - Float(y0)
        @inline(__always) func at(_ xx: Int, _ yy: Int, _ c: Int) -> Float { Float(s[yy * stride + xx * 4 + c]) / 255 }
        var out: (Float, Float, Float, Float) = (0, 0, 0, 0)
        for c in 0..<4 {
            let top = at(x0, y0, c) + (at(x1, y0, c) - at(x0, y0, c)) * fx
            let bottom = at(x0, y1, c) + (at(x1, y1, c) - at(x0, y1, c)) * fx
            let v = top + (bottom - top) * fy
            switch c { case 0: out.0 = v; case 1: out.1 = v; case 2: out.2 = v; default: out.3 = v }
        }
        return out
    }

    /// Saturation: every colour pulled away from (above 1) or toward (below 1) its luminance.
    mutating func saturate(by s: CGFloat) {
        let k = Float(s)
        for y in 0..<height {
            for x in 0..<width {
                let o = y * stride + x * 4
                let b = Float(bytes[o]), g = Float(bytes[o + 1]), r = Float(bytes[o + 2]), a = Float(bytes[o + 3])
                let l = 0.0722 * b + 0.7152 * g + 0.2126 * r
                // Premultiplied values stay within 0...alpha.
                bytes[o] = UInt8(min(a, max(0, (l + (b - l) * k).rounded())))
                bytes[o + 1] = UInt8(min(a, max(0, (l + (g - l) * k).rounded())))
                bytes[o + 2] = UInt8(min(a, max(0, (l + (r - l) * k).rounded())))
            }
        }
    }

    /// The alpha-weighted mean luminance of the straight colours, nil for no coverage.
    func averageLuminance() -> CGFloat? {
        var sum: Double = 0, weight: Double = 0
        for y in 0..<height {
            for x in 0..<width {
                let o = y * stride + x * 4
                let a = Double(bytes[o + 3])
                guard a > 0 else { continue }
                // Premultiplied: luma / alpha is the straight luma; the weight is alpha.
                sum += 0.0722 * Double(bytes[o]) + 0.7152 * Double(bytes[o + 1]) + 0.2126 * Double(bytes[o + 2])
                weight += a
            }
        }
        return weight > 0 ? CGFloat(sum / weight) : nil
    }

    /// Whether at least `fraction` of the pixels are within `tolerance` of `color`
    /// (straight sRGB components): a sample that holds nothing but the window background.
    func mostly(_ color: PlatformGlassParameters.Color, tolerance: Int = 6, fraction: Double = 0.97) -> Bool {
        let cb = Int(color.blue * 255), cg = Int(color.green * 255), cr = Int(color.red * 255)
        var hits = 0
        for y in 0..<height {
            for x in 0..<width {
                let o = y * stride + x * 4
                let a = Int(bytes[o + 3])
                guard a > 0 else { continue }
                if abs(Int(bytes[o]) * 255 / a - cb) <= tolerance, abs(Int(bytes[o + 1]) * 255 / a - cg) <= tolerance, abs(Int(bytes[o + 2]) * 255 / a - cr) <= tolerance { hits += 1 }
            }
        }
        return Double(hits) >= fraction * Double(width * height)
    }

    /// The rows in reverse order: the strip beyond an edge mirrored into the surface.
    func flippedVertically() -> _MaterialPixels {
        var copy = self
        for y in 0..<height {
            let src = (height - 1 - y) * stride
            copy.bytes.replaceSubrange(y * stride..<(y * stride + stride), with: bytes[src..<(src + stride)])
        }
        return copy
    }

    /// One box-blur pass of `radius` along rows (`horizontal`) or columns, every byte of
    /// each pixel averaged over `2 * radius + 1` samples with the border clamped.
    static func box(_ src: [UInt8], into dst: inout [UInt8], width: Int, height: Int, stride: Int, radius: Int, horizontal: Bool) {
        let length = horizontal ? width : height
        let lines = horizontal ? height : width
        let stepIn = horizontal ? 4 : stride
        let lineIn = horizontal ? stride : 4
        let window = 2 * radius + 1
        src.withUnsafeBufferPointer { s in
            dst.withUnsafeMutableBufferPointer { d in
                for line in 0..<lines {
                    let base = line * lineIn
                    for c in 0..<4 {
                        // The running sum starts with the first pixel repeated `radius`
                        // times plus the first `radius + 1` pixels.
                        var sum = 0
                        let first = Int(s[base + c])
                        sum += first * radius
                        for i in 0...min(radius, length - 1) { sum += Int(s[base + i * stepIn + c]) }
                        if length - 1 < radius { sum += Int(s[base + (length - 1) * stepIn + c]) * (radius - (length - 1)) }
                        for i in 0..<length {
                            d[base + i * stepIn + c] = UInt8(sum / window)
                            let leaving = max(0, i - radius)
                            let entering = min(length - 1, i + radius + 1)
                            sum += Int(s[base + entering * stepIn + c]) - Int(s[base + leaving * stepIn + c])
                        }
                    }
                }
            }
        }
    }
}
