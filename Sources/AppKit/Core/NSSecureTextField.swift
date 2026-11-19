// NSSecureTextField (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nssecuretextfield
/// A text field that shows bullets for its text and edits in the window's secure field
/// editor (`NSWindow.fieldEditor(_:for:)`), whose layout draws one bullet per character
/// and which never copies, cuts or drags the text out.
@MainActor open class NSSecureTextField: NSTextField {
    @MainActor open override class func _makeDefaultCell() -> NSCell? { NSSecureTextFieldCell(textCell: "") }
}
