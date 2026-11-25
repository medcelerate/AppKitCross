// The GPU stage of Liquid Glass (ADR-0052 stage 2): the platform's glass program (Metal on
// the macOS host, Vulkan on Linux, the Direct2D effect on Windows) agrees with the software
// pass within the documented tolerance over the same requests, a whole window drawn through
// it matches the software window, and `APPKITWIN_LIQUID_GLASS_GPU=0` selects the software
// pass. Tests skip where the platform has no program (no Metal device, no Vulkan loader).

import XCTest
@testable import AppKit

/// Premultiplied BGRA pixels of an image, top row first.
private func bytes(_ image: CGImage) -> [UInt8] { [UInt8](_pixels(image)) }

/// A 32-bit premultiplied BGRA image from a per-pixel colour.
@MainActor
private func gpuTestImage(width: Int, height: Int, _ color: (Int, Int) -> (r: UInt8, g: UInt8, b: UInt8)) -> CGImage {
    let stride = width * 4
    var data = Data(count: stride * height)
    for y in 0..<height { for x in 0..<width { let c = color(x, y); data[y * stride + x * 4] = c.b; data[y * stride + x * 4 + 1] = c.g; data[y * stride + x * 4 + 2] = c.r; data[y * stride + x * 4 + 3] = 255 } }
    #if os(Windows) || os(Linux)
    return CGImage.fromBGRA(width: width, height: height, stride: stride, data: data)!
    #else
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: stride, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    data.withUnsafeBytes { _ = memcpy(ctx.data!, $0.baseAddress, stride * height) }
    return ctx.makeImage()!
    #endif
}

/// The largest and the mean difference of two images' bytes (row padding skipped).
private func difference(_ a: CGImage, _ b: CGImage) -> (max: Int, mean: Double) {
    let pa = bytes(a), pb = bytes(b)
    var worst = 0, sum = 0, n = 0
    for y in 0..<min(a.height, b.height) {
        for x in 0..<(min(a.width, b.width) * 4) {
            let d = abs(Int(pa[y * a.bytesPerRow + x]) - Int(pb[y * b.bytesPerRow + x]))
            worst = max(worst, d); sum += d; n += 1
        }
    }
    return (worst, n > 0 ? Double(sum) / Double(n) : 0)
}

/// The documented tolerance (ADR-0052 stage 2): the programs run the software pass's
/// arithmetic on the same bytes, so a channel differs by float rounding alone.
private let maxTolerance = 3
private let meanTolerance = 0.25

