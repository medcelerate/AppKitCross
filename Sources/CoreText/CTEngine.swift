// The platform seam of the CoreText module (ADR-0007): everything that needs a real font
// engine. Pango/HarfBuzz implement it on Linux, DirectWrite on Windows. Typesetting, line
// breaking, frames and drawing orchestration are shared Swift on top of this.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A loaded face at a size.
protocol CTEngineFont: AnyObject {
    var size: CGFloat { get }
    var ascent: CGFloat { get }            // positive, points
    var descent: CGFloat { get }           // positive, points
    var leading: CGFloat { get }
    var capHeight: CGFloat { get }
    var xHeight: CGFloat { get }
    var underlinePosition: CGFloat { get } // negative below the baseline, points
    var underlineThickness: CGFloat { get }
    var unitsPerEm: UInt32 { get }
    var glyphCount: Int { get }
    var familyName: String { get }
    var styleName: String { get }
    var fullName: String { get }
    var postScriptName: String { get }
    var isBold: Bool { get }
    var isItalic: Bool { get }
    var isMonospace: Bool { get }
    /// -1...1 (regular 0, bold ~0.4) and the slant in the same unit CoreText reports.
    var weight: CGFloat { get }
    var slant: CGFloat { get }
    var boundingBox: CGRect { get }

    func glyphs(for units: [UInt16]) -> [CGGlyph]    // 0 for unmapped characters; one per UTF-16 unit, trailing surrogate 0
    func advances(for glyphs: [CGGlyph]) -> [CGSize]
    func boundingRects(for glyphs: [CGGlyph]) -> [CGRect]
    func path(for glyph: CGGlyph) -> CGPath?
    func hasTable(_ tag: UInt32) -> Bool
    func table(_ tag: UInt32) -> Data?
    func availableTables() -> [UInt32]
    func glyph(named name: String) -> CGGlyph
    /// Draws glyphs with their origins at `positions` (user space of `ctx`, y up) in `color`.
    func draw(glyphs: [CGGlyph], positions: [CGPoint], color: CGColor, in ctx: CGContext)
    /// The same face at another size.
    func withSize(_ size: CGFloat) -> CTEngineFont
}

/// One shaped stretch of text in a single resolved font.
struct CTShapedRun {
    var font: CTEngineFont
    var glyphs: [CGGlyph]
    var advances: [CGFloat]        // horizontal advance per glyph, points
    var offsets: [CGPoint]         // glyph offset from the pen, points
    var clusters: [Int]            // UTF-16 index (relative to the shaped text) of each glyph's cluster start
    var range: NSRange             // the substring this run covers, relative to the shaped text
    var isRightToLeft: Bool
}

protocol CTEngine: AnyObject {
    /// A font by family or PostScript name; nil when the name is unknown. `family` nil is the
    /// UI font for `uiType`.
    func makeFont(name: String?, size: CGFloat, weight: CGFloat?, italic: Bool?, uiType: CTFontUIFontType) -> CTEngineFont?
    /// All installed family names.
    var familyNames: [String] { get }
    /// The faces (typefaces) of an installed family at `size`, regular first. Engines that
    /// cannot enumerate faces probe the standard four (regular, bold, italic, bold italic).
    func faces(inFamily family: String, size: CGFloat) -> [CTEngineFont]
    /// Shapes `units` (UTF-16) in `font`, substituting fallback fonts for characters the font
    /// lacks. Runs come back in string order.
    func shape(_ units: [UInt16], font: CTEngineFont, language: String?) -> [CTShapedRun]
}

extension CTEngine {
    func faces(inFamily family: String, size: CGFloat) -> [CTEngineFont] {
        var out: [CTEngineFont] = []
        for (weight, italic) in [(CGFloat(0), false), (0.4, false), (0, true), (0.4, true)] {
            guard let f = makeFont(name: family, size: size, weight: weight, italic: italic, uiType: .none),
                  f.familyName.lowercased() == family.lowercased() || f.familyName.replacingOccurrences(of: " ", with: "").lowercased() == family.replacingOccurrences(of: " ", with: "").lowercased(),
                  !out.contains(where: { $0.postScriptName == f.postScriptName }) else { continue }
            out.append(f)
        }
        return out
    }
}

enum CTRuntime {
    nonisolated(unsafe) static var engine: CTEngine = {
        #if os(Linux)
        return CTPangoEngine()
        #elseif os(Windows)
        return CTDirectWriteEngine()
        #else
        fatalError("CoreText: no engine for this platform")
        #endif
    }()
}
