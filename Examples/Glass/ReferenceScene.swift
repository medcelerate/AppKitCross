// The Liquid Glass reference scenes (ADR-0052 stage 2): one layout of glass over a fixed
// backdrop, built from public AppKit names alone so the same file compiles against Apple's
// AppKit on macOS 26 (tools/glass/reference, which captures real `NSGlassEffectView`s) and
// against the port (`Glass --reference <scene> <out.png>`). The two captures are compared
// region by region by `tools/glass/reference` (`compare`) to tune the port's constants.

import AppKit

enum GlassReferenceScene: String, CaseIterable {
    /// Light appearance: regular, clear, tinted and a large rounded lens over the bands.
    case light = "light"
    /// Dark appearance, the same layout.
    case dark = "dark"
    /// Light appearance over dark content: the adaptive regular glass turns dark.
    case overDark = "over-dark"

    static let size = NSSize(width: 480, height: 300)

    /// The glass surfaces, by name, in content coordinates (y up), with their corner radius
    /// and style: what the comparison measures.
    struct Surface { let name: String; let frame: NSRect; let radius: CGFloat; let clear: Bool; let tinted: Bool }
    static let surfaces: [Surface] = [
        Surface(name: "regular capsule", frame: NSRect(x: 24, y: 228, width: 180, height: 48), radius: 24, clear: false, tinted: false),
        Surface(name: "clear capsule", frame: NSRect(x: 276, y: 228, width: 180, height: 48), radius: 24, clear: true, tinted: false),
        Surface(name: "regular panel", frame: NSRect(x: 24, y: 60, width: 220, height: 120), radius: 20, clear: false, tinted: false),
        Surface(name: "tinted capsule", frame: NSRect(x: 276, y: 132, width: 180, height: 48), radius: 24, clear: false, tinted: true),
        Surface(name: "small circle", frame: NSRect(x: 340, y: 48, width: 56, height: 56), radius: 28, clear: false, tinted: false),
    ]

    var appearance: NSAppearance.Name { self == .dark ? .darkAqua : .aqua }

    // `makeContent()` (the backdrop with the glass over it) is in ReferenceSceneGlass.swift,
    // which Apple's SDK compiles for macOS 26 only; the comparison needs this file alone.
}

/// Colour bands, a black-and-white checker strip (edges for the blur and the refraction)
/// and discs; or the dark variant's deep bands.
final class GlassReferenceBackdrop: NSView {
    private let dark: Bool
    init(frame: NSRect, dark: Bool) { self.dark = dark; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let light: [NSColor] = [
            NSColor(srgbRed: 0.98, green: 0.36, blue: 0.33, alpha: 1), NSColor(srgbRed: 1.0, green: 0.78, blue: 0.25, alpha: 1),
            NSColor(srgbRed: 0.30, green: 0.75, blue: 0.40, alpha: 1), NSColor(srgbRed: 0.25, green: 0.55, blue: 0.95, alpha: 1),
            NSColor(srgbRed: 0.62, green: 0.40, blue: 0.90, alpha: 1), NSColor(srgbRed: 0.96, green: 0.96, blue: 0.96, alpha: 1),
        ]
        let deep: [NSColor] = [
            NSColor(srgbRed: 0.10, green: 0.10, blue: 0.14, alpha: 1), NSColor(srgbRed: 0.20, green: 0.06, blue: 0.10, alpha: 1),
            NSColor(srgbRed: 0.05, green: 0.14, blue: 0.10, alpha: 1), NSColor(srgbRed: 0.04, green: 0.08, blue: 0.20, alpha: 1),
            NSColor(srgbRed: 0.12, green: 0.06, blue: 0.18, alpha: 1), NSColor(srgbRed: 0.02, green: 0.02, blue: 0.02, alpha: 1),
        ]
        let colors = dark ? deep : light
        let h = bounds.height / CGFloat(colors.count)
        for (i, c) in colors.enumerated() {
            c.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: CGFloat(i) * h, width: bounds.width, height: h)).fill()
        }
        // A checker strip across the middle: 8 pt squares.
        var x: CGFloat = 0, on = false
        while x < bounds.width {
            for row in 0..<2 {
                ((on != (row == 1)) ? NSColor.black : NSColor.white).setFill()
                NSBezierPath(rect: NSRect(x: x, y: 140 + CGFloat(row) * 8, width: 8, height: 8)).fill()
            }
            x += 8; on.toggle()
        }
        // Discs crossing the glass edges.
        let discs: [(NSPoint, NSColor)] = [(NSPoint(x: 60, y: 250), .systemPink), (NSPoint(x: 330, y: 260), .systemTeal),
                                           (NSPoint(x: 200, y: 80), .systemOrange), (NSPoint(x: 400, y: 150), .systemIndigo)]
        for (p, c) in discs {
            (dark ? c.withAlphaComponent(0.6) : c).setFill()
            NSBezierPath(ovalIn: NSRect(x: p.x - 26, y: p.y - 26, width: 52, height: 52)).fill()
        }
    }
}
