// The GPU stage of the Liquid Glass material (ADR-0052, stage 2).
//
// One glass program per graphics API runs the stages the software pass in Material.swift
// runs, over the same inputs and with the same arithmetic, so the two agree within a few
// 1/255 steps (the tolerance is in the ADR and the tests):
//
// 1. Backdrop: three box passes of radius max(1, (radius + 1) / 2) per axis over the raw
//    sample (integer sums, truncating division, the border clamped: the software
//    running sum exactly), then the saturation pull from luminance.
// 2. Luminance probe: the alpha-weighted mean luminance of the blurred sample, which picks
//    the light or dark variant of an adaptive surface inside the program.
// 3. Lens: per output pixel the rounded rectangle's signed distance and normal, the
//    refraction through the bevel, the bilinear backdrop look-up, veil, tint, rim,
//    specular sheen, hover/press lift and antialiased coverage.
//
// The programs: Metal on the macOS host (`Platform/Host/HostGlassMetal.swift`, over the
// CGlassMetal shim, so the port's glass can be compared with real macOS glass on the same
// machine), Vulkan compute on Linux (`Platform/Linux/LinuxGlassVulkan.swift`, SPIR-V built
// from GLSL), and a Direct2D custom effect on Windows (`Platform/Win32/Win32GlassD2D.swift`,
// an HLSL pixel shader on the window's own D2D device, drawn straight into the window).
// The sources live in `Platform/Shaders` and are embedded by `tools/glass/embed-shaders.sh`
// into `GlassShaders.swift`.
//
// `APPKITWIN_LIQUID_GLASS_GPU=0` forces the software pass; it stays the fallback whenever
// a program cannot start or fails, and the reference the pixel tests compare against.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Everything one run of the glass program needs besides the backdrop pixels.
public struct PlatformGlassRequest: Hashable, Sendable {
    public enum Variant: Int, Hashable, Sendable { case light = 0, dark = 1, adaptive = 2 }
    /// The light variant's lens parameters (the output size, the shape's lengths, tint,
    /// light, lift); `darkVeil`, `darkVeilAlpha`, `darkRimAlpha` and `darkSpecular` replace
    /// the veil and lighting when the dark variant applies.
    public var parameters: PlatformGlassParameters
    public var darkVeil: PlatformGlassParameters.Color
    public var darkVeilAlpha: CGFloat
    public var darkRimAlpha: CGFloat
    public var darkSpecular: CGFloat
    public var variant: Variant
    /// The adaptive variant is dark below this mean luminance.
    public var threshold: CGFloat = 0.35
    /// The rounded rectangle in output pixels (top row first).
    public var shapeRect: CGRect
    public var cornerRadius: CGFloat
    /// Where the backdrop image lies in output pixels (it extends beyond the output by the
    /// blur margin).
    public var backdropRect: CGRect
    /// The backdrop stage: the blur radius in sample pixels and the saturation. A program
    /// that is handed an already blurred backdrop ignores them.
    public var blurRadius: Int
    public var saturation: CGFloat
    /// The backdrop's mean luminance when it is already known (a blurred backdrop handed in);
    /// nil lets the program probe it.
    public var luminance: CGFloat?

    public init(parameters: PlatformGlassParameters, darkVeil: PlatformGlassParameters.Color, darkVeilAlpha: CGFloat, darkRimAlpha: CGFloat, darkSpecular: CGFloat,
                variant: Variant, shapeRect: CGRect, cornerRadius: CGFloat, backdropRect: CGRect, blurRadius: Int, saturation: CGFloat, luminance: CGFloat? = nil) {
        self.parameters = parameters; self.darkVeil = darkVeil; self.darkVeilAlpha = darkVeilAlpha; self.darkRimAlpha = darkRimAlpha; self.darkSpecular = darkSpecular
        self.variant = variant; self.shapeRect = shapeRect; self.cornerRadius = cornerRadius; self.backdropRect = backdropRect
        self.blurRadius = blurRadius; self.saturation = saturation; self.luminance = luminance
    }

    /// Whether the dark variant applies for a backdrop of mean luminance `luminance`.
    public func resolvesDark(luminance: CGFloat?) -> Bool {
        switch variant {
        case .light: return false
        case .dark: return true
        case .adaptive: return (luminance ?? 1) < threshold
        }
    }

    /// The lens parameters of the variant that applies.
    public func resolvedParameters(luminance: CGFloat?) -> PlatformGlassParameters {
        guard resolvesDark(luminance: luminance) else { return parameters }
        var p = parameters
        p.veil = darkVeil; p.veilAlpha = darkVeilAlpha; p.rimAlpha = darkRimAlpha; p.specular = darkSpecular
        return p
    }

    /// The box radius of each of the three passes per axis (0: no blur), as the software pass.
    public var boxRadius: Int { blurRadius > 0 ? max(1, (blurRadius + 1) / 2) : 0 }

