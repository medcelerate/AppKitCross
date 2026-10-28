// DirectWrite-backed text through the CD2D shim.

#if os(Windows)
import Foundation
import WinSDK
import CoreGraphics
import CD2D

final class Win32Font: PlatformFontHandle {
    let format: OpaquePointer          // CD2DTextFormat*
    let pointSize: CGFloat
    let familyName: String
    let ascent: CGFloat, descent: CGFloat, leading: CGFloat, capHeight: CGFloat, xHeight: CGFloat
    let isFixedPitch: Bool
    var postScriptName: String { familyName }

    init?(family: String, size: CGFloat, weight: Int32, italic: Bool, fixedPitch: Bool) {
        let utf16 = Array(family.utf16) + [0]
        guard let fmt = utf16.withUnsafeBufferPointer({ cd2d_text_format_create($0.baseAddress, Float(size), weight, italic) }) else { return nil }
        var a: Float = 0, d: Float = 0, lg: Float = 0, ch: Float = 0, xh: Float = 0
        guard cd2d_text_format_metrics(fmt, &a, &d, &lg, &ch, &xh) else { cd2d_text_format_release(fmt); return nil }
        format = fmt
        pointSize = size
        familyName = family
        ascent = CGFloat(a); descent = CGFloat(d); leading = CGFloat(lg); capHeight = CGFloat(ch); xHeight = CGFloat(xh)
        isFixedPitch = fixedPitch
    }

    deinit { cd2d_text_format_release(format) }
}

@MainActor
final class Win32TextBackend: PlatformTextBackend {
    func makeFont(family: String?, size: CGFloat, weight: CGFloat, italic: Bool, monospaced: Bool) -> PlatformFontHandle? {
        // AppKit weight -1...1 -> DirectWrite 100...950 (regular 400, bold 700).
        let dw = Int32(min(950, max(100, (400 + weight * 750).rounded())))
        let name = family ?? (monospaced ? "Consolas" : "Segoe UI")
        return Win32Font(family: name, size: size, weight: dw, italic: italic, fixedPitch: monospaced)
    }

    private func layout(_ text: String, font: Win32Font, maxWidth: CGFloat?) -> OpaquePointer? {
        let utf16 = Array(text.utf16)
        return utf16.withUnsafeBufferPointer {
            cd2d_text_layout_create(font.format, $0.baseAddress, UInt32($0.count), Float(maxWidth ?? 1e6), 1e6, maxWidth != nil)
        }
    }

    func measure(_ text: String, font: PlatformFontHandle, maxWidth: CGFloat?) -> CGSize {
        guard let f = font as? Win32Font, let l = layout(text, font: f, maxWidth: maxWidth) else { return .zero }
        defer { cd2d_text_layout_release(l) }
        var w: Float = 0, h: Float = 0, b: Float = 0
        cd2d_text_layout_metrics(l, &w, &h, &b)
        return CGSize(width: CGFloat(w).rounded(.up), height: CGFloat(h).rounded(.up))
    }

    func draw(_ text: String, font: PlatformFontHandle, color: CGColor, topLeft: CGPoint, maxWidth: CGFloat?, flipped: Bool, in context: CGContext) {
        guard let f = font as? Win32Font, let l = layout(text, font: f, maxWidth: maxWidth) else { return }
        defer { cd2d_text_layout_release(l) }
        context.drawTextLayout(l, topLeft: topLeft, flipped: flipped, color: color)
    }
}
#endif
