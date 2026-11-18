// NSPathControlItem (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// One component of a path control: a title, an optional image and the URL of the path
// up to it (set by the control when it builds the items from its URL).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcontrolitem
@available(macOS 10.10, *)
open class NSPathControlItem: NSObject {
    private var _attributedTitle = NSAttributedString(string: "")
    private var _image: NSImage? = nil
    internal var _url: URL? = nil

    public override init() { super.init() }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcontrolitem/attributedtitle
    open var attributedTitle: NSAttributedString {
        get { _attributedTitle }
        set { _attributedTitle = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcontrolitem/image
    open var image: NSImage? {
        get { _image }
        set { _image = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcontrolitem/title
    open var title: String {
        get { _attributedTitle.string }
        set { _attributedTitle = NSAttributedString(string: newValue) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcontrolitem/url
    open var url: URL? { _url }
}
