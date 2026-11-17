import AppKit
import SwiftUI

/// Sizes and spacing for the rendered (viewer) side. Everything scales off `bodySize`
/// so ⌘+ / ⌘- can resize the whole document proportionally.
struct MDTheme: Sendable {
    var bodySize: CGFloat

    var blockSpacing: CGFloat { bodySize * 0.95 }
    var tightSpacing: CGFloat { bodySize * 0.28 }
    var codeSize: CGFloat { bodySize * 0.88 }
    var maxWidth: CGFloat { max(560, bodySize * 46) }

    func headingSize(_ level: Int) -> CGFloat {
        let scale: [CGFloat] = [2.0, 1.55, 1.28, 1.12, 1.0, 0.92]
        return bodySize * scale[min(max(level, 1), 6) - 1]
    }

    func headingTopSpace(_ level: Int) -> CGFloat {
        switch level {
        case 1: return bodySize * 0.7
        case 2: return bodySize * 0.55
        default: return bodySize * 0.35
        }
    }
}

enum MDFont {
    /// One place that knows how to combine bold + italic + monospace, which
    /// `Font.system(...)` can't express for mono + italic.
    static func make(size: CGFloat,
                     bold: Bool = false,
                     italic: Bool = false,
                     mono: Bool = false,
                     weight: NSFont.Weight = .regular) -> NSFont {
        var font: NSFont = mono
            ? .monospacedSystemFont(ofSize: size, weight: bold ? .semibold : weight)
            : .systemFont(ofSize: size, weight: bold ? .bold : weight)
        if italic {
            let descriptor = font.fontDescriptor.withSymbolicTraits(.italic)
            font = NSFont(descriptor: descriptor, size: size) ?? font
        }
        return font
    }
}

extension NSColor {
    /// Appearance-aware color without needing an asset catalog.
    static func mdDynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}
