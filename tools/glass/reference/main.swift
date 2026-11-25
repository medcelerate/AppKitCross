// Liquid Glass references (ADR-0052 stage 2), built against Apple's AppKit outside the
// package by tools/glass/capture-references.sh:
//
//   glass-reference-capture capture <dir>   macOS 26 (built with -D GLASS_CAPTURE and a
//                                           macOS 26 target): every scene of
//                                           Examples/Glass/ReferenceScene.swift in every state
//                                           with real NSGlassEffectViews and SwiftUI glass, at
//                                           the display's scale and at 1x, into
//                                           macos26-<scene>-<state>@<n>x.png plus
//                                           macos26-manifest.json
//   glass-reference compare <scene> <mac.png> <port.png>
//                                           any macOS: per glass surface of the scene, the mean
//                                           colour and luminance, the spread (how blurred), the
//                                           top and bottom rim against the interior, for both
//                                           captures and the difference
//
// Determinism: a fixed 480x300 pt content area at a fixed screen position, the app active and
// its window key, the pointer parked off the window for the rest state, a settle delay before
// each capture (glass animates its state changes), the window's shadow excluded. Hover warps
// the pointer to the interactive surface's centre; press also posts a left mouse down there
// (CGEvent, which needs Accessibility permission for the terminal; without it the press
// captures are skipped and the manifest says so) and the mouse up after the capture.

import AppKit
import ImageIO
#if GLASS_CAPTURE
import ScreenCaptureKit
#endif

#if GLASS_CAPTURE
struct Capture: Encodable {
    let file: String, scene: String, state: String, appearance: String
    let scale: Int
    /// The display's own scale; a capture at another scale was resampled by the window server.
    let nativeScale: Int
    let resampled: Bool
    let width: Int, height: Int
}
struct Manifest: Encodable {
    let generator = "tools/glass/capture-references.sh"
    let os: String, model: String, date: String
    let contentSize: [Int]
    var captures: [Capture] = []
    var skipped: [String] = []
}

@MainActor
func capture(into dir: String) async throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.activate(ignoringOtherApps: true)
    var model = [CChar](repeating: 0, count: 256), size = 256
    sysctlbyname("hw.model", &model, &size, nil, 0)
    let iso = ISO8601DateFormatter()
    var manifest = Manifest(os: ProcessInfo.processInfo.operatingSystemVersionString, model: String(cString: model),
                            date: iso.string(from: Date()), contentSize: [Int(GlassReferenceScene.size.width), Int(GlassReferenceScene.size.height)])
    let trusted = AXIsProcessTrusted()
    let screen = NSScreen.main!
    let park = CGPoint(x: screen.frame.maxX - 5, y: 5)   // global display coordinates, top left origin
    for scene in GlassReferenceScene.allCases {
        let w = NSWindow(contentRect: NSRect(origin: NSPoint(x: screen.visibleFrame.minX + 80, y: screen.visibleFrame.maxY - 80 - GlassReferenceScene.size.height),
                                             size: GlassReferenceScene.size), styleMask: [.titled], backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: scene.appearance)
        w.contentView = scene.makeContent()
        w.hasShadow = false
        w.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        for state in scene.states {
            var pressed = false
            if state == .rest {
                CGWarpMouseCursorPosition(park)
            } else if let surface = scene.surfaces.first(where: { $0.interactive }) {
                // The surface's centre on screen, in the global top-left coordinates CG uses.
                let inWindow = NSPoint(x: surface.frame.midX, y: surface.frame.midY)
                let onScreen = w.convertPoint(toScreen: inWindow)
                let primary = NSScreen.screens[0].frame.height
                let target = CGPoint(x: onScreen.x, y: primary - onScreen.y)
                CGWarpMouseCursorPosition(target)
                // A move event so the tracking areas see the pointer arrive.
                CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: target, mouseButton: .left)?.post(tap: .cghidEventTap)
                if state == .press {
                    guard trusted else {
                        manifest.skipped.append("\(scene.rawValue)-press: Accessibility permission not granted to the terminal, so no mouse down could be posted")
                        continue
                    }
                    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: target, mouseButton: .left)?.post(tap: .cghidEventTap)
                    pressed = true
                }
            }
            try await Task.sleep(nanoseconds: 1_200_000_000)
            let native = Int(w.backingScaleFactor.rounded())
            for scale in Array(Set([native, 1])).sorted(by: >) {
                let image = try await captureContent(of: w, scale: CGFloat(scale))
                let name = scene.fileName(prefix: "macos26", state: state, scale: scale)
                write(image, to: URL(fileURLWithPath: dir).appendingPathComponent(name))
                manifest.captures.append(Capture(file: name, scene: scene.rawValue, state: state.rawValue, appearance: scene.appearance.rawValue,
                                                 scale: scale, nativeScale: native, resampled: scale != native, width: image.width, height: image.height))
                print("captured \(name) (\(image.width)x\(image.height))")
            }
            if pressed, let surface = scene.surfaces.first(where: { $0.interactive }) {
                let onScreen = w.convertPoint(toScreen: NSPoint(x: surface.frame.midX, y: surface.frame.midY))
                let target = CGPoint(x: onScreen.x, y: NSScreen.screens[0].frame.height - onScreen.y)
                CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: target, mouseButton: .left)?.post(tap: .cghidEventTap)
                try await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        w.close()
    }
    CGWarpMouseCursorPosition(park)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(manifest).write(to: URL(fileURLWithPath: dir).appendingPathComponent("macos26-manifest.json"))
    for s in manifest.skipped { print("skipped: \(s)") }
}

