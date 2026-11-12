// NSScrubberTextItemView (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// An item showing a title in a label centred in the item (ADR-0034).

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubbertextitemview
@available(macOS 10.12, *)
@MainActor open class NSScrubberTextItemView: NSScrubberItemView {
    private let _textField = NSTextField(labelWithString: "")

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        _setUp()
    }
    /// Also how a scrubber makes a registered item view.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        _setUp()
    }
    private func _setUp() {
        _textField.alignment = .center
        _textField.lineBreakMode = .byTruncatingTail
        addSubview(_textField)
        _placeLabel()
    }
    open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        _placeLabel()
    }
    private func _placeLabel() {
        let h = min(bounds.height, max(_textField.intrinsicContentSize.height, 0))
        _textField.frame = NSRect(x: 4, y: ((bounds.height - h) / 2).rounded(.down), width: max(0, bounds.width - 8), height: h)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubbertextitemview/textfield
    @MainActor open var textField: NSTextField { _textField }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubbertextitemview/title
    @MainActor open var title: String {
        get { _textField.stringValue }
        set { _textField.stringValue = newValue; _placeLabel() }
    }
}
