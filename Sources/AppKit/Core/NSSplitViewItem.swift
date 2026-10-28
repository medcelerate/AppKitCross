// NSSplitViewItem (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem
@available(macOS 10.10, *)
@MainActor open class NSSplitViewItem: NSObject, NSAnimatablePropertyContainer, NSCoding {
    // MARK: Storage
    private let _viewController: NSViewController
    private var _behavior: NSSplitViewItem.Behavior = .default
    private var _holdingPriority = NSLayoutConstraint.Priority(250)
    private var _canCollapse = false
    private var _canCollapseFromWindowResize = false
    private var _collapseBehavior: NSSplitViewItem.CollapseBehavior = .default
    private var _isCollapsed = false
    private var _isSpringLoaded = false
    private var _minimumThickness: CGFloat = NSSplitViewItem.unspecifiedDimension
    private var _maximumThickness: CGFloat = NSSplitViewItem.unspecifiedDimension
    private var _preferredThicknessFraction: CGFloat = NSSplitViewItem.unspecifiedDimension
    private var _automaticMaximumThickness: CGFloat = NSSplitViewItem.unspecifiedDimension
    private var _allowsFullHeightLayout = false
    private var _automaticallyAdjustsSafeAreaInsets = false
    private var _titlebarSeparatorStyle: NSTitlebarSeparatorStyle = .automatic
    private var _topAccessories: [NSViewController] = []
    private var _bottomAccessories: [NSViewController] = []
    /// The split view controller owning the item.
    internal weak var _controller: NSSplitViewController? = nil

    @MainActor internal init(_viewController vc: NSViewController, behavior: NSSplitViewItem.Behavior) {
        _viewController = vc
        _behavior = behavior
        super.init()
        if behavior == .sidebar || behavior == .inspector { _canCollapse = true; _holdingPriority = NSLayoutConstraint.Priority(260) }
    }

