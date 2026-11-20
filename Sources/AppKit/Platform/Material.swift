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
        let veilR = Float(p.veil.red), veilG = Float(p.veil.green), veilB = Float(p.veil.blue), veilA = Float(p.veilAlpha)
        let tintA = Float(p.tintAlpha) * Float(p.tint?.alpha ?? 0)
        let tintR = Float(p.tint?.red ?? 0), tintG = Float(p.tint?.green ?? 0), tintB = Float(p.tint?.blue ?? 0)
        let hasTint = p.tint != nil && tintA > 0
        let edge = Float(max(0.001, p.edgeWidth)), refraction = Float(p.refraction)
        let bevelled = p.edgeWidth > 0
        let rimW = Float(max(0.001, p.rimWidth)), rimA = Float(p.rimAlpha), spec = Float(p.specular), lift = Float(p.brighten)
        // Deeper than this inside the outline nothing but the veil applies: no bend, no rim,
        // no sheen, full coverage, so the interior takes the short path.
        let interior = -(max(bevelled ? 2 * edge : 0, rimA > 0 ? rimW : 0) + 1)
        let sw = source.width, sh = source.height, sStride = source.stride, oStride = out.stride
        source.bytes.withUnsafeBufferPointer { src in
            out.bytes.withUnsafeMutableBufferPointer { dst in
                for y in 0..<p.height {
                    let py0 = Float(y) + 0.5
                    for x in 0..<p.width {
                        let (d, nx, ny) = field.sample(x, y)
                        let o = y * oStride + x * 4
                        if d >= 0.5 { dst[o] = 0; dst[o + 1] = 0; dst[o + 2] = 0; dst[o + 3] = 0; continue }
                        var px = Float(x) + 0.5, py = py0
                        var cover: Float = 1, t: Float = 0, facing: Float = 0
                        let deep = d < interior
                        if !deep {
                            // Antialiased coverage of the shape at this pixel: 1 inside, 0 outside.
                            cover = min(1, 0.5 - d)
                            // The bevel: t is 1 at the rim, 0 edgeWidth inside; the lens looks
                            // outward through it, so content beyond the edge bends into the rim.
                            t = bevelled ? min(1, max(0, 1 + d / edge)) : 0
                            let bend = refraction * t * t
                            px += nx * bend; py += ny * bend
                            facing = nx * lx + ny * ly
                        }
                        var (b, g, r, a) = _MaterialPixels.bilinear(src, width: sw, height: sh, stride: sStride, x: (px - ox) * sx - 0.5, y: (py - oy) * sy - 0.5)
                        if a > 0.001 { let inv = 1 / a; b *= inv; g *= inv; r *= inv }
                        // Veil, then tint, over the backdrop.
                        r += (veilR - r) * veilA; g += (veilG - g) * veilA; b += (veilB - b) * veilA
                        a += (1 - a) * veilA
                        if hasTint {
                            r += (tintR - r) * tintA; g += (tintG - g) * tintA; b += (tintB - b) * tintA
                            a += (1 - a) * tintA
                        }
                        if !deep {
                            // Lighting on the bevel: the rim line and the specular sheen.
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
                            if spec > 0, facing > 0, bevelled {
                                // The sheen reaches twice as deep as the bevel and falls off
                                // with the square of the facing, a soft band rather than a line.
                                let reach = min(1, max(0, 1 + d / (2 * edge)))
                                let k = facing * facing * reach * reach * spec
                                r += (1 - r) * k; g += (1 - g) * k; b += (1 - b) * k
                            }
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
    @_transparent
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

    @_transparent static func byte(_ v: Float) -> UInt8 { UInt8(min(255, max(0, (v * 255).rounded()))) }

    /// The premultiplied (b, g, r, a) in 0...1 at a fractional pixel position, bilinear,
    /// clamped to the border.
    @_transparent
    static func bilinear(_ s: UnsafeBufferPointer<UInt8>, width: Int, height: Int, stride: Int, x: Float, y: Float) -> (Float, Float, Float, Float) {
        let cx = min(Float(width - 1), max(0, x)), cy = min(Float(height - 1), max(0, y))
        let x0 = Int(cx), y0 = Int(cy)
        let x1 = min(width - 1, x0 + 1), y1 = min(height - 1, y0 + 1)
        let fx = cx - Float(x0), fy = cy - Float(y0)
        let o00 = y0 * stride + x0 * 4, o10 = y0 * stride + x1 * 4, o01 = y1 * stride + x0 * 4, o11 = y1 * stride + x1 * 4
        let w00 = (1 - fx) * (1 - fy), w10 = fx * (1 - fy), w01 = (1 - fx) * fy, w11 = fx * fy
        let k: Float = 1 / 255
        let b = (Float(s[o00]) * w00 + Float(s[o10]) * w10 + Float(s[o01]) * w01 + Float(s[o11]) * w11) * k
        let g = (Float(s[o00 + 1]) * w00 + Float(s[o10 + 1]) * w10 + Float(s[o01 + 1]) * w01 + Float(s[o11 + 1]) * w11) * k
        let r = (Float(s[o00 + 2]) * w00 + Float(s[o10 + 2]) * w10 + Float(s[o01 + 2]) * w01 + Float(s[o11 + 2]) * w11) * k
        let a = (Float(s[o00 + 3]) * w00 + Float(s[o10 + 3]) * w10 + Float(s[o01 + 3]) * w01 + Float(s[o11 + 3]) * w11) * k
        return (b, g, r, a)
    }

    /// Saturation: every colour pulled away from (above 1) or toward (below 1) its luminance.
    mutating func saturate(by s: CGFloat) {
        let k = Float(s), w = width, h = height, st = stride
        bytes.withUnsafeMutableBufferPointer { px in
            for y in 0..<h {
                var o = y * st
                for _ in 0..<w {
                    let b = Float(px[o]), g = Float(px[o + 1]), r = Float(px[o + 2]), a = Float(px[o + 3])
                    let l = 0.0722 * b + 0.7152 * g + 0.2126 * r
                    // Premultiplied values stay within 0...alpha.
                    px[o] = UInt8(min(a, max(0, (l + (b - l) * k).rounded())))
                    px[o + 1] = UInt8(min(a, max(0, (l + (g - l) * k).rounded())))
                    px[o + 2] = UInt8(min(a, max(0, (l + (r - l) * k).rounded())))
                    o += 4
                }
            }
        }
    }

    /// The alpha-weighted mean luminance of the straight colours, nil for no coverage.
    func averageLuminance() -> CGFloat? {
        var sum: Double = 0, weight: Double = 0
        let w = width, h = height, st = stride
        bytes.withUnsafeBufferPointer { px in
            for y in 0..<h {
                var o = y * st
                for _ in 0..<w {
                    let a = Double(px[o + 3])
                    if a > 0 {
                        // Premultiplied: luma / alpha is the straight luma; the weight is alpha.
                        sum += 0.0722 * Double(px[o]) + 0.7152 * Double(px[o + 1]) + 0.2126 * Double(px[o + 2])
                        weight += a
                    }
                    o += 4
                }
            }
        }
        return weight > 0 ? CGFloat(sum / weight) : nil
    }

    /// Whether at least `fraction` of the pixels are within `tolerance` of `color`
    /// (straight sRGB components): a sample that holds nothing but the window background.
    func mostly(_ color: PlatformGlassParameters.Color, tolerance: Int = 6, fraction: Double = 0.97) -> Bool {
        let cb = Int(color.blue * 255), cg = Int(color.green * 255), cr = Int(color.red * 255)
        var hits = 0
        let w = width, h = height, st = stride
        bytes.withUnsafeBufferPointer { px in
            for y in 0..<h {
                var o = y * st
                for _ in 0..<w {
                    let a = Int(px[o + 3])
                    if a > 0, abs(Int(px[o]) * 255 / a - cb) <= tolerance, abs(Int(px[o + 1]) * 255 / a - cg) <= tolerance, abs(Int(px[o + 2]) * 255 / a - cr) <= tolerance { hits += 1 }
                    o += 4
                }
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
    /// each pixel averaged over `2 * radius + 1` samples with the border clamped. The four
    /// channels run in one sweep with running sums (wrapping arithmetic: a sum of bytes
    /// over a window never overflows), so a debug build of the package keeps up too.
    static func box(_ src: [UInt8], into dst: inout [UInt8], width: Int, height: Int, stride: Int, radius: Int, horizontal: Bool) {
        let length = horizontal ? width : height
        let lines = horizontal ? height : width
        let stepIn = horizontal ? 4 : stride
        let lineIn = horizontal ? stride : 4
        let window = 2 * radius + 1
        let last = length - 1
        src.withUnsafeBufferPointer { s in
            dst.withUnsafeMutableBufferPointer { d in
                guard let sp = s.baseAddress, let dp = d.baseAddress else { return }
                for line in 0..<lines {
                    let base = line * lineIn
                    // The running sums start with the first pixel repeated `radius` times
                    // plus the first `radius + 1` pixels.
                    var s0 = Int32(sp[base]) &* Int32(radius), s1 = Int32(sp[base + 1]) &* Int32(radius)
                    var s2 = Int32(sp[base + 2]) &* Int32(radius), s3 = Int32(sp[base + 3]) &* Int32(radius)
                    var i = 0
                    while i <= min(radius, last) {
                        let o = base + i * stepIn
                        s0 &+= Int32(sp[o]); s1 &+= Int32(sp[o + 1]); s2 &+= Int32(sp[o + 2]); s3 &+= Int32(sp[o + 3])
                        i &+= 1
                    }
                    if last < radius {
                        let o = base + last * stepIn, n = Int32(radius - last)
                        s0 &+= Int32(sp[o]) &* n; s1 &+= Int32(sp[o + 1]) &* n; s2 &+= Int32(sp[o + 2]) &* n; s3 &+= Int32(sp[o + 3]) &* n
                    }
                    let w = Int32(window)
                    var o = base
                    var leaving = base, entering = base + min(last, radius + 1) * stepIn
                    i = 0
                    while i < length {
                        dp[o] = UInt8(truncatingIfNeeded: s0 / w); dp[o + 1] = UInt8(truncatingIfNeeded: s1 / w)
                        dp[o + 2] = UInt8(truncatingIfNeeded: s2 / w); dp[o + 3] = UInt8(truncatingIfNeeded: s3 / w)
                        s0 &+= Int32(sp[entering]) &- Int32(sp[leaving]); s1 &+= Int32(sp[entering + 1]) &- Int32(sp[leaving + 1])
                        s2 &+= Int32(sp[entering + 2]) &- Int32(sp[leaving + 2]); s3 &+= Int32(sp[entering + 3]) &- Int32(sp[leaving + 3])
                        if i >= radius { leaving &+= stepIn }
                        if i + radius + 1 < last { entering &+= stepIn }
                        o &+= stepIn; i &+= 1
                    }
                }
            }
        }
    }
}
