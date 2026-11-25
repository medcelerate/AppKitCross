// The Liquid Glass program on Windows (ADR-0052 stage 2): Direct2D custom effects
// (Sources/CD2D/cd2d_glass.cpp) whose pixel shaders are glass_lens.hlsl and
// glass_backdrop.hlsl, drawn on the window's own device context.
//
// Round 3: the frame beneath the glass is rendered into a bitmap on the window's device
// (`makeFrame`), and each surface runs the whole program over its crop as one effect graph
// (`draw(from:)`): nothing is read back or uploaded. Where no such frame can be made the
// round-1 path remains: the backdrop stage on the CPU over the CPU frame, the sample-scale
// backdrop uploaded, the lens on the GPU.

#if os(Windows)
import Foundation
import CoreGraphics
import CD2D

@MainActor
final class Win32GlassProgram: PlatformGlassProgram {
    let name = "Direct2D"
    var runsBackdropStage: Bool { false }
    var drawsInPlace: Bool { true }

    static func make() -> Result<any PlatformGlassProgram, _GlassProgramError> {
        var error = [CChar](repeating: 0, count: 2048)
        let ok = _GlassShaders.hlsl.withCString { lens in
            _GlassShaders.hlslBackdrop.withCString { backdrop in cd2d_glass_prepare(lens, backdrop, &error, UInt32(error.count)) }
        }
        guard ok else { return .failure(.init("Direct2D: " + String(cString: error))) }
        return .success(Win32GlassProgram())
    }

    func draw(_ backdrop: CGImage, request: PlatformGlassRequest, in rect: CGRect, of ctx: CGContext, flipped: Bool) -> Bool {
        let w = request.parameters.width, h = request.parameters.height
        guard w > 0, h > 0, backdrop.bitsPerPixel == 32, rect.width > 0, rect.height > 0 else { return false }
        var request = request
        if request.luminance == nil { request.luminance = SoftwareMaterialBackend.shared.averageLuminance(backdrop) ?? 1 }
        let constants = request.constants(sampleWidth: backdrop.width, sampleHeight: backdrop.height)
        ctx.saveGState()
        defer { ctx.restoreGState() }
        // The output's pixels, x right and y down from its top row, onto `rect` as the
        // software pass draws its shaded image (in a flipped view too).
        if flipped { ctx.translateBy(x: 0, y: rect.minY + rect.maxY); ctx.scaleBy(x: 1, y: -1) }
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: rect.width / CGFloat(w), y: -rect.height / CGFloat(h))
        return backdrop.data.withUnsafeBytes { raw in
            constants.withUnsafeBufferPointer { k in
                cd2d_glass_draw(ctx._d2dTarget, raw.baseAddress?.assumingMemoryBound(to: UInt8.self), UInt32(backdrop.width), UInt32(backdrop.height),
                                UInt32(backdrop.bytesPerRow), k.baseAddress, UInt32(w), UInt32(h))
            }
        }
    }

    func makeFrame(pixelWidth: Int, pixelHeight: Int, scale: CGFloat, like context: CGContext) -> (any PlatformGlassFrame)? {
        Win32GlassFrame(pixelWidth: pixelWidth, pixelHeight: pixelHeight, scale: scale, like: context)
    }

    func frameDevice(for context: CGContext) -> Int? {
        let device = cd2d_glass_frame_device(context._d2dTarget)
        return device == 0 ? nil : Int(bitPattern: UInt(device))
    }

    func draw(from source: PlatformGlassFrameSource, request: PlatformGlassRequest, in rect: CGRect, of ctx: CGContext, flipped: Bool) -> Bool {
        let w = request.parameters.width, h = request.parameters.height
        guard let frame = source.frame as? Win32GlassFrame, w > 0, h > 0, rect.width > 0, rect.height > 0 else { return false }
        var request = request
        request.luminance = nil
        let constants = request.constants(sampleWidth: source.cropWidth, sampleHeight: source.cropHeight)
        ctx.saveGState()
        defer { ctx.restoreGState() }
        if flipped { ctx.translateBy(x: 0, y: rect.minY + rect.maxY); ctx.scaleBy(x: 1, y: -1) }
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: rect.width / CGFloat(w), y: -rect.height / CGFloat(h))
        return constants.withUnsafeBufferPointer { k in
            cd2d_glass_draw_from_frame(ctx._d2dTarget, frame.handle, source.halved, UInt32(source.cropX), UInt32(source.cropY),
                                       UInt32(source.cropWidth), UInt32(source.cropHeight), Int32(source.mirrorBelow ?? -1),
                                       UInt32(request.boxRadius), k.baseAddress, UInt32(w), UInt32(h))
        }
    }

    /// The shaded surface read back (tests): the effect drawn into a bitmap context.
    func render(_ backdrop: CGImage, request: PlatformGlassRequest) -> CGImage? {
        let w = request.parameters.width, h = request.parameters.height
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        guard draw(backdrop, request: request, in: CGRect(x: 0, y: 0, width: w, height: h), of: ctx, flipped: false) else { return nil }
        return ctx.makeImage()
    }
}
/// The frame beneath the glass on the window's device: a bitmap target drawn through a
/// context whose base transform takes points (bottom-left origin) to its pixels.
@MainActor
final class Win32GlassFrame: PlatformGlassFrame {
    let handle: OpaquePointer   // CD2DGlassFrame*
    let context: CGContext

    init?(pixelWidth: Int, pixelHeight: Int, scale: CGFloat, like: CGContext) {
        guard pixelWidth > 0, pixelHeight > 0, let h = cd2d_glass_frame_create(like._d2dTarget, UInt32(pixelWidth), UInt32(pixelHeight)),
              let target = cd2d_glass_frame_target(h) else { return nil }
        handle = h
        let base = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: 0, ty: CGFloat(pixelHeight))
        context = CGContext(target: target, factory: like._d2dFactory, baseTransform: base, width: pixelWidth, height: pixelHeight)
    }

    func finish() -> Bool {
        context.releaseImageCache()
        return cd2d_glass_frame_finish(handle)
    }

    deinit { cd2d_glass_frame_release(handle) }
}
#endif
