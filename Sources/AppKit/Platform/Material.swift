// Material backend (ADR-0051, Liquid Glass): the pixel work behind an in-window glass
// pass. Core samples what the window drew beneath a glass rectangle into an offscreen
// surface (`PlatformImageBackend.makeOffscreen`), hands the pixels here to be blurred, and
// draws the result tinted under the glass shape. Every backend ships the software blur;
// a backend with a GPU blur (Direct2D's Gaussian blur effect, a Vulkan compute pass) can
// override `material` on its `PlatformBackend` without Core knowing.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Blurs the pixels behind a glass surface.
@MainActor
public protocol PlatformMaterialBackend: AnyObject {
    /// `image` blurred by about `radius` pixels (a Gaussian approximation; the edges clamp
    /// to the border pixels). Returns `image` itself for a radius of zero, nil when the
    /// pixels cannot be read back.
    func blur(_ image: CGImage, radius: Int) -> CGImage?
}

extension PlatformBackend {
    /// The material pass every backend gets unless it provides its own.
    public var material: any PlatformMaterialBackend { SoftwareMaterialBackend.shared }
}

/// Three separable box blurs in place of a Gaussian (the classic approximation), on
/// 32-bit premultiplied pixels so translucent content blurs without fringes. The glass
/// pass samples at a quarter of the backing scale, so a toolbar band or sidebar column is
/// a few hundred by a few dozen pixels here and the pass costs well under a millisecond.
@MainActor
public final class SoftwareMaterialBackend: PlatformMaterialBackend {
    public static let shared = SoftwareMaterialBackend()
    public init() {}

    public func blur(_ image: CGImage, radius: Int) -> CGImage? {
        guard radius > 0 else { return image }
        guard var pixels = _MaterialPixels(image) else { return nil }
        // Three passes of radius r approximate a Gaussian of sigma ~ r; `radius` is the
        // visual blur (about 2 sigma), so each pass runs at half of it.
        let r = max(1, (radius + 1) / 2)
        var scratch = [UInt8](repeating: 0, count: pixels.bytes.count)
        for _ in 0..<3 {
            _MaterialPixels.box(pixels.bytes, into: &scratch, width: pixels.width, height: pixels.height, stride: pixels.stride, radius: r, horizontal: true)
            _MaterialPixels.box(scratch, into: &pixels.bytes, width: pixels.width, height: pixels.height, stride: pixels.stride, radius: r, horizontal: false)
        }
        return pixels.makeImage()
    }
}

/// The 32-bit pixel rows of a bitmap image, top row first, with the layout the offscreen
/// surfaces produce on every backend (premultiplied BGRA on Direct2D, cairo and the macOS
/// host's bitmap context); the blur treats the four bytes alike, so the channel order
/// does not matter to it, only that alpha is premultiplied.
struct _MaterialPixels {
    var bytes: [UInt8]
    let width: Int
    let height: Int
    let stride: Int
    private let template: CGImage

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
