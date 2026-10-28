// NSTabViewItem (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewitem
@MainActor open class NSTabViewItem: NSObject, NSCoding {
    // MARK: Storage
    private var _identifier: Any? = nil
    private var _label = ""
    private var _image: NSImage? = nil
    private var _color: NSColor = .controlColor
    private var _toolTip: String? = nil
    private var _initialFirstResponder: NSView? = nil
    private var _view: NSView? = nil
    private var _viewController: NSViewController? = nil
    internal weak var _tabView: NSTabView? = nil
    internal var _tabState: NSTabViewItem.State = .backgroundTab

    public override init() { super.init() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewitem/init(identifier:)
    public init(identifier: Any?) {
        _identifier = identifier
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewitem/init(viewcontroller:)
    @available(macOS 10.10, *)
    public convenience init(viewController: NSViewController) {
        self.init(identifier: nil)
        self.viewController = viewController
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewitem/color
    open var color: NSColor {
        get { _color }
        set { _color = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewitem/drawlabel(_:in:)
    open func drawLabel(_ shouldTruncateLabel: Bool, in labelRect: NSRect) {
        let font = _tabView?.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let color: NSColor = _tabState == .selectedTab ? .controlTextColor : .secondaryLabelColor
        let text = label
        let size = text.size(withAttributes: [.font: font])
        let origin = NSPoint(x: labelRect.midX - size.width / 2, y: labelRect.midY - size.height / 2)
        text.draw(at: origin, withAttributes: [.font: font, .foregroundColor: color])
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewitem/identifier
    open var identifier: Any? {
        get { _identifier }
        set { _identifier = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewitem/image
    @available(macOS 10.10, *)
    open var image: NSImage? {
        get { _image }
        set { _image = newValue; _tabView?.needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewitem/initialfirstresponder
    open var initialFirstResponder: NSView? {
        get { _initialFirstResponder }
        set { _initialFirstResponder = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewitem/label
    open var label: String {
        get { _label.isEmpty ? (_viewController?.title ?? "") : _label }
        set { _label = newValue; _tabView?._tabsChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewitem/sizeoflabel(_:)
    open func sizeOfLabel(_ computeMin: Bool) -> NSSize {
        let font = _tabView?.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let s = label.size(withAttributes: [.font: font])
        return NSSize(width: s.width.rounded(.up) + 16, height: s.height.rounded(.up))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewitem/tabstate
    open var tabState: NSTabViewItem.State { _tabState }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewitem/tabview
    open var tabView: NSTabView? { _tabView }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewitem/tooltip
    open var toolTip: String? {
        get { _toolTip }
        set { _toolTip = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewitem/view
    open var view: NSView? {
        get { _view ?? _viewController?.view }
        set { _view = newValue; _tabView?._itemViewChanged(self) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewitem/viewcontroller
    @available(macOS 10.10, *)
    open var viewController: NSViewController? {
        get { _viewController }
        set { _viewController = newValue; _tabView?._itemViewChanged(self) }
    }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { }
    // Requirement of NSCoding
    public required init?(coder: NSCoder) { return nil }
}