/// The window's content area at `scale` pixels per point (ScreenCaptureKit resamples when it
/// is not the display's), the title bar cropped off.
@MainActor
func captureContent(of w: NSWindow, scale: CGFloat) async throws -> CGImage {
    let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    guard let scw = shareable.windows.first(where: { $0.windowID == CGWindowID(w.windowNumber) }) else { throw NSError(domain: "glass-reference", code: 1) }
    let config = SCStreamConfiguration()
    config.width = Int((w.frame.width * scale).rounded()); config.height = Int((w.frame.height * scale).rounded())
    config.showsCursor = false
    config.ignoreShadowsSingleWindow = true
    let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: scw), configuration: config)
    let titleBar = ((w.frame.height - w.contentRect(forFrameRect: w.frame).height) * scale).rounded()
    let crop = CGRect(x: 0, y: titleBar, width: (GlassReferenceScene.size.width * scale).rounded(), height: (GlassReferenceScene.size.height * scale).rounded())
    guard let content = image.cropping(to: crop) else { throw NSError(domain: "glass-reference", code: 2) }
    return content
}

func write(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}
#endif

/// RGBA bytes of an image, top row first.
func rgba(_ path: String) -> (bytes: [UInt8], width: Int, height: Int) {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        FileHandle.standardError.write(Data("cannot read \(path)\n".utf8)); exit(1)
    }
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

func compare(_ scene: GlassReferenceScene, _ macPath: String, _ portPath: String) {
    let mac = rgba(macPath), port = rgba(portPath)
    func f(_ v: Double) -> String { String(format: "%6.3f", v) }
    print("surface             | measure         |    mac |   port |  delta")
    print("--------------------|-----------------|--------|--------|-------")
    for s in scene.surfaces {
        let inset = s.radius * 0.6 + 4
        let interior = s.frame.insetBy(dx: inset, dy: min(inset, s.frame.height / 2 - 4))
        let top = NSRect(x: s.frame.midX - 20, y: s.frame.maxY - 3, width: 40, height: 2)
        let bottom = NSRect(x: s.frame.midX - 20, y: s.frame.minY + 1, width: 40, height: 2)
        let mi = measure(mac, interior), pi = measure(port, interior)
        let mt = measure(mac, top), pt = measure(port, top), mb = measure(mac, bottom), pb = measure(port, bottom)
        let rows: [(String, Double, Double)] = [
            ("interior luma", mi.luma, pi.luma), ("interior r", mi.r, pi.r), ("interior g", mi.g, pi.g), ("interior b", mi.b, pi.b),
            ("blur spread", mi.spread, pi.spread), ("top rim - inside", mt.luma - mi.luma, pt.luma - pi.luma), ("bottom rim - in", mb.luma - mi.luma, pb.luma - pi.luma),
        ]
        for (name, m, p) in rows {
            print("\(s.name.padding(toLength: 19, withPad: " ", startingAt: 0)) | \(name.padding(toLength: 15, withPad: " ", startingAt: 0)) | \(f(m)) | \(f(p)) | \(f(p - m))")
        }
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
case "compare" where args.count > 4:
    guard let scene = GlassReferenceScene(rawValue: args[2]) else { print("unknown scene \(args[2])"); exit(64) }
    compare(scene, args[3], args[4])
default:
    print("usage: glass-reference compare <scene> <mac.png> <port.png>   (capture: glass-reference-capture capture <dir>)")
    exit(64)
}
