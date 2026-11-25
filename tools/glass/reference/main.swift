// Liquid Glass references (ADR-0052 stage 2), built against Apple's AppKit outside the
// package (tools/glass/capture-references.sh):
//
//   glass-reference-capture capture <dir> macOS 26 (built with -D GLASS_CAPTURE): draws each scene of
//                                         Examples/Glass/ReferenceScene.swift with real
//                                         NSGlassEffectViews and writes macos26-<scene>@2x.png
//                                         (ScreenCaptureKit; needs Screen Recording permission)
//   glass-reference compare <mac.png> <port.png>
//                                         any macOS: per glass surface of the scene, the mean
//                                         colour and luminance, the spread (how blurred), the
//                                         top and bottom rim against the interior, for both
//                                         captures and the difference, the numbers the port's
//                                         constants are tuned against.

import AppKit
import ImageIO
import ScreenCaptureKit

#if GLASS_CAPTURE
@MainActor
func capture(into dir: String) async throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.activate(ignoringOtherApps: true)
    for scene in GlassReferenceScene.allCases {
        let w = NSWindow(contentRect: NSRect(origin: NSPoint(x: 200, y: 200), size: GlassReferenceScene.size), styleMask: [.titled], backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: scene.appearance)
        w.contentView = scene.makeContent()
        w.makeKeyAndOrderFront(nil)
        // Let the window server composite the glass.
        try await Task.sleep(nanoseconds: 800_000_000)
        let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let scw = shareable.windows.first(where: { $0.windowID == CGWindowID(w.windowNumber) }) else { throw NSError(domain: "glass-reference", code: 1) }
        let scale = w.backingScaleFactor
        let config = SCStreamConfiguration()
        config.width = Int(w.frame.width * scale); config.height = Int(w.frame.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: scw), configuration: config)
        // The content area alone: the title bar sits above it.
        let titleBar = (w.frame.height - w.contentRect(forFrameRect: w.frame).height) * scale
        let crop = CGRect(x: 0, y: titleBar, width: GlassReferenceScene.size.width * scale, height: GlassReferenceScene.size.height * scale)
        guard let content = image.cropping(to: crop) else { throw NSError(domain: "glass-reference", code: 2) }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("macos26-\(scene.rawValue)@2x.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, content, nil)
        CGImageDestinationFinalize(dest)
        print("captured \(scene.rawValue): \(url.path) (\(content.width)x\(content.height))")
        w.close()
    }
}
#endif

/// RGBA bytes of an image, top row first.
func rgba(_ path: String) -> (bytes: [UInt8], width: Int, height: Int) {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
    let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
    var bytes = [UInt8](repeating: 0, count: img.width * img.height * 4)
    let ctx = CGContext(data: &bytes, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
    return (bytes, img.width, img.height)
}

struct Region { var r = 0.0, g = 0.0, b = 0.0, luma = 0.0, spread = 0.0 }

/// The mean colour and the luminance standard deviation of a rectangle in points (y up).
func measure(_ img: (bytes: [UInt8], width: Int, height: Int), _ rect: NSRect) -> Region {
    let s = Double(img.width) / Double(GlassReferenceScene.size.width)
    let x0 = Int(rect.minX * s), x1 = Int(rect.maxX * s)
    let y0 = Int((GlassReferenceScene.size.height - rect.maxY) * s), y1 = Int((GlassReferenceScene.size.height - rect.minY) * s)
    var out = Region(), lumas: [Double] = []
    for y in max(0, y0)..<min(img.height, y1) {
        for x in max(0, x0)..<min(img.width, x1) {
            let o = (y * img.width + x) * 4
            let r = Double(img.bytes[o]) / 255, g = Double(img.bytes[o + 1]) / 255, b = Double(img.bytes[o + 2]) / 255
            out.r += r; out.g += g; out.b += b
            lumas.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
        }
    }
    let n = Double(max(1, lumas.count))
    out.r /= n; out.g /= n; out.b /= n
    out.luma = lumas.reduce(0, +) / n
    out.spread = (lumas.reduce(0) { $0 + ($1 - out.luma) * ($1 - out.luma) } / n).squareRoot()
    return out
}

func compare(_ macPath: String, _ portPath: String) {
    let mac = rgba(macPath), port = rgba(portPath)
    func f(_ v: Double) -> String { String(format: "%6.3f", v) }
    print("surface            | measure      |    mac |   port |  delta")
    print("-------------------|--------------|--------|--------|-------")
    for s in GlassReferenceScene.surfaces {
        let inset = s.radius * 0.6 + 4
        let interior = s.frame.insetBy(dx: inset, dy: min(inset, s.frame.height / 2 - 4))
        let top = NSRect(x: s.frame.midX - 20, y: s.frame.maxY - 3, width: 40, height: 2)
        let bottom = NSRect(x: s.frame.midX - 20, y: s.frame.minY + 1, width: 40, height: 2)
        let mi = measure(mac, interior), pi = measure(port, interior)
        let mt = measure(mac, top), pt = measure(port, top), mb = measure(mac, bottom), pb = measure(port, bottom)
        let rows: [(String, Double, Double)] = [
            ("interior luma", mi.luma, pi.luma), ("interior r", mi.r, pi.r), ("interior g", mi.g, pi.g), ("interior b", mi.b, pi.b),
            ("blur spread", mi.spread, pi.spread), ("top rim - in", mt.luma - mi.luma, pt.luma - pi.luma), ("bottom rim - in", mb.luma - mi.luma, pb.luma - pi.luma),
        ]
        for (name, m, p) in rows { print("\(s.name.padding(toLength: 18, withPad: " ", startingAt: 0)) | \(name.padding(toLength: 12, withPad: " ", startingAt: 0)) | \(f(m)) | \(f(p)) | \(f(p - m))") }
    }
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
#if GLASS_CAPTURE
case "capture" where args.count > 2:
    let dir = args[2]
    Task { @MainActor in
        do { try await capture(into: dir); exit(0) } catch { FileHandle.standardError.write(Data("capture failed: \(error)\n".utf8)); exit(1) }
    }
    NSApplication.shared.run()
#endif
case "compare" where args.count > 3:
    compare(args[2], args[3])
default:
    print("usage: glass-reference capture <dir> | compare <mac.png> <port.png>")
    exit(64)
}
