// The accessibility seam (ADR-0013): what a window exposes to the platform's assistive
// technology (UI Automation on Windows, AT-SPI2 on Linux), as a snapshot tree plus
// change notifications. The core builds the tree from the NSAccessibility protocol
// answers of its views; a backend turns it into providers, D-Bus objects, ...

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// What a control's value looks like to assistive technology.
public enum PlatformAccessibilityValue: Equatable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)

    public var stringValue: String {
        switch self {
        case .string(let s): return s
        case .number(let d): return d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d)
        case .boolean(let b): return b ? "1" : "0"
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .string(let s): return Double(s)
        case .number(let d): return d
        case .boolean(let b): return b ? 1 : 0
        }
    }
}

/// An action an element performs for assistive technology (`accessibilityPerformPress`
/// and friends). Platforms map these onto their patterns (UIA Invoke/Toggle, AT-SPI
/// Action).
public enum PlatformAccessibilityAction: String, Sendable, CaseIterable {
    case press, increment, decrement, showMenu, confirm, cancel, pick, raise, expand, collapse
}

/// One node of the accessibility tree a window exposes: a snapshot of what the
/// `NSAccessibility` protocol answers for a view, in a form a backend can hand to the
/// platform without calling back into AppKit for every attribute. Frames are in AppKit
/// screen coordinates (points, origin at the bottom-left of the primary display).
public struct PlatformAccessibilityElement: Sendable {
    /// Stable for the lifetime of the element (the view): platforms use it for runtime
    /// ids, object paths and to find the element again when an action arrives.
    public var id: Int
    /// `NSAccessibility.Role` raw value ("AXButton", "AXStaticText", ...).
    public var role: String
    /// `NSAccessibility.Subrole` raw value, when there is one.
    public var subrole: String?
    public var roleDescription: String?
    public var label: String?
    public var title: String?
    public var value: PlatformAccessibilityValue?
    public var help: String?
    public var identifier: String?
    public var placeholder: String?
    public var frame: NSRect
    public var isEnabled = true
    public var isFocusable = false
    public var isFocused = false
    public var isSelected = false
    /// The value can be set (editable text, a slider, a checkbox).
    public var isSettable = false
    /// Multi-line text (text areas).
    public var isMultiline = false
    /// A selection container (table) that allows more than one selected child.
    public var allowsMultipleSelection = false
    /// Assistive technology may select the element (a row, a collection view item).
    public var isSelectable = false
    /// Expanded (true) or collapsed (false) for elements that can expand (outline rows,
    /// disclosure triangles); nil for everything else.
    public var isExpanded: Bool? = nil
    public var minValue: Double?
    public var maxValue: Double?
    public var selectedTextRange: NSRange?
    /// Row index inside a table, tab index, ...
    public var index: Int?
    public var actions: [PlatformAccessibilityAction] = []
    /// The element's `accessibilityCustomActions`, by name; performing one goes through
    /// `accessibilityPerform(.press, on:)` with the action's own id.
    public var customActions: [PlatformAccessibilityCustomAction] = []
    /// A menu item's check mark: 0 off, 1 on, 2 mixed; nil for everything else.
    public var checkedState: Int? = nil
    /// A menu item's key equivalent as drawn ("Ctrl+S"); nil when it has none.
    public var keyEquivalent: String? = nil
    /// The window root only: the platform window's client area (what
    /// `PlatformWindow.contentRect(forFrameRect:)` gives for the root's frame), in the same
    /// screen points as every frame of the tree. Backends anchor it to the client area's
    /// physical origin so frames reach the screen through the window's own scale, whatever
    /// monitor the window is on (`PlatformAccessibilityScreenMapping`).
    public var clientFrame: NSRect? = nil
    public var children: [PlatformAccessibilityElement] = []

    public init(id: Int, role: String, frame: NSRect) {
        self.id = id
        self.role = role
        self.frame = frame
    }

    /// Depth-first search for an element.
    public func element(withID id: Int) -> PlatformAccessibilityElement? {
        if self.id == id { return self }
        for c in children { if let e = c.element(withID: id) { return e } }
        return nil
    }

    /// The deepest element whose frame contains `point` (screen coordinates), or nil.
    public func element(at point: NSPoint) -> PlatformAccessibilityElement? {
        for c in children.reversed() { if let hit = c.element(at: point) { return hit } }
        return frame.contains(point) ? self : nil
    }

    /// Every element in the tree, parents before children.
    public var flattened: [PlatformAccessibilityElement] { [self] + children.flatMap(\.flattened) }

    /// The parent of an element, when it is in this tree.
    public func parent(of id: Int) -> PlatformAccessibilityElement? {
        if children.contains(where: { $0.id == id }) { return self }
        for c in children { if let p = c.parent(of: id) { return p } }
        return nil
    }
}

/// An `NSAccessibilityCustomAction` as the platform sees it: the name a screen reader
/// lists and the id that performs it.
public struct PlatformAccessibilityCustomAction: Sendable, Equatable {
    public var id: Int
    public var name: String
    public init(id: Int, name: String) { self.id = id; self.name = name }
}

