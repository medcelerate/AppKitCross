// NSSecureTextFieldCell (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(QuartzCore)
import QuartzCore
#endif
#if canImport(CoreText)
import CoreText
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nssecuretextfieldcell
@MainActor open class NSSecureTextFieldCell: NSTextFieldCell {
    private var _echosBullets = true

    @MainActor internal override func _copyCellState(from other: NSCell) {
        super._copyCellState(from: other)
        if let o = other as? NSSecureTextFieldCell { _echosBullets = o._echosBullets }
    }

    /// One bullet per character, or nothing when the cell does not echo.
    @MainActor internal override var _displayedString: String {
        _echosBullets ? String(repeating: "\u{2022}", count: stringValue.count) : ""
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssecuretextfieldcell/echosbullets
    @MainActor open var echosBullets: Bool {
        get { _echosBullets }
        set {
            _echosBullets = newValue
            // The field editor follows while it shows this cell's text.
            if let field = controlView as? NSSecureTextField, let editor = field.currentEditor() as? NSTextView {
                editor._layoutManager._secureEcho = newValue ? "\u{2022}" : ""
            }
            _changed()
        }
    }
}

/// What a secure field's editor lays out: one echo per character, padded with zero-width
/// spaces so every UTF-16 offset still maps to the same offset in the real text.
enum _NSSecureEcho {
    static func mask(_ text: String, with echo: String) -> String {
        let echoUnit: UInt16 = echo.utf16.first ?? 0x200B
        var units: [UInt16] = []
        units.reserveCapacity(text.utf16.count)
        for ch in text {
            let n = String(ch).utf16.count
            // Line breaks stay (a field editor shows one line anyway; offsets stay put).
            if ch.isNewline { units.append(contentsOf: String(ch).utf16); continue }
            units.append(echoUnit)
            if n > 1 { units.append(contentsOf: repeatElement(0x200B, count: n - 1)) }
        }
        return String(decoding: units, as: UTF16.self)
    }
}