    /// The constant block every shader reads, twelve float4 rows (`GlassConstants` in the
    /// sources): sizes, backdrop placement, shape, lens lengths, light, tint, both veils,
    /// both lightings, the variant and the saturation.
    public func constants(sampleWidth: Int, sampleHeight: Int) -> [Float] {
        let p = parameters
        let lightLength = max(1e-6, (p.lightX * p.lightX + p.lightY * p.lightY).squareRoot())
        let tintA = p.tint.map { Float(p.tintAlpha * $0.alpha) } ?? 0
        var k = [Float](repeating: 0, count: 48)
        func row(_ i: Int, _ a: Float, _ b: Float, _ c: Float, _ d: Float) { k[i * 4] = a; k[i * 4 + 1] = b; k[i * 4 + 2] = c; k[i * 4 + 3] = d }
        row(0, Float(p.width), Float(p.height), Float(sampleWidth), Float(sampleHeight))
        row(1, Float(backdropRect.minX), Float(backdropRect.minY),
            Float(sampleWidth) / Float(max(1e-6, backdropRect.width)), Float(sampleHeight) / Float(max(1e-6, backdropRect.height)))
        let radius = min(cornerRadius, shapeRect.width / 2, shapeRect.height / 2)
        row(2, Float(shapeRect.minX), Float(shapeRect.minY), Float(shapeRect.maxX), Float(shapeRect.maxY))
        row(3, Float(radius), Float(max(0.001, p.edgeWidth)), Float(p.refraction), Float(max(0.001, p.rimWidth)))
        row(4, Float(p.lightX / lightLength), Float(p.lightY / lightLength), Float(p.brighten), p.edgeWidth > 0 ? 1 : 0)
        row(5, Float(p.tint?.red ?? 0), Float(p.tint?.green ?? 0), Float(p.tint?.blue ?? 0), tintA)
        row(6, Float(p.veil.red), Float(p.veil.green), Float(p.veil.blue), Float(p.veilAlpha))
        row(7, Float(darkVeil.red), Float(darkVeil.green), Float(darkVeil.blue), Float(darkVeilAlpha))
        row(8, Float(p.rimAlpha), Float(p.specular), Float(darkRimAlpha), Float(darkSpecular))
        row(9, Float(variant.rawValue), Float(threshold), luminance.map { Float($0) } ?? -1, Float(saturation))
        row(10, Float(boxRadius), 0, 0, 0)
        return k
    }
}

/// One graphics API's glass program.
@MainActor
public protocol PlatformGlassProgram: AnyObject {
    /// "Metal", "Vulkan", "Direct2D" and the device, for traces and the tests.
    var name: String { get }
    /// True when the program runs the backdrop stage (blur, saturation, luminance probe)
    /// itself and wants the raw sample; false when it takes the software-blurred backdrop
    /// and its luminance (`request.luminance`) and runs the lens alone.
    var runsBackdropStage: Bool { get }
    /// True when `draw` puts the result straight into the context without reading it back
    /// (Direct2D on the window's device); Core then caches nothing.
    var drawsInPlace: Bool { get }
    /// The shaded surface as premultiplied BGRA pixels, top row first, `parameters.width`
    /// by `parameters.height`; nil when the device could not run it.
    func render(_ backdrop: CGImage, request: PlatformGlassRequest) -> CGImage?
    /// Draws the shaded surface into `rect` of `context` (the image's top row at the rect's
    /// visual top, `flipped` as the view); false when it could not.
    func draw(_ backdrop: CGImage, request: PlatformGlassRequest, in rect: CGRect, of context: CGContext, flipped: Bool) -> Bool
    /// Round 3: a surface for the frame beneath the glass that stays on the device `like`
    /// draws with, `pixelWidth` by `pixelHeight`, drawn in points at `scale` (bottom-left
    /// origin, as an offscreen surface); nil to render the frame on the CPU. The default is nil.
    func makeFrame(pixelWidth: Int, pixelHeight: Int, scale: CGFloat, like context: CGContext) -> (any PlatformGlassFrame)?
    /// The whole program over such a frame, drawn into `rect` of `context`; false when it could
    /// not (the caller draws the software pass).
    func draw(from source: PlatformGlassFrameSource, request: PlatformGlassRequest, in rect: CGRect, of context: CGContext, flipped: Bool) -> Bool
}

/// The frame beneath the glass on the GPU (round 3): drawn through `context`, then finished.
@MainActor
public protocol PlatformGlassFrame: AnyObject {
    var context: CGContext { get }
    /// Ends the drawing; false when the device failed it.
    func finish() -> Bool
}

/// One surface's backdrop in a GPU frame: the crop (frame pixels, top row first, of the frame
/// halved when `halved`), and the crop row above which the strip below is mirrored in.
public struct PlatformGlassFrameSource {
    public let frame: any PlatformGlassFrame
    public let halved: Bool
    public let cropX: Int, cropY: Int, cropWidth: Int, cropHeight: Int
    public let mirrorBelow: Int?
}

