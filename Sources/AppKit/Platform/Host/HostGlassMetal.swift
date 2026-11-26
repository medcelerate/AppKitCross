// The Liquid Glass program on the macOS host (ADR-0052 stage 2): glass.metal on Apple's
// Metal through the CGlassMetal shim, the whole program (box passes, saturation, luminance
// probe, lens) on the GPU with one read-back of the shaded surface. The host build is for
// tests and for comparing the port's glass with real macOS glass on the same machine.

#if os(macOS)
import Foundation
import CoreGraphics
@_implementationOnly import CGlassMetal

@MainActor
final class HostGlassMetalProgram: PlatformGlassProgram {
    private let program: OpaquePointer
    let name: String
    var runsBackdropStage: Bool { true }
    var drawsInPlace: Bool { false }
    /// The luminance the last run probed (-1 for none), for the tests.
    private(set) var lastLuminance: Float = -1

    private init(program: OpaquePointer) {
        self.program = program
        name = "Metal (\(String(cString: cgm_program_device_name(program))))"
    }

    static func make() -> Result<any PlatformGlassProgram, _GlassProgramError> {
        var error = [CChar](repeating: 0, count: 1024)
        guard let p = _GlassShaders.metal.withCString({ cgm_program_create($0, &error, error.count) }) else {
            return .failure(.init("Metal: " + String(cString: error)))
        }
        return .success(HostGlassMetalProgram(program: p))
    }

    func render(_ backdrop: CGImage, request: PlatformGlassRequest) -> CGImage? {
        guard let up = _GlassUpload(backdrop) else { return nil }
        let w = request.parameters.width, h = request.parameters.height
        guard w > 0, h > 0 else { return nil }
        let constants = request.constants(sampleWidth: up.width, sampleHeight: up.height)
        var out = [UInt8](repeating: 0, count: w * h * 4)
        var luminance: Float = -1
        let ok = up.bytes.withUnsafeBufferPointer { raw in
            out.withUnsafeMutableBufferPointer { dst in
                cgm_program_run(program, raw.baseAddress, UInt32(up.width), UInt32(up.height), UInt32(up.stride),
                                request.luminance == nil, UInt32(request.boxRadius), constants,
                                dst.baseAddress, UInt32(w), UInt32(h), &luminance)
            }
        }
        guard ok else { return nil }
        lastLuminance = luminance
        return _GlassUpload.image(bytes: out, width: w, height: h, template: backdrop)
    }

    func draw(_ backdrop: CGImage, request: PlatformGlassRequest, in rect: CGRect, of context: CGContext, flipped: Bool) -> Bool {
        drawRendered(backdrop, request: request, in: rect, of: context, flipped: flipped)
    }
}
#endif
