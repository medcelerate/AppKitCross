// NSTableCellView (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecellview
@MainActor open class NSTableCellView: NSView {
    private var _backgroundStyle: NSView.BackgroundStyle = .normal
    private weak var _imageView: NSImageView?
    private var _objectValue: Any?
    private var _rowSizeStyle: NSTableView.RowSizeStyle = .default
    private weak var _textField: NSTextField?

    @MainActor public override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    public required init?(coder: NSCoder) { unimplemented() }

    @MainActor open override var isFlipped: Bool { true }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecellview/backgroundstyle
    @MainActor open var backgroundStyle: NSView.BackgroundStyle {
        get { _backgroundStyle }
        set {
            _backgroundStyle = newValue
            // Emphasized rows (selected in a key window) show light text, as AppKit's cells do.
            if let f = _textField { f.cell?.backgroundStyle = newValue; f.needsDisplay = true }
            needsDisplay = true
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecellview/draggingimagecomponents
    @MainActor open var draggingImageComponents: [NSDraggingImageComponent] { [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecellview/imageview
    @MainActor open var imageView: NSImageView? {
        get { _imageView }
        set { _imageView = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecellview/objectvalue
    @MainActor open var objectValue: Any? {
        get { _objectValue }
        set { _objectValue = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecellview/rowsizestyle
    @MainActor open var rowSizeStyle: NSTableView.RowSizeStyle {
        get { _rowSizeStyle }
        set { _rowSizeStyle = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecellview/textfield
    @MainActor open var textField: NSTextField? {
        get { _textField }
        set { _textField = newValue }
    }

    // MARK: Accessibility (ADR-0013)
    // AXCell: its text field and image view are its children.
    @MainActor open override func isAccessibilityElement() -> Bool { _a11y.isElement ?? true }
    @MainActor open override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .cell }
    @MainActor open override func accessibilityLabel() -> String? { _a11y.label ?? _textField?.stringValue }
    @MainActor open override func isAccessibilitySelected() -> Bool { _a11y.isSelected ?? ((superview as? NSTableRowView)?.isSelected ?? false) }
    @MainActor override func _accessibilityIsFocusable() -> Bool { false }

    /// A cell view with one label filling it, for tables whose delegate provides no views.
    internal static func _makeLabelCell(frame: NSRect) -> NSTableCellView {
        let cell = NSTableCellView(frame: frame)
        cell.identifier = NSUserInterfaceItemIdentifier("AppKitWin.TextCell")
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 2, y: 0, width: max(0, frame.width - 4), height: frame.height)
        label.autoresizingMask = [.width, .height]
        cell.addSubview(label)
        cell.textField = label
        return cell
    }
}