    /// Lets the controller re-lay out when something affecting thickness changes.
    private func _changed() { _controller?._itemDidChange(self) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/init(contentlistwithviewcontroller:)
    @available(macOS 10.11, *)
    @MainActor public convenience init(contentListWithViewController viewController: NSViewController) { self.init(_viewController: viewController, behavior: .contentList) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/init(inspectorwithviewcontroller:)
    @available(macOS 11.0, *)
    @MainActor public convenience init(inspectorWithViewController viewController: NSViewController) { self.init(_viewController: viewController, behavior: .inspector) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/init(sidebarwithviewcontroller:)
    @available(macOS 10.11, *)
    @MainActor public convenience init(sidebarWithViewController viewController: NSViewController) { self.init(_viewController: viewController, behavior: .sidebar) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/init(viewcontroller:)
    @MainActor public convenience init(viewController: NSViewController) { self.init(_viewController: viewController, behavior: .default) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/addbottomalignedaccessoryviewcontroller(_:)
    @available(macOS 26.0, *)
    open func addBottomAlignedAccessoryViewController(_ childViewController: NSSplitViewItemAccessoryViewController) { _bottomAccessories.append(childViewController) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/addtopalignedaccessoryviewcontroller(_:)
    @available(macOS 26.0, *)
    open func addTopAlignedAccessoryViewController(_ childViewController: NSSplitViewItemAccessoryViewController) { _topAccessories.append(childViewController) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/allowsfullheightlayout
    @available(macOS 11.0, *)
    open var allowsFullHeightLayout: Bool {
        get { _allowsFullHeightLayout }
        set { _allowsFullHeightLayout = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/automaticmaximumthickness
    @available(macOS 10.11, *)
    open var automaticMaximumThickness: CGFloat {
        get { _automaticMaximumThickness }
        set { _automaticMaximumThickness = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/automaticallyadjustssafeareainsets
    @available(macOS 26.0, *)
    open var automaticallyAdjustsSafeAreaInsets: Bool {
        get { _automaticallyAdjustsSafeAreaInsets }
        set { _automaticallyAdjustsSafeAreaInsets = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/behavior
    @available(macOS 10.11, *)
    open var behavior: NSSplitViewItem.Behavior { _behavior }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/bottomalignedaccessoryviewcontrollers
    @available(macOS 26.0, *)
    open var bottomAlignedAccessoryViewControllers: [NSSplitViewItemAccessoryViewController] {
        get { _bottomAccessories.compactMap { $0 as? NSSplitViewItemAccessoryViewController } }
        set { _bottomAccessories = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/cancollapse
    open var canCollapse: Bool {
        get { _canCollapse }
        set { _canCollapse = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/cancollapsefromwindowresize
    @available(macOS 10.14, *)
    open var canCollapseFromWindowResize: Bool {
        get { _canCollapseFromWindowResize }
        set { _canCollapseFromWindowResize = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/collapsebehavior
    @available(macOS 10.11, *)
    open var collapseBehavior: NSSplitViewItem.CollapseBehavior {
        get { _collapseBehavior }
        set { _collapseBehavior = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/holdingpriority
    open var holdingPriority: NSLayoutConstraint.Priority {
        get { _holdingPriority }
        set { _holdingPriority = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/insertbottomalignedaccessoryviewcontroller(_:at:)
    @available(macOS 26.0, *)
    open func insertBottomAlignedAccessoryViewController(_ childViewController: NSSplitViewItemAccessoryViewController, at index: Int) { _bottomAccessories.insert(childViewController, at: min(index, _bottomAccessories.count)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/inserttopalignedaccessoryviewcontroller(_:at:)
    @available(macOS 26.0, *)
    open func insertTopAlignedAccessoryViewController(_ childViewController: NSSplitViewItemAccessoryViewController, at index: Int) { _topAccessories.insert(childViewController, at: min(index, _topAccessories.count)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/iscollapsed
    open var isCollapsed: Bool {
        get { _isCollapsed }
        set { guard newValue != _isCollapsed else { return }; _isCollapsed = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/isspringloaded
    @available(macOS 10.11, *)
    open var isSpringLoaded: Bool {
        get { _isSpringLoaded }
        set { _isSpringLoaded = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/maximumthickness
    @available(macOS 10.11, *)
    open var maximumThickness: CGFloat {
        get { _maximumThickness }
        set { _maximumThickness = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/minimumthickness
    @available(macOS 10.11, *)
    open var minimumThickness: CGFloat {
        get { _minimumThickness }
        set { _minimumThickness = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/preferredthicknessfraction
    @available(macOS 10.11, *)
    open var preferredThicknessFraction: CGFloat {
        get { _preferredThicknessFraction }
        set { _preferredThicknessFraction = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/removebottomalignedaccessoryviewcontroller(at:)
    @available(macOS 26.0, *)
    open func removeBottomAlignedAccessoryViewController(at index: Int) { if _bottomAccessories.indices.contains(index) { _bottomAccessories.remove(at: index) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/removetopalignedaccessoryviewcontroller(at:)
    @available(macOS 26.0, *)
    open func removeTopAlignedAccessoryViewController(at index: Int) { if _topAccessories.indices.contains(index) { _topAccessories.remove(at: index) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/titlebarseparatorstyle
    @available(macOS 11.0, *)
    open var titlebarSeparatorStyle: NSTitlebarSeparatorStyle {
        get { _titlebarSeparatorStyle }
        set { _titlebarSeparatorStyle = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/topalignedaccessoryviewcontrollers
    @available(macOS 26.0, *)
    open var topAlignedAccessoryViewControllers: [NSSplitViewItemAccessoryViewController] {
        get { _topAccessories.compactMap { $0 as? NSSplitViewItemAccessoryViewController } }
        set { _topAccessories = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/unspecifieddimension
    @available(macOS 10.11, *)
    static public var unspecifiedDimension: CGFloat { -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitviewitem/viewcontroller
    open var viewController: NSViewController { _viewController }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { }
    // Requirement of NSCoding
    public required init?(coder: NSCoder) { return nil }
}