final class LiquidGlassGPUTests: XCTestCase, @unchecked Sendable {
    @MainActor private static var previousGlass: Bool?
    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated { Self.previousGlass = _LiquidGlass._override; _LiquidGlass._override = true }
    }
    override func tearDown() {
        MainActor.assumeIsolated { _LiquidGlass._override = Self.previousGlass; _GlassGPU._override = nil }
        super.tearDown()
    }

    @MainActor private func platformProgram() throws -> any PlatformGlassProgram {
        guard let p = _GlassGPU.makePlatformProgram() else {
            throw XCTSkip("no glass program here: \(_GlassGPU.unavailableReason ?? "unknown")")
        }
        return p
    }

    /// A lens request over a sample of `sample` pixels for an output of `width` by
    /// `height`, the sample a quarter of the scale with the blur margin around the output.
    @MainActor private func request(width: Int, height: Int, sample: (Int, Int), margin: CGFloat, lens: Bool = true, variant: PlatformGlassRequest.Variant = .adaptive) -> PlatformGlassRequest {
        var p = PlatformGlassParameters(width: width, height: height)
        p.veil = .white; p.veilAlpha = 0.42
        if lens { p.edgeWidth = 12; p.refraction = 6; p.rimWidth = 2; p.rimAlpha = 0.55; p.specular = 0.5 }
        return PlatformGlassRequest(parameters: p, darkVeil: .init(red: 0.16, green: 0.16, blue: 0.18), darkVeilAlpha: 0.4, darkRimAlpha: 0.3, darkSpecular: 0.35,
                                    variant: variant, shapeRect: CGRect(x: 0, y: 0, width: width, height: height), cornerRadius: lens ? CGFloat(height) / 2 : 0,
                                    backdropRect: CGRect(x: -margin, y: -margin, width: CGFloat(width) + 2 * margin, height: CGFloat(height) + 2 * margin),
                                    blurRadius: 8, saturation: 1.3)
    }

    /// The program and the software pass over the same raw sample and request; the
    /// program gets the software-blurred backdrop and its luminance when it runs the lens
    /// alone, as Core hands it.
    @MainActor private func compare(_ program: any PlatformGlassProgram, raw: CGImage, request: PlatformGlassRequest, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let software = SoftwareMaterialBackend.shared.render(raw, request: request)!
        let gpu: CGImage?
        if program.runsBackdropStage {
            gpu = program.render(raw, request: request)
        } else {
            let blurred = SoftwareMaterialBackend.shared.blur(raw, radius: request.blurRadius, saturation: request.saturation)!
            var r = request
            r.luminance = SoftwareMaterialBackend.shared.averageLuminance(blurred) ?? 1
            gpu = program.render(blurred, request: r)
        }
        guard let gpu else { return XCTFail("\(program.name) rendered nothing for \(label)", file: file, line: line) }
        XCTAssertEqual(gpu.width, software.width, file: file, line: line)
        XCTAssertEqual(gpu.height, software.height, file: file, line: line)
        let d = difference(gpu, software)
        XCTAssertLessThanOrEqual(d.max, maxTolerance, "\(program.name), \(label): largest channel difference", file: file, line: line)
        XCTAssertLessThanOrEqual(d.mean, meanTolerance, "\(program.name), \(label): mean channel difference", file: file, line: line)
    }

    /// Every stage agrees: the blur and saturation, the luminance probe's variant pick, the
    /// lens with refraction, rim and sheen, the tint, the lift, a flat material.
    func testProgramAgreesWithSoftwarePass() throws {
        try MainActor.assumeIsolated {
            let program = try platformProgram()
            // The output 240x88 px, its sample a quarter of that plus a 26 px margin.
            let margin: CGFloat = 26
            let sw = Int(((240 + 2 * margin) / 4).rounded(.up)), sh = Int(((88 + 2 * margin) / 4).rounded(.up))
            let halves = gpuTestImage(width: sw, height: sh) { x, _ in x < sw / 2 ? (255, 90, 90) : (90, 90, 255) }
            let stripes = gpuTestImage(width: sw, height: sh) { x, y in ((x / 3 + y / 5) % 2 == 0) ? (250, 240, 200) : (40, 120, 220) }
            let dark = gpuTestImage(width: sw, height: sh) { x, _ in (UInt8(20 + x % 30), 25, 40) }
            let base = request(width: 240, height: 88, sample: (sw, sh), margin: margin)
            compare(program, raw: halves, request: base, "light lens over halves")
            compare(program, raw: stripes, request: base, "light lens over stripes")
            compare(program, raw: dark, request: base, "adaptive lens over a dark backdrop")
            var forced = base; forced.variant = .dark
            compare(program, raw: halves, request: forced, "dark variant")
            var tinted = base; tinted.parameters.tint = .init(red: 1, green: 0.5, blue: 0.1, alpha: 0.9); tinted.parameters.tintAlpha = 0.55
            compare(program, raw: stripes, request: tinted, "tinted lens")
            var hovered = base; hovered.parameters.brighten = 0.2
            compare(program, raw: halves, request: hovered, "pressed lens")
            var clear = base; clear.parameters.veilAlpha = 0.16; clear.blurRadius = 5; clear.saturation = 1.15
            compare(program, raw: stripes, request: clear, "clear lens")
            var light = base; light.parameters.lightX = 0.4; light.parameters.lightY = -0.6
            compare(program, raw: stripes, request: light, "another light")
            let material = request(width: 240, height: 88, sample: (sw, sh), margin: margin, lens: false)
            compare(program, raw: stripes, request: material, "flat material")
            var unblurred = base; unblurred.blurRadius = 0; unblurred.saturation = 1
            compare(program, raw: stripes, request: unblurred, "no blur, no saturation")
        }
    }

    /// The variant the program picks follows the luminance probe as the software pass's does:
    /// the same adaptive request is light over a pale backdrop and dark over a dark one.
    func testProgramProbesLuminanceForTheVariant() throws {
        try MainActor.assumeIsolated {
            let program = try platformProgram()
            let pale = gpuTestImage(width: 40, height: 30) { _, _ in (230, 230, 220) }
            let deep = gpuTestImage(width: 40, height: 30) { _, _ in (20, 20, 30) }
            let r = request(width: 120, height: 80, sample: (40, 30), margin: 20)
            @MainActor func center(_ raw: CGImage) -> Int {
                let src: CGImage
                var rr = r
                if program.runsBackdropStage { src = raw } else {
                    src = SoftwareMaterialBackend.shared.blur(raw, radius: r.blurRadius, saturation: r.saturation)!
                    rr.luminance = SoftwareMaterialBackend.shared.averageLuminance(src)
                }
                let img = program.render(src, request: rr)!
                let px = bytes(img), o = 40 * img.bytesPerRow + 60 * 4
                return Int(px[o + 1])
            }
            XCTAssertGreaterThan(center(pale), 200, "light veil over the pale backdrop")
            XCTAssertLessThan(center(deep), 60, "dark veil over the dark backdrop")
        }
    }

    /// A window drawn through the program matches the same window drawn by the software
    /// pass: Core builds the request from the spec exactly as it builds the software
    /// parameters, for lenses (plain, clear, tinted, interactive) and the band's material.
    func testWindowThroughProgramMatchesSoftware() throws {
        try MainActor.assumeIsolated {
            let program = try platformProgram()
            @MainActor func paint(_ p: (any PlatformGlassProgram)?) -> CGImage {
                _GlassGPU._override = .some(p)
                let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
                w.appearance = NSAppearance(named: .aqua)
                let content = w.contentView!
                let backdrop = _GPUTestBands(frame: content.bounds)
                content.addSubview(backdrop)
                let lens = NSGlassEffectView(frame: NSRect(x: 20, y: 20, width: 120, height: 44)); lens.cornerRadius = 22
                let clear = NSGlassEffectView(frame: NSRect(x: 170, y: 20, width: 120, height: 44)); clear.cornerRadius = 12; clear.style = .clear
                let tinted = NSGlassEffectView(frame: NSRect(x: 20, y: 90, width: 120, height: 44)); tinted.cornerRadius = 22; tinted.tintColor = .systemOrange
                let interactive = NSGlassEffectView(frame: NSRect(x: 170, y: 90, width: 120, height: 44)); interactive.cornerRadius = 22; interactive._isInteractive = true; interactive._isHovered = true
                for v in [lens, clear, tinted, interactive] { content.addSubview(v) }
                let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
                content.cacheDisplay(in: content.bounds, to: rep)
                w.close()
                return rep.cgImage!
            }
            let gpu = paint(program), software = paint(nil)
            let d = difference(gpu, software)
            XCTAssertLessThanOrEqual(d.max, maxTolerance, "\(program.name): window largest channel difference")
            XCTAssertLessThanOrEqual(d.mean, meanTolerance, "\(program.name): window mean channel difference")
            // The program really drew: the samples are raw for a program that blurs them.
            _GlassGPU._override = .some(program)
            XCTAssertNotNil(_GlassGPU.program)
        }
    }

    /// `APPKITWIN_LIQUID_GLASS_GPU=0` (or no/false/off) selects the software pass; anything
    /// else, or nothing, asks for the program.
    func testEnvironmentOptOutSelectsSoftware() {
        MainActor.assumeIsolated {
            XCTAssertTrue(_GlassGPU.isRequested([:]))
            XCTAssertTrue(_GlassGPU.isRequested(["APPKITWIN_LIQUID_GLASS_GPU": "1"]))
            for off in ["0", "no", "false", "OFF"] { XCTAssertFalse(_GlassGPU.isRequested(["APPKITWIN_LIQUID_GLASS_GPU": off]), off) }
            let previous = ProcessInfo.processInfo.environment["APPKITWIN_LIQUID_GLASS_GPU"]
            setenv("APPKITWIN_LIQUID_GLASS_GPU", "0", 1)
            _GlassGPU._resetForTesting()
            XCTAssertNil(_GlassGPU.program, "the switch off selects the software pass")
            XCTAssertEqual(_GlassGPU.unavailableReason, "APPKITWIN_LIQUID_GLASS_GPU=0")
            // And the pass a window then draws is the software one: the sample is blurred on the CPU.
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            w.contentView!.addSubview(_GPUTestBands(frame: w.contentView!.bounds))
            let glass = NSGlassEffectView(frame: NSRect(x: 40, y: 20, width: 120, height: 60))
            w.contentView!.addSubview(glass)
            let rep = w.contentView!.bitmapImageRepForCachingDisplay(in: w.contentView!.bounds)!
            w.contentView!.cacheDisplay(in: w.contentView!.bounds, to: rep)
            XCTAssertFalse(_GlassRegistry.sample(for: glass).isRaw, "the software pass blurs the sample itself")
            w.close()
            if let previous { setenv("APPKITWIN_LIQUID_GLASS_GPU", previous, 1) } else { unsetenv("APPKITWIN_LIQUID_GLASS_GPU") }
            _GlassGPU._resetForTesting()
        }
    }

    /// The embedded shaders are the ones in Platform/Shaders: the MSL and HLSL text verbatim,
    /// the SPIR-V built from the GLSL whose hash it records (run tools/glass/build-spirv.sh
    /// after editing a shader).
    func testEmbeddedShadersMatchSources() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/AppKit/Platform/Shaders")
        guard FileManager.default.fileExists(atPath: dir.path) else { throw XCTSkip("sources not beside the tests") }
        func text(_ name: String) throws -> String { try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) }
        func fnv(_ data: Data) -> UInt64 {
            var h: UInt64 = 0xcbf29ce484222325
            for b in data { h ^= UInt64(b); h = h &* 0x100000001b3 }
            return h
        }
        XCTAssertEqual(_GlassShaders.metal, try text("glass.metal").trimmingCharacters(in: .newlines))
        XCTAssertEqual(_GlassShaders.hlsl, try text("glass_lens.hlsl").trimmingCharacters(in: .newlines))
        let common = try Data(contentsOf: dir.appendingPathComponent("glass_common.glsl"))
        for (name, hash, spirv) in [("glass_box", _GlassShaders.glassBoxHash, _GlassShaders.glassBoxSPIRV),
                                    ("glass_saturate", _GlassShaders.glassSaturateHash, _GlassShaders.glassSaturateSPIRV),
                                    ("glass_luminance", _GlassShaders.glassLuminanceHash, _GlassShaders.glassLuminanceSPIRV),
                                    ("glass_lens", _GlassShaders.glassLensHash, _GlassShaders.glassLensSPIRV)] {
            let glsl = try Data(contentsOf: dir.appendingPathComponent(name + ".comp"))
            XCTAssertEqual(fnv(common + glsl), hash, "\(name).comp changed since its SPIR-V was embedded")
            XCTAssertEqual(spirv.first, 0x0723_0203, "\(name) is SPIR-V")
        }
    }
}

/// Horizontal bands of saturated colours with a light one between, so the lenses sit over
/// edges, colour and both luminances.
@MainActor
private final class _GPUTestBands: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let colors: [NSColor] = [.systemRed, .systemYellow, .white, .systemBlue, .systemGreen, .black, .systemPurple]
        let h = bounds.height / CGFloat(colors.count)
        for (i, c) in colors.enumerated() {
            c.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: CGFloat(i) * h, width: bounds.width, height: h)).fill()
        }
        NSColor.systemPink.setFill()
        NSBezierPath(ovalIn: NSRect(x: bounds.midX - 30, y: bounds.midY - 30, width: 60, height: 60)).fill()
    }
}
