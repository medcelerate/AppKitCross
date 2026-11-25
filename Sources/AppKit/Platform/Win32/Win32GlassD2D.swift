// The Liquid Glass program on Windows (ADR-0052 stage 2): the lens as a Direct2D custom
// effect (Sources/CD2D/cd2d_glass.cpp) whose pixel shader is glass_lens.hlsl, drawn on the
// window's own device context. The frame beneath the glass is still a CPU bitmap on Windows
// (a WIC render target), so the backdrop stage stays on the CPU, where at the sample scale it
// costs a few hundredths of a millisecond, and the lens (the stage that runs at the backing
// scale and dominated the software pass) runs on the GPU with nothing read back and only the
// sample-scale backdrop uploaded.

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
        let ok = _GlassShaders.hlsl.withCString { cd2d_glass_prepare($0, &error, UInt32(error.count)) }
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
#endif