/// How one window's accessibility frames (AppKit screen points) become physical screen
/// pixels (top-left origin, y down) for UI Automation and AT-SPI.
///
/// AppKit's global point space is not a linear image of the physical desktop once
/// monitors have different scales: a window on a 100% monitor next to a 150% primary has
/// frames in points that only its own scale turns back into the pixels it covers. So every
/// frame is taken relative to the window's client area in points, scaled by the window's
/// own backing scale, and added to the client area's physical origin as the window system
/// reports it (`ClientToScreen` on Windows, the X window's root position on X11). Nothing
/// depends on the primary monitor's height or scale.
public struct PlatformAccessibilityScreenMapping: Sendable, Equatable {
    /// The client area in AppKit screen points (the tree root's `clientFrame`).
    public var clientFrame: NSRect
    /// The client area's top-left corner in physical screen pixels.
    public var clientOriginX: Double
    public var clientOriginY: Double
    /// The window's backing scale factor (physical pixels per point).
    public var scale: Double

    public init(clientFrame: NSRect, clientOriginX: Double, clientOriginY: Double, scale: Double) {
        self.clientFrame = clientFrame
        self.clientOriginX = clientOriginX
        self.clientOriginY = clientOriginY
        self.scale = scale
    }

    /// A frame as a physical-pixel rectangle: left, top, width, height. The edges are
    /// rounded (not the size), so adjacent elements stay adjacent.
    public func pixelRect(_ frame: NSRect) -> (x: Int32, y: Int32, width: Int32, height: Int32) {
        let left = (clientOriginX + Double(frame.minX - clientFrame.minX) * scale).rounded()
        let right = (clientOriginX + Double(frame.maxX - clientFrame.minX) * scale).rounded()
        let top = (clientOriginY + Double(clientFrame.maxY - frame.maxY) * scale).rounded()
        let bottom = (clientOriginY + Double(clientFrame.maxY - frame.minY) * scale).rounded()
        return (Int32(clamping: Int(left)), Int32(clamping: Int(top)), Int32(clamping: Int(right - left)), Int32(clamping: Int(bottom - top)))
    }

    /// A physical screen pixel as AppKit screen points in this window's space (hit tests).
    public func point(pixelX: Double, pixelY: Double) -> NSPoint {
        NSPoint(x: clientFrame.minX + CGFloat((pixelX - clientOriginX) / scale),
                y: clientFrame.maxY - CGFloat((pixelY - clientOriginY) / scale))
    }
}

/// What a backend tells the platform's assistive technology when the tree changes.
public enum PlatformAccessibilityChange: Sendable, Equatable {
    /// Keyboard focus moved to the element (nil: the window has no focused element).
    case focus(Int?)
    /// The element's value (text, state, number) changed.
    case value(Int)
    /// The element's label or title changed.
    case name(Int)
    /// The element's children changed (views added, removed, hidden or shown).
    case structure(Int)
    /// The selection inside the element (a table's rows) changed.
    case selection(Int)
    /// A child element appeared under `parent` (sent after `.structure(parent)`, so
    /// platforms that only know "children invalidated" can ignore it).
    case childAdded(parent: Int, child: Int)
    /// A child element left `parent`; the child is no longer in the tree.
    case childRemoved(parent: Int, child: Int)
    /// A menu (an `AXMenu` element) opened in this window / is about to close.
    case menuOpened(Int)
    case menuClosed(Int)
}

/// Implemented by `NSWindow`: the window's accessibility tree, queried by the platform
/// window and driven by its actions.
@MainActor
public protocol PlatformAccessibilityProvider: AnyObject {
    /// A snapshot of the whole tree; the root is the window itself.
    func accessibilityTree() -> PlatformAccessibilityElement
    /// The element that has keyboard focus, when the window is key.
    var accessibilityFocusedElementID: Int? { get }
    func accessibilityPerform(_ action: PlatformAccessibilityAction, on elementID: Int) -> Bool
    func accessibilitySetValue(_ value: PlatformAccessibilityValue, on elementID: Int) -> Bool
    /// Moves keyboard focus to the element.
    func accessibilityFocus(_ elementID: Int) -> Bool
    /// Selects (or deselects) a selectable element such as a table row. `extending`
    /// keeps the current selection.
    func accessibilitySetSelected(_ selected: Bool, on elementID: Int, extending: Bool) -> Bool
}

extension PlatformWindow {
    /// The tree changed; backends with assistive technology forward this (default: nothing).
    public func accessibilityDidChange(_ change: PlatformAccessibilityChange) { }
}

extension PlatformAccessibilityElement {
    /// The client area a mapping anchors to: the root's `clientFrame`, else its frame.
    public var mappingClientFrame: NSRect { clientFrame ?? frame }
}

/// Implemented by `NSApplication` (through `PlatformMenuHost`): the application-level
/// elements that belong to no window, the main menu as an `AXMenuBar`. Backends whose menu
/// bar the system does not expose (AT-SPI) list it next to the windows.
@MainActor
public protocol PlatformAccessibilityApplication: AnyObject {
    /// The main menu as an AXMenuBar tree (nil when there is none).
    func accessibilityMenuBarTree() -> PlatformAccessibilityElement?
    /// Performs an action on an element of the menu bar tree.
    func accessibilityPerformMenuBarAction(_ action: PlatformAccessibilityAction, on elementID: Int) -> Bool
}
