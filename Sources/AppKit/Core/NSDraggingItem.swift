// NSDraggingItem (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingitem
open class NSDraggingItem: NSObject {
    private let _writer: any NSPasteboardWriting
    private var _frame: NSRect = .zero
    private var _components: [NSDraggingImageComponent]? = nil
    private var _provider: (() -> [NSDraggingImageComponent])? = nil

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingitem/init(pasteboardwriter:)
    public init(pasteboardWriter: any NSPasteboardWriting) {
        _writer = pasteboardWriter
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingitem/draggingframe
    open var draggingFrame: NSRect {
        get { _frame }
        set { _frame = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingitem/imagecomponents
    open var imageComponents: [NSDraggingImageComponent]? { _components ?? _provider?() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingitem/imagecomponentsprovider
    open var imageComponentsProvider: (() -> [NSDraggingImageComponent])? {
        get { _provider }
        set { _provider = newValue; _components = nil }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingitem/item
    open var item: Any { _writer }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingitem/setdraggingframe(_:contents:)
    open func setDraggingFrame(_ frame: NSRect, contents: Any?) {
        _frame = frame
        _provider = nil
        if let contents {
            let c = NSDraggingImageComponent(key: .icon)
            c.contents = contents
            c.frame = NSRect(origin: .zero, size: frame.size)
            _components = [c]
        } else {
            _components = nil
        }
    }

    /// The pasteboard item this drag carries: the writer's types and values.
    internal func _makePasteboardItem(for pasteboard: NSPasteboard) -> NSPasteboardItem {
        if let item = _writer as? NSPasteboardItem { return item }
        let item = NSPasteboardItem()
        for type in _writer.writableTypes(for: pasteboard) {
            guard let value = _writer.pasteboardPropertyList(forType: type) else { continue }
            if let d = value as? Data { _ = item.setData(d, forType: type) }
            else if let s = value as? String { _ = item.setString(s, forType: type) }
            else { _ = item.setPropertyList(value, forType: type) }
        }
        return item
    }
}
