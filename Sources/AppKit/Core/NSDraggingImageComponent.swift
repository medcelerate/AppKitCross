// NSDraggingImageComponent (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingimagecomponent
open class NSDraggingImageComponent: NSObject {
    private var _key: NSDraggingItem.ImageComponentKey
    private var _contents: Any? = nil
    private var _frame: NSRect = .zero

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingimagecomponent/init(key:)
    public init(key: NSDraggingItem.ImageComponentKey) {
        _key = key
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingimagecomponent/contents
    open var contents: Any? {
        get { _contents }
        set { _contents = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingimagecomponent/frame
    open var frame: NSRect {
        get { _frame }
        set { _frame = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingimagecomponent/key
    open var key: NSDraggingItem.ImageComponentKey {
        get { _key }
        set { _key = newValue }
    }
}
