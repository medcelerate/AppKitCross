// NSTabViewController (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewcontroller
@available(macOS 10.10, *)
@MainActor open class NSTabViewController: NSViewController, NSTabViewDelegate, NSToolbarDelegate {
    // MARK: Storage
    private var _tabView: NSTabView? = nil
    private var _tabStyle: NSTabViewController.TabStyle = .segmentedControlOnTop
    private var _transitionOptions: NSViewController.TransitionOptions = .crossfade
    private var _canPropagateTitle = true

    open override func loadView() {
        view = tabView
    }

    open override func addChild(_ childViewController: NSViewController) {
        if tabViewItem(for: childViewController) == nil {
            addTabViewItem(NSTabViewItem(viewController: childViewController))
        } else {
            super.addChild(childViewController)
        }
    }

    open override func insertChild(_ childViewController: NSViewController, at index: Int) {
        if tabViewItem(for: childViewController) == nil {
            insertTabViewItem(NSTabViewItem(viewController: childViewController), at: index)
        } else {
            super.insertChild(childViewController, at: index)
        }
    }

    open override func removeChild(at index: Int) {
        guard children.indices.contains(index) else { return }
        if let item = tabViewItem(for: children[index]) { removeTabViewItem(item) } else { super.removeChild(at: index) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewcontroller/addtabviewitem(_:)
    @MainActor open func addTabViewItem(_ tabViewItem: NSTabViewItem) { insertTabViewItem(tabViewItem, at: tabView.numberOfTabViewItems) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewcontroller/canpropagateselectedchildviewcontrollertitle
    @MainActor open var canPropagateSelectedChildViewControllerTitle: Bool {
        get { _canPropagateTitle }
        set { _canPropagateTitle = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewcontroller/inserttabviewitem(_:at:)
    @MainActor open func insertTabViewItem(_ tabViewItem: NSTabViewItem, at index: Int) {
        if let vc = tabViewItem.viewController, !children.contains(where: { $0 === vc }) { super.insertChild(vc, at: min(index, children.count)) }
        tabView.insertTabViewItem(tabViewItem, at: index)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewcontroller/removetabviewitem(_:)
    @MainActor open func removeTabViewItem(_ tabViewItem: NSTabViewItem) {
        tabView.removeTabViewItem(tabViewItem)
        if let vc = tabViewItem.viewController, let i = children.firstIndex(where: { $0 === vc }) { super.removeChild(at: i) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewcontroller/selectedtabviewitemindex
    @MainActor open var selectedTabViewItemIndex: Int {
        get { tabView.selectedTabViewItem.map { tabView.indexOfTabViewItem($0) } ?? -1 }
        set { tabView.selectTabViewItem(at: newValue) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewcontroller/tabstyle
    @MainActor open var tabStyle: NSTabViewController.TabStyle {
        get { _tabStyle }
        set {
            _tabStyle = newValue
            switch newValue {
            case .segmentedControlOnTop: tabView.tabPosition = .top
            case .segmentedControlOnBottom: tabView.tabPosition = .bottom
            default: tabView.tabPosition = .none
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewcontroller/tabview
    @MainActor open var tabView: NSTabView {
        get {
            if let t = _tabView { return t }
            let t = NSTabView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
            t.delegate = self
            _tabView = t
            return t
        }
        set {
            _tabView = newValue
            newValue.delegate = self
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewcontroller/tabview(_:didselect:)
    @MainActor open func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        if _canPropagateTitle, let t = tabViewItem?.viewController?.title { title = t }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewcontroller/tabview(_:shouldselect:)
    @MainActor open func tabView(_ tabView: NSTabView, shouldSelect tabViewItem: NSTabViewItem?) -> Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewcontroller/tabview(_:willselect:)
    @MainActor open func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewcontroller/tabviewitem(for:)
    @MainActor open func tabViewItem(for viewController: NSViewController) -> NSTabViewItem? { tabView.tabViewItems.first { $0.viewController === viewController } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewcontroller/tabviewitems
    @MainActor open var tabViewItems: [NSTabViewItem] {
        get { tabView.tabViewItems }
        set {
            for item in tabView.tabViewItems { removeTabViewItem(item) }
            for item in newValue { addTabViewItem(item) }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewcontroller/toolbar(_:itemforitemidentifier:willbeinsertedintotoolbar:)
    @MainActor open func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewcontroller/toolbaralloweditemidentifiers(_:)
    @MainActor open func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewcontroller/toolbardefaultitemidentifiers(_:)
    @MainActor open func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewcontroller/toolbarselectableitemidentifiers(_:)
    @MainActor open func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewcontroller/transitionoptions
    @MainActor open var transitionOptions: NSViewController.TransitionOptions {
        get { _transitionOptions }
        set { _transitionOptions = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabviewcontroller/viewdidload()
    @MainActor open override func viewDidLoad() { super.viewDidLoad() }
    // SKIPPED (Foundation.NSExtensionContext not in corelibs): func beginRequest(with context: NSExtensionContext)
}
