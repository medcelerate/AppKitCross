// NSAccessibilityCustomAction (hand-written; seeded from the generated stub, see tools/apigen)
//
// A named action an element offers besides its role's standard ones (ADR-0013). The
// element lists it in `accessibilityCustomActions()`; the platform shows it by name (an
// extra AT-SPI action, a child button under the element in UI Automation) and performing
// it calls the handler, or sends the selector to the target.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomaction
@available(macOS 10.13, *)
open class NSAccessibilityCustomAction: NSObject {
    private var _name: String
    private var _handler: (() -> Bool)?
    private weak var _target: (any NSObjectProtocol)?
    private var _selector: Selector?
    private var _accessibilityID = 0

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomaction/init(name:handler:)
    public init(name: String, handler: (() -> Bool)? = nil) {
        _name = name
        _handler = handler
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomaction/init(name:target:selector:)
    public init(name: String, target: any NSObjectProtocol, selector: Selector) {
        _name = name
        _target = target
        _selector = selector
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomaction/handler
    open var handler: (() -> Bool)? {
        get { _handler }
        set { _handler = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomaction/name
    open var name: String {
        get { _name }
        set { _name = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomaction/selector
    open var selector: Selector? {
        get { _selector }
        set { _selector = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilitycustomaction/target
    open var target: (any NSObjectProtocol)? {
        get { _target }
        set { _target = newValue }
    }

    // MARK: Platform (ADR-0013)

    /// Stable id: the platform performs the action by it.
    @MainActor internal var _accessibilityElementID: Int {
        if _accessibilityID == 0 { _accessibilityID = _NSAccessibilityIDs.next(registering: self) }
        return _accessibilityID
    }

    /// Runs the handler, else sends the selector to the target (the action method gets
    /// the custom action as its argument, as AppKit's does). True when something ran and
    /// said yes.
    @MainActor internal func _perform() -> Bool {
        if let h = _handler { return h() }
        guard let selector = _selector, let target = _target as? AnyObject else { return false }
        return ActionRegistry.perform(selector, on: target, with: self)
    }
}
