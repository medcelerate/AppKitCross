// NSSplitViewController (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewcontroller
@available(macOS 10.10, *)
@MainActor open class NSSplitViewController: NSViewController, NSSplitViewDelegate, NSUserInterfaceValidations {
    // MARK: Storage
    private var _items: [NSSplitViewItem] = []
    private var _splitView: NSSplitView? = nil
    private var _minimumThicknessForInlineSidebars: CGFloat = 0

    open override func loadView() {
        view = splitView
    }

    /// Re-applies item thickness limits and collapse state after an item changed.
    internal func _itemDidChange(_ item: NSSplitViewItem) {
        guard isViewLoaded, let i = _items.firstIndex(where: { $0 === item }) else { return }
        splitView.setHoldingPriority(item.holdingPriority, forSubviewAt: i)
        if splitView.isSubviewCollapsed(item.viewController.view) != item.isCollapsed {
            splitView._setCollapsed(item.viewController.view, item.isCollapsed)
        }
        _enforceThickness()
    }

    private func _enforceThickness() {
        for item in _items where !item.isCollapsed {
            let v = item.viewController.view
            var size = splitView.isVertical ? v.frame.width : v.frame.height
            if item.minimumThickness >= 0 { size = max(size, item.minimumThickness) }
            if item.maximumThickness >= 0 { size = min(size, item.maximumThickness) }
            if size != (splitView.isVertical ? v.frame.width : v.frame.height) {
                v.setFrameSize(splitView.isVertical ? NSSize(width: size, height: v.frame.height) : NSSize(width: v.frame.width, height: size))
            }
        }
        splitView.needsLayout = true
    }

    /// Collapses or expands the first item with `behavior`.
    private func _toggle(_ behavior: NSSplitViewItem.Behavior) {
        guard let item = _items.first(where: { $0.behavior == behavior }) else { return }
        item.isCollapsed.toggle()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewcontroller/addsplitviewitem(_:)
    @MainActor open func addSplitViewItem(_ splitViewItem: NSSplitViewItem) { insertSplitViewItem(splitViewItem, at: _items.count) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewcontroller/automaticdimension
    @available(macOS 10.11, *)
    static public var automaticDimension: CGFloat { -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewcontroller/insertsplitviewitem(_:at:)
    @MainActor open func insertSplitViewItem(_ splitViewItem: NSSplitViewItem, at index: Int) {
        let i = min(index, _items.count)
        _items.insert(splitViewItem, at: i)
        splitViewItem._controller = self
        insertChild(splitViewItem.viewController, at: i)
        let v = splitViewItem.viewController.view
        splitView.insertArrangedSubview(v, at: i)
        splitView.setHoldingPriority(splitViewItem.holdingPriority, forSubviewAt: i)
        if splitViewItem.isCollapsed { splitView._setCollapsed(v, true) }
        _enforceThickness()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewcontroller/minimumthicknessforinlinesidebars
    @available(macOS 10.11, *)
    @MainActor open var minimumThicknessForInlineSidebars: CGFloat {
        get { _minimumThicknessForInlineSidebars }
        set { _minimumThicknessForInlineSidebars = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewcontroller/removesplitviewitem(_:)
    @MainActor open func removeSplitViewItem(_ splitViewItem: NSSplitViewItem) {
        guard let i = _items.firstIndex(where: { $0 === splitViewItem }) else { return }
        _items.remove(at: i)
        splitViewItem._controller = nil
        let v = splitViewItem.viewController.view
        splitView.removeArrangedSubview(v)
        v.removeFromSuperview()
        splitViewItem.viewController.removeFromParent()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewcontroller/splitview
    @MainActor open var splitView: NSSplitView {
        get {
            if let s = _splitView { return s }
            let s = NSSplitView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
            s.isVertical = true
            s.dividerStyle = .thin
            s.delegate = self
            _splitView = s
            return s
        }
        set {
            _splitView = newValue
            newValue.delegate = self
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewcontroller/splitview(_:additionaleffectiverectofdividerat:)
    @MainActor open func splitView(_ splitView: NSSplitView, additionalEffectiveRectOfDividerAt dividerIndex: Int) -> NSRect { .zero }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewcontroller/splitview(_:cancollapsesubview:)
    @MainActor open func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { _items.first { $0.viewController.viewIfLoaded === subview }?.canCollapse ?? false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewcontroller/splitview(_:effectiverect:fordrawnrect:ofdividerat:)
    @MainActor open func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect { proposedEffectiveRect }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewcontroller/splitview(_:shouldcollapsesubview:fordoubleclickondividerat:)
    @MainActor open func splitView(_ splitView: NSSplitView, shouldCollapseSubview subview: NSView, forDoubleClickOnDividerAt dividerIndex: Int) -> Bool { self.splitView(splitView, canCollapseSubview: subview) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewcontroller/splitview(_:shouldhidedividerat:)
    @MainActor open func splitView(_ splitView: NSSplitView, shouldHideDividerAt dividerIndex: Int) -> Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewcontroller/splitviewitem(for:)
    @MainActor open func splitViewItem(for viewController: NSViewController) -> NSSplitViewItem? { _items.first { $0.viewController === viewController } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewcontroller/splitviewitems
    @MainActor open var splitViewItems: [NSSplitViewItem] {
        get { _items }
        set {
            for item in _items { removeSplitViewItem(item) }
            for item in newValue { addSplitViewItem(item) }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewcontroller/toggleinspector(_:)
    @available(macOS 14.0, *)
    @MainActor open func toggleInspector(_ sender: Any?) { _toggle(.inspector) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewcontroller/togglesidebar(_:)
    @available(macOS 10.11, *)
    @MainActor open func toggleSidebar(_ sender: Any?) { _toggle(.sidebar) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewcontroller/validateuserinterfaceitem(_:)
    @available(macOS 10.11, *)
    @MainActor open func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewcontroller/viewdidload()
    @MainActor open override func viewDidLoad() { super.viewDidLoad() }
    // SKIPPED (Foundation.NSExtensionContext not in corelibs): func beginRequest(with context: NSExtensionContext)
}
