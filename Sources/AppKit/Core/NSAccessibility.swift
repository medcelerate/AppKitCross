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
    public static func screenPoint(fromView parentView: NSView, point: NSPoint) -> NSPoint {
        MainActor.assumeIsolated {
            let inWindow = parentView.convert(point, to: nil)
            return parentView.window?.convertPoint(toScreen: inWindow) ?? inWindow
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibility/screenrect(fromview:rect:)
    @available(macOS 10.10, *)
    public static func screenRect(fromView parentView: NSView, rect frame: NSRect) -> NSRect {
        MainActor.assumeIsolated {
            let inWindow = parentView.convert(frame, to: nil)
            return parentView.window?.convertToScreen(inWindow) ?? inWindow
        }
    }
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
    var customActions: [NSAccessibilityCustomAction]? = nil
}

/// Element ids: one counter for views, windows, virtual elements and custom actions,
/// never reused.
internal enum _NSAccessibilityIDs {
    @MainActor private static var last = 0
    @MainActor static func next() -> Int { last += 1; return last }

    /// Objects that are not views (virtual elements, custom actions) by id, so an action
    /// arriving from the platform finds them without walking every tree. Weak: an element
    /// the application dropped is simply not found.
    private final class Weak { weak var object: AnyObject?; init(_ o: AnyObject) { object = o } }
    @MainActor private static var objects: [Int: Weak] = [:]
    @MainActor static func next(registering object: AnyObject) -> Int {
        let id = next()
        if objects.count > 256 && objects.count % 256 == 0 { objects = objects.filter { $0.value.object != nil } }
        objects[id] = Weak(object)
        return id
    }
    @MainActor static func object(withID id: Int) -> AnyObject? { objects[id]?.object }
}

extension NSAccessibility {
    /// The actions the platform may offer for a role (what UIA's Invoke/Toggle/
    /// RangeValue and AT-SPI's Action interface expose); the element answers
    /// `accessibilityPerform...` when one is used.
    internal static func _actions(for role: NSAccessibility.Role) -> [PlatformAccessibilityAction] {
        switch role {
        case .button, .checkBox, .radioButton, .link, .disclosureTriangle, .cell, .row, .colorWell: return [.press]
        case .menuItem, .menuBarItem: return [.press, .pick]
        case .menu: return [.cancel]
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

/// An element that is not a view: a tab of an `NSTabView`, a segment of an
/// `NSSegmentedControl`. The owning view lists it among its `accessibilityChildren()`;
/// the snapshot, the id lookups and the actions reach it through this protocol.
@MainActor
internal protocol _NSAccessibilityVirtualElement: AnyObject {
    var _accessibilityElementID: Int { get }
    /// The view that draws it (focus goes there).
    var _accessibilityOwnerView: NSView? { get }
    func _accessibilityElement() -> PlatformAccessibilityElement
    func _accessibilityPerform(_ action: PlatformAccessibilityAction) -> Bool
    /// Virtual elements below this one (an `NSAccessibilityElement`'s children, a menu's
    /// items), searched when an action arrives by id.
    var _accessibilityVirtualChildren: [any _NSAccessibilityVirtualElement] { get }
    /// Sets the value (default: not settable).
    func _accessibilitySetValue(_ value: PlatformAccessibilityValue) -> Bool
}

extension _NSAccessibilityVirtualElement {
    var _accessibilityVirtualChildren: [any _NSAccessibilityVirtualElement] { [] }
    func _accessibilitySetValue(_ value: PlatformAccessibilityValue) -> Bool { false }
    /// This element or one below it with an id.
    func _accessibilityVirtualElement(withID id: Int) -> (any _NSAccessibilityVirtualElement)? {
        if _accessibilityElementID == id { return self }
        for c in _accessibilityVirtualChildren { if let v = c._accessibilityVirtualElement(withID: id) { return v } }
        return nil
    }
}

extension NSAccessibility {
    /// The platform form of `accessibilityCustomActions` (ids registered so a press finds
    /// the action again).
    @MainActor internal static func _platformCustomActions(_ actions: [NSAccessibilityCustomAction]?) -> [PlatformAccessibilityCustomAction] {
        (actions ?? []).map { PlatformAccessibilityCustomAction(id: $0._accessibilityElementID, name: $0.name) }
    }

    /// The children of an element as snapshot nodes: views (not hidden) and virtual elements.
    @MainActor internal static func _childElements(_ children: [Any]?) -> [PlatformAccessibilityElement] {
        var out: [PlatformAccessibilityElement] = []
        for c in children ?? [] {
            if let v = c as? NSView {
                if v.isHidden || v.isAccessibilityHidden() { continue }
                out.append(v._accessibilityElement())
            } else if let v = c as? any _NSAccessibilityVirtualElement {
                out.append(v._accessibilityElement())
            }
        }
        return out
    }

    /// Performs a platform action on an id that is not a view: a custom action (press
    /// runs it) or a virtual element registered under the id.
    @MainActor internal static func _performOnRegistered(_ action: PlatformAccessibilityAction, id: Int) -> Bool? {
        switch _NSAccessibilityIDs.object(withID: id) {
        case let a as NSAccessibilityCustomAction: return action == .press || action == .pick ? a._perform() : false
        case let v as any _NSAccessibilityVirtualElement: return v._accessibilityPerform(action)
        default: return nil
        }
    }
}

extension NSView {
    /// The virtual element with an id among this subtree's children, if any.
    @MainActor internal func _accessibilityVirtualElement(withID id: Int) -> (any _NSAccessibilityVirtualElement)? {
        for c in accessibilityChildren() ?? [] {
            if let v = c as? any _NSAccessibilityVirtualElement, let hit = v._accessibilityVirtualElement(withID: id) { return hit }
        }
        for s in subviews { if let v = s._accessibilityVirtualElement(withID: id) { return v } }
        if let v = _NSAccessibilityIDs.object(withID: id) as? any _NSAccessibilityVirtualElement,
           let owner = v._accessibilityOwnerView, owner === self || owner.isDescendant(of: self) { return v }
        return nil
    }

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
        NSAccessibility._childElements(accessibilityChildren())
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
        e.allowsMultipleSelection = _accessibilityAllowsMultipleSelection()
        e.isSelectable = _accessibilityIsSelectable()
        e.isExpanded = _accessibilityExpandedState()
        e.minValue = NSAccessibility._double(accessibilityMinValue())
        e.maxValue = NSAccessibility._double(accessibilityMaxValue())
        let range = accessibilitySelectedTextRange()
        e.selectedTextRange = range.location == NSNotFound ? nil : range
        let index = accessibilityIndex()
        e.index = index < 0 ? nil : index
        e.actions = NSAccessibility._actions(for: role)
        if e.isExpanded != nil { e.actions += [.expand, .collapse] }
        e.customActions = NSAccessibility._platformCustomActions(accessibilityCustomActions())
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
    /// What happened to this view, for the structure event that names the child.
    internal enum _AccessibilityChildChange { case added, removed }

    @MainActor internal func _accessibilityStructureChanged(_ change: _AccessibilityChildChange? = nil) {
        // The parent element's children changed; an ignored view's parent is the
        // nearest element above it. A field editor coming and going is not a change:
        // the text field stands for it.
        guard let w = window else { return }
        if let t = self as? NSText, t.isFieldEditor { return }
        var v: NSView? = superview
        while let cur = v, !cur.isAccessibilityElement() { v = cur.superview }
        let parent = v?._accessibilityElementID ?? w._accessibilityElementID
        _accessibilityNotify(.structure(parent))
        // Name the elements this view brings or takes away: itself when it is an element,
        // else the elements its subtree contributes in its place.
        guard let change, !isAccessibilityHidden() else { return }
        for child in _accessibilityContributedElementIDs() {
            _accessibilityNotify(change == .added ? .childAdded(parent: parent, child: child) : .childRemoved(parent: parent, child: child))
        }
    }

    /// The ids of the elements this view puts into its parent's children, ignoring its
    /// own `isHidden` (a view being hidden takes away what it showed).
    @MainActor internal func _accessibilityContributedElementIDs() -> [Int] {
        if isAccessibilityElement() { return [_accessibilityElementID] }
        var ids: [Int] = []
        for c in accessibilityChildren() ?? [] {
            if let s = c as? NSView {
                if s.isHidden || s.isAccessibilityHidden() { continue }
                ids.append(contentsOf: s.isAccessibilityElement() ? [s._accessibilityElementID] : s._accessibilityContributedElementIDs())
            } else if let e = c as? any _NSAccessibilityVirtualElement {
                ids.append(e._accessibilityElementID)
            }
        }
        return ids
    }
}
