// NSAccessibility (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// The constants (roles, subroles, attributes, notifications) are the SDK's; the bottom
// of the file holds the machinery behind the NSAccessibility protocol on NSView,
// NSWindow and NSApplication (ADR-0013): the per-view overrides the
// `setAccessibility...` methods store, element ids, the snapshot the platform seam
// hands to assistive technology, and `post(element:notification:)`.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibility
public struct NSAccessibility {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibility/errorcodeexceptioninfo
    static public var ErrorCodeExceptionInfo: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibility/post(element:notification:)
    public static func post(element: Any, notification: NSAccessibility.Notification) { post(element: element, notification: notification, userInfo: nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibility/post(element:notification:userinfo:)
    ///
    /// Forwarded to the platform's assistive technology through the window's
    /// `PlatformAccessibilityChange` (value, title, focus, selection and layout changes);
    /// other notifications have no platform counterpart yet and are dropped.
    public static func post(element: Any, notification: NSAccessibility.Notification, userInfo: [NSAccessibility.NotificationUserInfoKey : Any]?) {
        MainActor.assumeIsolated {
            let view = element as? NSView
            let window = (element as? NSWindow) ?? view?.window
            guard let window else { return }
            let id = view?._accessibilityElementID ?? window._accessibilityElementID
            switch notification {
            case .valueChanged: window._accessibilityNotify(.value(id))
            case .titleChanged: window._accessibilityNotify(.name(id))
            case .focusedUIElementChanged: window._accessibilityNotify(.focus(view?._accessibilityElementID))
            case .focusedWindowChanged, .mainWindowChanged: window._accessibilityNotify(.focus(window.accessibilityFocusedElementID))
            case .selectedRowsChanged, .selectedChildrenChanged, .selectedTextChanged, .selectedColumnsChanged, .selectedCellsChanged: window._accessibilityNotify(.selection(id))
            case .layoutChanged, .rowCountChanged, .uiElementDestroyed, .created, .windowCreated: window._accessibilityNotify(.structure(id))
            default: break
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibility/raisebadargumentexception(_:_:_:)
    public static func raiseBadArgumentException(_ element: Any!, _ attribute: NSAccessibility.Attribute!, _ value: Any!) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibility/screenpoint(fromview:point:)
    @available(macOS 10.10, *)
    public static func screenPoint(fromView parentView: NSView, point: NSPoint) -> NSPoint { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibility/screenrect(fromview:rect:)
    @available(macOS 10.10, *)
    public static func screenRect(fromView parentView: NSView, rect frame: NSRect) -> NSRect { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibility/setmaycontainprotectedcontent(_:)
    public static func setMayContainProtectedContent(_ flag: Bool) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibility/unignoredancestor(of:)
    public static func unignoredAncestor(of element: Any) -> Any? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibility/unignoredchildren(from:)
    public static func unignoredChildren(from originalChildren: [Any]) -> [Any] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibility/unignoredchildrenforonlychild(from:)
    public static func unignoredChildrenForOnlyChild(from originalChild: Any) -> [Any] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibility/unignoreddescendant(of:)
    public static func unignoredDescendant(of element: Any) -> Any? { unimplemented() }
}

extension NSString {
    /// The substring for an accessibility range, nil when the range is out of bounds.
    internal func _accessibilitySubstring(_ range: NSRange) -> String? {
        guard range.location != NSNotFound, range.location >= 0, NSMaxRange(range) <= length else { return nil }
        return substring(with: range)
    }
}

// MARK: - Element overrides, ids and the platform snapshot (ADR-0013)

/// What the `setAccessibility...` methods store on a view: each overrides the value the
/// view would otherwise derive from its state (`nil` = not overridden).
internal struct _NSAccessibilityOverrides {
    var isElement: Bool? = nil
    var role: NSAccessibility.Role? = nil
    var subrole: NSAccessibility.Subrole? = nil
    var roleDescription: String? = nil
    var label: String? = nil
    var title: String? = nil
    var value: Any? = nil
    var hasValue = false
    var help: String? = nil
    var identifier: String? = nil
    var placeholder: String? = nil
    var isEnabled: Bool? = nil
    var isHidden = false
    var isSelected: Bool? = nil
    var frame: NSRect? = nil
    var parent: Any? = nil
    var children: [Any]? = nil
    var minValue: Any? = nil
    var maxValue: Any? = nil
    var index: Int? = nil
}

/// Element ids: one counter for views and windows, never reused.
internal enum _NSAccessibilityIDs {
    @MainActor private static var last = 0
    @MainActor static func next() -> Int { last += 1; return last }
}

extension NSAccessibility {
    /// The actions the platform may offer for a role (what UIA's Invoke/Toggle/
    /// RangeValue and AT-SPI's Action interface expose); the element answers
    /// `accessibilityPerform...` when one is used.
    internal static func _actions(for role: NSAccessibility.Role) -> [PlatformAccessibilityAction] {
        switch role {
        case .button, .checkBox, .radioButton, .link, .disclosureTriangle, .menuItem, .menuBarItem, .cell, .row: return [.press]
        case .popUpButton, .menuButton, .comboBox: return [.press, .showMenu]
        case .slider, .incrementor, .scrollBar, .levelIndicator: return [.increment, .decrement]
        case .textField: return [.confirm]
        case .window, .sheet, .drawer: return [.raise]
        default: return []
        }
    }

    /// Converts what `accessibilityValue()` answers into the seam's value.
    internal static func _platformValue(_ value: Any?) -> PlatformAccessibilityValue? {
        switch value {
        case nil: return nil
        case let s as String: return .string(s)
        case let a as NSAttributedString: return .string(a.string)
        case let b as Bool: return .boolean(b)
        case let n as NSControl.StateValue: return .number(Double(n.rawValue))
        case let i as Int: return .number(Double(i))
        case let d as Double: return .number(d)
        case let f as Float: return .number(Double(f))
        case let f as CGFloat: return .number(Double(f))
        case let n as NSNumber: return .number(n.doubleValue)
        case let other: return .string(String(describing: other))
        }
    }

    internal static func _double(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let f as Float: return Double(f)
        case let f as CGFloat: return Double(f)
        case let n as NSNumber: return n.doubleValue
        default: return nil
        }
    }
}

extension NSView {
    /// The accessibility tree below this view, as the platform sees it: the view itself
    /// when it is an element, otherwise its children stand in for it (AppKit's "ignored"
    /// elements). Hidden views and `accessibilityHidden` views contribute nothing.
    @MainActor internal func _accessibilityElements() -> [PlatformAccessibilityElement] {
        if isHidden || isAccessibilityHidden() { return [] }
        if isAccessibilityElement() { return [_accessibilityElement()] }
        return _accessibilityChildElements()
    }

    /// The elements of `accessibilityChildren()`.
    @MainActor internal func _accessibilityChildElements() -> [PlatformAccessibilityElement] {
        guard let children = accessibilityChildren() else { return [] }
        var out: [PlatformAccessibilityElement] = []
        for c in children {
            if let v = c as? NSView {
                if v.isHidden || v.isAccessibilityHidden() { continue }
                out.append(v._accessibilityElement())
            }
        }
        return out
    }

    /// This view as one node of the snapshot, with its children below it.
    @MainActor internal func _accessibilityElement() -> PlatformAccessibilityElement {
        let role = accessibilityRole() ?? .unknown
        var e = PlatformAccessibilityElement(id: _accessibilityElementID, role: role.rawValue, frame: accessibilityFrame())
        e.subrole = accessibilitySubrole()?.rawValue
        e.roleDescription = accessibilityRoleDescription()
        e.label = accessibilityLabel()
        e.title = accessibilityTitle()
        let value: Any? = accessibilityValue()
        e.value = NSAccessibility._platformValue(value)
        e.help = accessibilityHelp()
        let identifier: String = accessibilityIdentifier()
        e.identifier = identifier.isEmpty ? nil : identifier
        e.placeholder = accessibilityPlaceholderValue()
        e.isEnabled = isAccessibilityEnabled()
        e.isFocusable = _accessibilityIsFocusable()
        e.isFocused = isAccessibilityFocused()
        e.isSelected = isAccessibilitySelected()
        e.isSettable = _accessibilityValueIsSettable()
        e.isMultiline = _accessibilityIsMultiline()
        e.minValue = NSAccessibility._double(accessibilityMinValue())
        e.maxValue = NSAccessibility._double(accessibilityMaxValue())
        let range = accessibilitySelectedTextRange()
        e.selectedTextRange = range.location == NSNotFound ? nil : range
        let index = accessibilityIndex()
        e.index = index < 0 ? nil : index
        e.actions = NSAccessibility._actions(for: role)
        e.children = _accessibilityChildElements()
        return e
    }

    /// Finds the view with an element id in this subtree (hidden views included, so a
    /// platform acting on a stale snapshot still finds its target).
    @MainActor internal func _accessibilityView(withID id: Int) -> NSView? {
        if _accessibilityElementID == id { return self }
        for s in subviews { if let v = s._accessibilityView(withID: id) { return v } }
        return nil
    }

    /// The element the platform should report as focused for this first responder:
    /// the responder itself, or the control whose field editor it is.
    @MainActor internal var _accessibilityFocusTarget: NSView? {
        if let t = self as? NSText, t.isFieldEditor {
            var v = superview
            while let cur = v { if cur is NSControl { return cur }; v = cur.superview }
        }
        return self
    }

    /// Tells the platform the tree below this view changed (structure) or this view's
    /// value or name did. Nothing is sent before the view is in a window.
    @MainActor internal func _accessibilityNotify(_ change: PlatformAccessibilityChange) {
        window?._accessibilityNotify(change)
    }
    @MainActor internal func _accessibilityValueChanged() { if window != nil { _accessibilityNotify(.value(_accessibilityElementID)) } }
    @MainActor internal func _accessibilityNameChanged() { if window != nil { _accessibilityNotify(.name(_accessibilityElementID)) } }
    @MainActor internal func _accessibilityStructureChanged() {
        // The parent element's children changed; an ignored view's parent is the
        // nearest element above it.
        guard let w = window else { return }
        var v: NSView? = superview
        while let cur = v, !cur.isAccessibilityElement() { v = cur.superview }
        _accessibilityNotify(.structure(v?._accessibilityElementID ?? w._accessibilityElementID))
    }
}
