// NSAccessibilityElement (hand-written; seeded from the generated stub, see tools/apigen)
//
// A virtual element (ADR-0013): something a custom view draws that is not a view of its
// own (a chart's bars, a canvas's handles) but should reach assistive technology as an
// element with a role, a label, a value, a frame and actions. The custom view returns
// these from `accessibilityChildren()`; their frames are given in the parent's space
// (`accessibilityFrameInParentSpace`) and converted to the screen through the nearest view
// above them. They take part in the platform snapshot like the tabs of an NSTabView do,
// with ids of their own; a press or a value from UI Automation or AT-SPI calls the
// element's `accessibilityPerform...` and `setAccessibilityValue`, which subclasses
// override.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilityelement
@available(macOS 10.10, *)
open class NSAccessibilityElement: NSObject, NSAccessibilityProtocol {
    private var _overrides = _NSAccessibilityOverrides()
    private var _frameInParentSpace = NSRect.zero
    private var _hasFrameInParentSpace = false
    private var _focused = false
    private var _accessibilityID = 0

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilityelement/accessibilityaddchildelement(_:)
    open func accessibilityAddChildElement(_ childElement: NSAccessibilityElement) {
        var children = _overrides.children ?? []
        children.append(childElement)
        _overrides.children = children
        childElement._overrides.parent = self
        MainActor.assumeIsolated { _accessibilityStructureChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilityelement/accessibilityframeinparentspace()
    open func accessibilityFrameInParentSpace() -> NSRect { _frameInParentSpace }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilityelement/element(withrole:frame:label:parent:)
    ///
    /// The element is an `NSAccessibilityElement` (subclasses create their own instances
    /// and set the same four attributes).
    public class func element(withRole role: NSAccessibility.Role, frame: NSRect, label: String?, parent: Any?) -> Any {
        let e = NSAccessibilityElement()
        e.setAccessibilityRole(role)
        e.setAccessibilityFrame(frame)
        e.setAccessibilityLabel(label)
        e.setAccessibilityParent(parent)
        return e
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilityelement/setaccessibilityframeinparentspace(_:)
    open func setAccessibilityFrameInParentSpace(_ accessibilityFrameInParentSpace: NSRect) {
        _frameInParentSpace = accessibilityFrameInParentSpace
        _hasFrameInParentSpace = true
    }

    // MARK: NSAccessibility answers: what the setters stored.

    open func isAccessibilityElement() -> Bool { _overrides.isElement ?? true }
    open func setAccessibilityElement(_ accessibilityElement: Bool) { _overrides.isElement = accessibilityElement }
    open func accessibilityRole() -> NSAccessibility.Role? { _overrides.role }
    open func setAccessibilityRole(_ accessibilityRole: NSAccessibility.Role?) { _overrides.role = accessibilityRole }
    open func accessibilitySubrole() -> NSAccessibility.Subrole? { _overrides.subrole }
    open func setAccessibilitySubrole(_ accessibilitySubrole: NSAccessibility.Subrole?) { _overrides.subrole = accessibilitySubrole }
    open func accessibilityRoleDescription() -> String? { _overrides.roleDescription }
    open func setAccessibilityRoleDescription(_ accessibilityRoleDescription: String?) { _overrides.roleDescription = accessibilityRoleDescription }
    open func accessibilityLabel() -> String? { _overrides.label }
    open func setAccessibilityLabel(_ accessibilityLabel: String?) { _overrides.label = accessibilityLabel; MainActor.assumeIsolated { _accessibilityNotify(.name(_accessibilityElementID)) } }
    open func accessibilityTitle() -> String? { _overrides.title }
    open func setAccessibilityTitle(_ accessibilityTitle: String?) { _overrides.title = accessibilityTitle; MainActor.assumeIsolated { _accessibilityNotify(.name(_accessibilityElementID)) } }
    open func accessibilityValue() -> Any? { _overrides.value }
    open func setAccessibilityValue(_ accessibilityValue: Any?) { _overrides.value = accessibilityValue; _overrides.hasValue = true; MainActor.assumeIsolated { _accessibilityNotify(.value(_accessibilityElementID)) } }
    open func accessibilityHelp() -> String? { _overrides.help }
    open func setAccessibilityHelp(_ accessibilityHelp: String?) { _overrides.help = accessibilityHelp }
    open func accessibilityIdentifier() -> String { _overrides.identifier ?? "" }
    open func setAccessibilityIdentifier(_ accessibilityIdentifier: String?) { _overrides.identifier = accessibilityIdentifier }
    open func isAccessibilityEnabled() -> Bool { _overrides.isEnabled ?? true }
    open func setAccessibilityEnabled(_ accessibilityEnabled: Bool) { _overrides.isEnabled = accessibilityEnabled }
    open func isAccessibilitySelected() -> Bool { _overrides.isSelected ?? false }
    open func setAccessibilitySelected(_ accessibilitySelected: Bool) { _overrides.isSelected = accessibilitySelected }
    open func isAccessibilityFocused() -> Bool { _focused }
    open func setAccessibilityFocused(_ accessibilityFocused: Bool) {
        _focused = accessibilityFocused
        if accessibilityFocused { MainActor.assumeIsolated { _accessibilityNotify(.focus(_accessibilityElementID)) } }
    }
    open func accessibilityMinValue() -> Any? { _overrides.minValue }
    open func setAccessibilityMinValue(_ accessibilityMinValue: Any?) { _overrides.minValue = accessibilityMinValue }
    open func accessibilityMaxValue() -> Any? { _overrides.maxValue }
    open func setAccessibilityMaxValue(_ accessibilityMaxValue: Any?) { _overrides.maxValue = accessibilityMaxValue }
    open func accessibilityIndex() -> Int { _overrides.index ?? -1 }
    open func setAccessibilityIndex(_ accessibilityIndex: Int) { _overrides.index = accessibilityIndex }
    open func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? { _overrides.customActions }
    open func setAccessibilityCustomActions(_ accessibilityCustomActions: [NSAccessibilityCustomAction]?) { _overrides.customActions = accessibilityCustomActions }
    open func accessibilityParent() -> Any? { _overrides.parent }
    open func setAccessibilityParent(_ accessibilityParent: Any?) { _overrides.parent = accessibilityParent }
    open func accessibilityChildren() -> [Any]? { _overrides.children }
    open func setAccessibilityChildren(_ accessibilityChildren: [Any]?) {
        _overrides.children = accessibilityChildren
        MainActor.assumeIsolated { _accessibilityStructureChanged() }
    }
    /// The frame in screen coordinates: `setAccessibilityFrame`'s, else the frame in the
    /// parent's space converted through the nearest view above the element.
    open func accessibilityFrame() -> NSRect {
        if let f = _overrides.frame, !_hasFrameInParentSpace { return f }
        return MainActor.assumeIsolated {
            var parent: Any? = accessibilityParent()
            var rect = _frameInParentSpace
            // Elements nested in elements: their parent-space frames add up until a view.
            while let p = parent as? NSAccessibilityElement {
                rect = rect.offsetBy(dx: p._frameInParentSpace.minX, dy: p._frameInParentSpace.minY)
                parent = p.accessibilityParent()
            }
            guard let view = parent as? NSView else { return _overrides.frame ?? rect }
            return NSAccessibility.screenRect(fromView: view, rect: rect)
        }
    }
    open func setAccessibilityFrame(_ accessibilityFrame: NSRect) { _overrides.frame = accessibilityFrame; _hasFrameInParentSpace = false }
    open func accessibilityWindow() -> Any? { MainActor.assumeIsolated { _accessibilityOwnerView?.window } }
    open func accessibilityTopLevelUIElement() -> Any? { accessibilityWindow() }
    open func accessibilityActivationPoint() -> NSPoint { let f = accessibilityFrame(); return NSPoint(x: f.midX, y: f.midY) }
    open func accessibilityPerformPress() -> Bool { false }
    open func accessibilityPerformIncrement() -> Bool { false }
    open func accessibilityPerformDecrement() -> Bool { false }
    open func accessibilityPerformShowMenu() -> Bool { false }
    open func accessibilityPerformConfirm() -> Bool { false }
    open func accessibilityPerformCancel() -> Bool { false }
    open func accessibilityPerformPick() -> Bool { false }
    open func accessibilityPerformRaise() -> Bool { false }

    // MARK: Platform (ADR-0013)

    /// Tells the window holding the element about a change (nothing before it is in one).
    @MainActor private func _accessibilityNotify(_ change: PlatformAccessibilityChange) {
        _accessibilityOwnerView?.window?._accessibilityNotify(change)
    }
    @MainActor private func _accessibilityStructureChanged() {
        _accessibilityNotify(.structure(_accessibilityElementID))
    }
}

extension NSAccessibilityElement: _NSAccessibilityVirtualElement {
    @MainActor var _accessibilityElementID: Int {
        if _accessibilityID == 0 { _accessibilityID = _NSAccessibilityIDs.next(registering: self) }
        return _accessibilityID
    }
    /// The nearest view above the element (its parent chain ends in one).
    @MainActor var _accessibilityOwnerView: NSView? {
        var p: Any? = accessibilityParent()
        while let e = p as? NSAccessibilityElement { p = e.accessibilityParent() }
        return p as? NSView
    }
    @MainActor var _accessibilityVirtualChildren: [any _NSAccessibilityVirtualElement] {
        (accessibilityChildren() ?? []).compactMap { $0 as? any _NSAccessibilityVirtualElement }
    }
    @MainActor func _accessibilityElement() -> PlatformAccessibilityElement {
        let role = accessibilityRole() ?? .unknown
        var e = PlatformAccessibilityElement(id: _accessibilityElementID, role: role.rawValue, frame: accessibilityFrame())
        e.subrole = accessibilitySubrole()?.rawValue
        e.roleDescription = accessibilityRoleDescription()
        e.label = accessibilityLabel()
        e.title = accessibilityTitle()
        e.value = NSAccessibility._platformValue(accessibilityValue())
        e.help = accessibilityHelp()
        let identifier = accessibilityIdentifier()
        e.identifier = identifier.isEmpty ? nil : identifier
        e.isEnabled = isAccessibilityEnabled()
        e.isFocused = isAccessibilityFocused()
        e.isSelected = isAccessibilitySelected()
        e.minValue = NSAccessibility._double(accessibilityMinValue())
        e.maxValue = NSAccessibility._double(accessibilityMaxValue())
        let index = accessibilityIndex()
        e.index = index < 0 ? nil : index
        e.actions = NSAccessibility._actions(for: role)
        e.customActions = NSAccessibility._platformCustomActions(accessibilityCustomActions())
        e.children = NSAccessibility._childElements(accessibilityChildren())
        return e
    }
    @MainActor func _accessibilityPerform(_ action: PlatformAccessibilityAction) -> Bool {
        switch action {
        case .press: return accessibilityPerformPress()
        case .increment: return accessibilityPerformIncrement()
        case .decrement: return accessibilityPerformDecrement()
        case .showMenu: return accessibilityPerformShowMenu()
        case .confirm: return accessibilityPerformConfirm()
        case .cancel: return accessibilityPerformCancel()
        case .pick: return accessibilityPerformPick()
        case .raise: return accessibilityPerformRaise()
        case .expand, .collapse: return false
        }
    }
    @MainActor func _accessibilitySetValue(_ value: PlatformAccessibilityValue) -> Bool {
        switch value {
        case .string(let s): setAccessibilityValue(s)
        case .number(let d): setAccessibilityValue(d)
        case .boolean(let b): setAccessibilityValue(b)
        }
        return true
    }
}