/// Which glass program the window uses: the platform's when it starts and the switch does
/// not turn it off, else none (the software pass).
@MainActor
public enum _GlassGPU {
    /// Pins the program (tests): `.some(nil)` forces the software pass.
    public static var _override: (any PlatformGlassProgram)??
    private static var resolved: (any PlatformGlassProgram)??
    /// Set when the program made no GPU frame (round 3): the frame beneath the glass is
    /// rendered on the CPU from then on.
    public static var framesUnavailable = false
    /// Why the program is not in use, for traces.
    public private(set) static var unavailableReason: String?

    /// The program the glass pass runs, nil for the software pass.
    public static var program: (any PlatformGlassProgram)? {
        if let o = _override { return o }
        if let r = resolved { return r }
        let r = isRequested(ProcessInfo.processInfo.environment) ? makePlatformProgram() : nil
        if r == nil, unavailableReason == nil { unavailableReason = "APPKITWIN_LIQUID_GLASS_GPU=0" }
        resolved = .some(r)
        if NSView._traceFrames { NSView._trace("glass program: \(r?.name ?? "software (\(unavailableReason ?? "none"))")") }
        return r
    }

    /// Forgets the resolved program so the next use reads the environment again (tests).
    public static func _resetForTesting() { resolved = nil; unavailableReason = nil; framesUnavailable = false }

    /// Whether `environment` asks for the GPU program: anything but 0/no/false/off.
    public static func isRequested(_ environment: [String: String]) -> Bool {
        guard let v = environment["APPKITWIN_LIQUID_GLASS_GPU"]?.lowercased() else { return true }
        return !["0", "no", "false", "off"].contains(v)
    }

    /// Stops using the program for the rest of the process after a failure.
    public static func disable(_ reason: String) {
        guard _override == nil else { return }
        if case .some(.some) = resolved { FileHandle.standardError.write(Data("AppKitCross: Liquid Glass GPU program off, software pass from now on: \(reason)\n".utf8)) }
        unavailableReason = reason
        resolved = .some(nil)
    }

    /// The platform's program, nil when it cannot start (no device, no compiler).
    public static func makePlatformProgram() -> (any PlatformGlassProgram)? {
        #if os(Windows)
        let p = Win32GlassProgram.make()
        #elseif os(Linux)
        let p = LinuxGlassVulkanProgram.make()
        #elseif os(macOS)
        let p = HostGlassMetalProgram.make()
        #else
        let p: Result<any PlatformGlassProgram, _GlassProgramError> = .failure(.init("no glass program on this platform"))
        #endif
        switch p {
        case .success(let program): return program
        case .failure(let error): unavailableReason = error.message; return nil
        }
    }
}

/// Why a platform program did not start.
public struct _GlassProgramError: Error, Sendable { public let message: String; public init(_ message: String) { self.message = message } }

extension PlatformGlassProgram {
    public func makeFrame(pixelWidth: Int, pixelHeight: Int, scale: CGFloat, like context: CGContext) -> (any PlatformGlassFrame)? { nil }
    public func draw(from source: PlatformGlassFrameSource, request: PlatformGlassRequest, in rect: CGRect, of context: CGContext, flipped: Bool) -> Bool { false }

    /// Draws the rendered image the way the software pass's shaded image is drawn.
    public func drawRendered(_ backdrop: CGImage, request: PlatformGlassRequest, in rect: CGRect, of ctx: CGContext, flipped: Bool) -> Bool {
        guard let image = render(backdrop, request: request) else { return false }
        ctx.saveGState()
        ctx.interpolationQuality = .default
        if flipped { ctx.translateBy(x: 0, y: rect.minY + rect.maxY); ctx.scaleBy(x: 1, y: -1) }
        ctx.draw(image, in: rect)
        ctx.restoreGState()
        return true
    }
}

extension SoftwareMaterialBackend {
    /// The software pass for a whole request: blur, saturation and luminance over the raw
    /// sample, then the lens of the variant that applies. The reference the GPU programs are
    /// compared with.
    public func render(_ raw: CGImage, request: PlatformGlassRequest) -> CGImage? {
        let blurred = request.luminance == nil ? (blur(raw, radius: request.blurRadius, saturation: request.saturation) ?? raw) : raw
        let luminance = request.luminance ?? averageLuminance(blurred)
        return shade(blurred, in: request.backdropRect, shape: .roundedRect(request.shapeRect, cornerRadius: request.cornerRadius), parameters: request.resolvedParameters(luminance: luminance))
    }
}

/// The 32-bit premultiplied BGRA rows of an image, for the programs' uploads.
struct _GlassUpload {
    let bytes: [UInt8]
    let width: Int, height: Int, stride: Int
    init?(_ image: CGImage) {
        guard let px = _MaterialPixels(image) else { return nil }
        bytes = px.bytes; width = px.width; height = px.height; stride = px.stride
    }
    /// An image of `template`'s format from tightly packed rows.
    static func image(bytes: [UInt8], width: Int, height: Int, template: CGImage) -> CGImage? {
        _MaterialPixels(bytes: bytes, width: width, height: height, stride: width * 4, template: template).makeImage()
    }
}
