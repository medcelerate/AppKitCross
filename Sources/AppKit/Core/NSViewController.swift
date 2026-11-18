// NSViewController (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller
@MainActor open class NSViewController: NSResponder, NSEditor, NSSeguePerforming, NSUserInterfaceItemIdentification {
    // MARK: Storage
    private var _view: NSView? = nil
    private var _children: [NSViewController] = []
    private weak var _parent: NSViewController? = nil
    private var _title: String? = nil
    private var _representedObject: Any? = nil
    private var _preferredContentSize = NSSize.zero
    private var _preferredScreenOrigin = NSPoint.zero
    private var _sourceItemView: NSView? = nil
    private let _nibName: NSNib.Name?
    private let _nibBundle: Bundle?
    private var _presented: [NSViewController] = []
    private weak var _presenting: NSViewController? = nil
    internal var _presentedWindow: NSWindow? = nil
    /// The popover `present(_:asPopoverRelativeTo:…)` showed this controller in.
    internal var _presentedPopover: NSPopover? = nil
    private var _presentationAnimator: (any NSViewControllerPresentationAnimator)? = nil

    @MainActor public convenience override init() { self.init(nibName: nil, bundle: nil) }

    private func _presentInWindow(_ viewController: NSViewController, title: String?) {
        let w = NSWindow(contentViewController: viewController)
        w.title = title ?? viewController.title ?? ""
        viewController._presenting = self
        viewController._presentedWindow = w
        _presented.append(viewController)
        w.center()
        _ = NSApplication.shared.runModal(for: w)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/init(coder:)
    public required init?(coder: NSCoder) {
        _nibName = nil
        _nibBundle = nil
        super.init(coder: coder)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/init(nibname:bundle:)
    @MainActor public init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        _nibName = nibNameOrNil
        _nibBundle = nibBundleOrNil
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/addchild(_:)
    @available(macOS 10.10, *)
    @MainActor open func addChild(_ childViewController: NSViewController) { insertChild(childViewController, at: _children.count) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/children
    @available(macOS 10.10, *)
    @MainActor open var children: [NSViewController] {
        get { _children }
        set {
            for c in _children { c._parent = nil }
            _children = []
            for c in newValue { addChild(c) }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/commitediting()
    @MainActor open func commitEditing() -> Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/commitediting(withdelegate:didcommit:contextinfo:)
    @MainActor open func commitEditing(withDelegate delegate: Any?, didCommit didCommitSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/discardediting()
    @MainActor open func discardEditing() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/dismiss(_:)
    @available(macOS 10.10, *)
    @MainActor open func dismiss(_ viewController: NSViewController) {
        guard let i = _presented.firstIndex(where: { $0 === viewController }) else { return }
        _presented.remove(at: i)
        if let w = viewController._presentedWindow {
            if NSApplication.shared.modalWindow === w { NSApplication.shared.stopModal() }
            w.close()
            viewController._presentedWindow = nil
        } else if let p = viewController._presentedPopover {
            viewController._presentedPopover = nil
            p.close()
        } else if let a = viewController._presentationAnimator {
            a.animateDismissal(of: viewController, from: self)
            viewController._presentationAnimator = nil
        }
        viewController._presenting = nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/dismiss(_:)
    @available(macOS 10.10, *)
    @MainActor open func dismiss(_ sender: Any?) { _presenting?.dismiss(self) }
    // SKIPPED (Foundation.NSExtensionContext not in corelibs): @MainActor var extensionContext: NSExtensionContext? { get }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/insertchild(_:at:)
    @available(macOS 10.10, *)
    @MainActor open func insertChild(_ childViewController: NSViewController, at index: Int) {
        childViewController.removeFromParent()
        _children.insert(childViewController, at: min(index, _children.count))
        childViewController._parent = self
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/isviewloaded
    @available(macOS 10.10, *)
    @MainActor open var isViewLoaded: Bool { _view != nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/loadview()
    @MainActor open func loadView() {
        // Without a nib AppKit gives the controller an empty view.
        view = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/loadviewifneeded()
    @available(macOS 14.0, *)
    @MainActor open func loadViewIfNeeded() {
        guard _view == nil else { return }
        loadView()
        precondition(_view != nil, "NSViewController: loadView() must set `view`")
        viewDidLoad()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/nibbundle
    @MainActor open var nibBundle: Bundle? { _nibBundle }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/nibname
    @MainActor open var nibName: NSNib.Name? { _nibName }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/parent
    @available(macOS 10.10, *)
    @MainActor open var parent: NSViewController? { _parent }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/preferredcontentsize
    @available(macOS 10.10, *)
    @MainActor open var preferredContentSize: NSSize {
        get { _preferredContentSize }
        set { _preferredContentSize = newValue; _parent?.preferredContentSizeDidChange(for: self) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/preferredcontentsizedidchange(for:)
    @available(macOS 10.10, *)
    @MainActor open func preferredContentSizeDidChange(for viewController: NSViewController) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/preferredmaximumsize
    @available(macOS 10.10, *)
    @MainActor open var preferredMaximumSize: NSSize { NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/preferredminimumsize
    @available(macOS 10.10, *)
    @MainActor open var preferredMinimumSize: NSSize { .zero }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/preferredscreenorigin
    @available(macOS 10.10, *)
    @MainActor open var preferredScreenOrigin: NSPoint {
        get { _preferredScreenOrigin }
        set { _preferredScreenOrigin = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/present(_:animator:)
    @available(macOS 10.10, *)
    @MainActor open func present(_ viewController: NSViewController, animator: any NSViewControllerPresentationAnimator) {
        viewController._presenting = self
        viewController._presentationAnimator = animator
        _presented.append(viewController)
        animator.animatePresentation(of: viewController, from: self)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/present(_:aspopoverrelativeto:of:preferrededge:behavior:)
    @available(macOS 10.10, *)
    @MainActor open func present(_ viewController: NSViewController, asPopoverRelativeTo positioningRect: NSRect, of positioningView: NSView, preferredEdge: NSRectEdge, behavior: NSPopover.Behavior) {
        let popover = NSPopover()
        popover.contentViewController = viewController
        popover.behavior = behavior
        viewController._presenting = self
        viewController._presentedPopover = popover
        _presented.append(viewController)
        popover.show(relativeTo: positioningRect, of: positioningView, preferredEdge: preferredEdge)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/present(_:aspopoverrelativeto:of:preferrededge:behavior:hasfullsizecontent:)
    @available(macOS 14.0, *)
    @MainActor open func present(_ viewController: NSViewController, asPopoverRelativeTo positioningRect: NSRect, of positioningView: NSView, preferredEdge: NSRectEdge, behavior: NSPopover.Behavior, hasFullSizeContent: Bool) {
        present(viewController, asPopoverRelativeTo: positioningRect, of: positioningView, preferredEdge: preferredEdge, behavior: behavior)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/presentasmodalwindow(_:)
    @available(macOS 10.10, *)
    @MainActor open func presentAsModalWindow(_ viewController: NSViewController) { _presentInWindow(viewController, title: viewController.title) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/presentassheet(_:)
    @available(macOS 10.10, *)
    @MainActor open func presentAsSheet(_ viewController: NSViewController) {
        // Sheets attach to the window in AppKit; here they run as a modal window over it.
        _presentInWindow(viewController, title: "")
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/presentedviewcontrollers
    @available(macOS 10.10, *)
    @MainActor open var presentedViewControllers: [NSViewController]? { _presented.isEmpty ? nil : _presented }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/presentingviewcontroller
    @available(macOS 10.10, *)
    @MainActor open var presentingViewController: NSViewController? { _presenting }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/removechild(at:)
    @available(macOS 10.10, *)
    @MainActor open func removeChild(at index: Int) {
        guard _children.indices.contains(index) else { return }
        let c = _children.remove(at: index)
        c._parent = nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/removefromparent()
    @available(macOS 10.10, *)
    @MainActor open func removeFromParent() {
        guard let p = _parent, let i = p._children.firstIndex(where: { $0 === self }) else { return }
        p.removeChild(at: i)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/representedobject
    @MainActor open var representedObject: Any? {
        get { _representedObject }
        set { _representedObject = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/sourceitemview
    @available(macOS 10.10, *)
    @MainActor open var sourceItemView: NSView? {
        get { _sourceItemView }
        set { _sourceItemView = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/storyboard
    @available(macOS 10.10, *)
    @MainActor open var storyboard: NSStoryboard? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/title
    @MainActor open var title: String? {
        get { _title }
        set { _title = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/transition(from:to:options:)
    @available(macOS 10.10, *)
    @MainActor open func transition(from fromViewController: NSViewController, to toViewController: NSViewController, options: NSViewController.TransitionOptions = []) async {
        transition(from: fromViewController, to: toViewController, options: options, completionHandler: nil)
    }

    /// Swaps the child views in place (both controllers must be children).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/transition(from:to:options:completionhandler:)
    @MainActor open func transition(from fromViewController: NSViewController, to toViewController: NSViewController, options: NSViewController.TransitionOptions = [], completionHandler completion: (() -> Void)?) {
        let fromView = fromViewController.view
        let toView = toViewController.view
        toView.frame = fromView.frame
        toView.autoresizingMask = fromView.autoresizingMask
        if let sup = fromView.superview {
            sup.addSubview(toView, positioned: .above, relativeTo: fromView)
        } else {
            view.addSubview(toView)
        }
        fromView.removeFromSuperview()
        completion?()
    }
    // DUPLICATE: @MainActor open func transition(from fromViewController: NSViewController, to toViewController: NSViewController, options: NSViewController.TransitionOptions = []) async
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/updateviewconstraints()
    @available(macOS 10.10, *)
    @MainActor open func updateViewConstraints() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/view
    @MainActor open var view: NSView {
        get {
            loadViewIfNeeded()
            return _view!
        }
        set {
            _view?._viewController = nil
            _view = newValue
            newValue._viewController = self
            // The controller sits between its view and the view's superview in the responder chain.
            nextResponder = newValue.superview
            newValue.nextResponder = self
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/viewdidappear()
    @available(macOS 10.10, *)
    @MainActor open func viewDidAppear() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/viewdiddisappear()
    @available(macOS 10.10, *)
    @MainActor open func viewDidDisappear() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/viewdidlayout()
    @available(macOS 10.10, *)
    @MainActor open func viewDidLayout() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/viewdidload()
    @available(macOS 10.10, *)
    @MainActor open func viewDidLoad() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/viewifloaded
    @available(macOS 14.0, *)
    @MainActor open var viewIfLoaded: NSView? { _view }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/viewwillappear()
    @available(macOS 10.10, *)
    @MainActor open func viewWillAppear() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/viewwilldisappear()
    @available(macOS 10.10, *)
    @MainActor open func viewWillDisappear() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/viewwilllayout()
    @available(macOS 10.10, *)
    @MainActor open func viewWillLayout() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/viewwilltransition(to:)
    @available(macOS 10.10, *)
    @MainActor open func viewWillTransition(to newSize: NSSize) { }
    // SKIPPED (Foundation.NSExtensionContext not in corelibs): func beginRequest(with context: NSExtensionContext)
}
