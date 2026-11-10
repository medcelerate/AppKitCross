// NSToolbarItemGroup: several items shown as one segmented control (or, collapsed, as
// a menu). The group's view is an NSSegmentedControl built from the subitems; a click
// selects the segment and sends the group's action with the group as sender.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritemgroup
@MainActor open class NSToolbarItemGroup: NSToolbarItem {
    private var _subitems: [NSToolbarItem] = []
    private var _selectionMode: NSToolbarItemGroup.SelectionMode = .momentary
    private var _controlRepresentation: NSToolbarItemGroup.ControlRepresentation = .automatic
    private var _control: NSSegmentedControl?
    private var _selected: [Bool] = []
    private var _groupTarget: AnyObject?
    private var _groupAction: Selector?

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritemgroup/init(itemidentifier:images:selectionmode:labels:target:action:)
    @available(macOS 10.15, *)
    @MainActor public convenience init(itemIdentifier: NSToolbarItem.Identifier, images: [NSImage], selectionMode: NSToolbarItemGroup.SelectionMode, labels: [String]?, target: Any?, action: Selector?) {
        self.init(itemIdentifier: itemIdentifier)
        _subitems = images.enumerated().map { i, image in
            let item = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("\(itemIdentifier.rawValue).\(i)"))
            item.image = image
            if let labels, i < labels.count { item.label = labels[i] }
            return item
        }
        _selectionMode = selectionMode
        self.target = target as AnyObject?
        self.action = action
        _rebuildControl()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritemgroup/init(itemidentifier:titles:selectionmode:labels:target:action:)
    @available(macOS 10.15, *)
    @MainActor public convenience init(itemIdentifier: NSToolbarItem.Identifier, titles: [String], selectionMode: NSToolbarItemGroup.SelectionMode, labels: [String]?, target: Any?, action: Selector?) {
        self.init(itemIdentifier: itemIdentifier)
        _subitems = titles.enumerated().map { i, title in
            let item = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("\(itemIdentifier.rawValue).\(i)"))
            item.title = title
            if let labels, i < labels.count { item.label = labels[i] }
            return item
        }
        _selectionMode = selectionMode
        self.target = target as AnyObject?
        self.action = action
        _rebuildControl()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritemgroup/controlrepresentation
    @available(macOS 10.15, *)
    @MainActor open var controlRepresentation: NSToolbarItemGroup.ControlRepresentation {
        get { _controlRepresentation }
        set { _controlRepresentation = newValue; _rebuildControl() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritemgroup/isselected(at:)
    @available(macOS 10.15, *)
    @MainActor open func isSelected(at index: Int) -> Bool { _selected.indices.contains(index) ? _selected[index] : false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritemgroup/selectedindex
    @available(macOS 10.15, *)
    @MainActor open var selectedIndex: Int {
        get { _selected.firstIndex(of: true) ?? -1 }
        set {
            _selected = _subitems.indices.map { $0 == newValue }
            _control?.selectedSegment = newValue
            _changed(layout: false)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritemgroup/selectionmode
    @available(macOS 10.15, *)
    @MainActor open var selectionMode: NSToolbarItemGroup.SelectionMode {
        get { _selectionMode }
        set { _selectionMode = newValue; _rebuildControl() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritemgroup/setselected(_:at:)
    @available(macOS 10.15, *)
    @MainActor open func setSelected(_ selected: Bool, at index: Int) {
        guard _selected.indices.contains(index) else { return }
        if _selectionMode == .selectOne && selected { _selected = _subitems.indices.map { $0 == index } }
        else { _selected[index] = selected }
        _control?.setSelected(selected, forSegment: index)
        _changed(layout: false)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritemgroup/subitems
    @MainActor open var subitems: [NSToolbarItem] {
        get { _subitems }
        set { _subitems = newValue; _rebuildControl() }
    }

    /// The item's own target/action: the group sends them itself after a segment click.
    open override var target: AnyObject? {
        get { _groupTarget }
        set { _groupTarget = newValue }
    }
    open override var action: Selector? {
        get { _groupAction }
        set { _groupAction = newValue }
    }

    /// Replaces the view with a segmented control reflecting the subitems and mode.
    private func _rebuildControl() {
        _selected = _subitems.indices.map { _selected.indices.contains($0) ? _selected[$0] : false }
        let tracking: NSSegmentedControl.SwitchTracking
        switch _selectionMode {
        case .selectOne: tracking = .selectOne
        case .selectAny: tracking = .selectAny
        case .momentary: tracking = .momentary
        }
        let control = NSSegmentedControl(labels: _subitems.map { $0.title }, trackingMode: tracking, target: nil, action: nil)
        for (i, item) in _subitems.enumerated() {
            if let image = item.image { control.setImage(image, forSegment: i); control.setLabel("", forSegment: i) }
            control.setSelected(_selected[i], forSegment: i)
        }
        control.setActionHandler(for: NSToolbarItemGroup._segmentAction) { [weak self] _ in self?._segmentClicked() }
        control.target = control
        control.action = NSToolbarItemGroup._segmentAction
        control.sizeToFit()
        _control = control
        view = control
    }
    private static let _segmentAction = Selector(("_toolbarGroupSegmentClicked:"))

    private func _segmentClicked() {
        guard let c = _control else { return }
        _selected = _subitems.indices.map { c.isSelected(forSegment: $0) }
        if _selectionMode == .momentary, c.selectedSegment >= 0, c.selectedSegment < _subitems.count {
            let sub = _subitems[c.selectedSegment]
            if sub.action != nil { sub._fireAction() }
        }
        if let a = _groupAction { _ = NSApplication.shared.sendAction(a, to: _groupTarget, from: self) }
    }

    open override func copy(with zone: NSZone? = nil) -> Any {
        MainActor.assumeIsolated {
            let c = NSToolbarItemGroup(itemIdentifier: itemIdentifier)
            c._copyProperties(from: self)
            c._subitems = _subitems.compactMap { $0.copy() as? NSToolbarItem }
            c._selectionMode = _selectionMode
            c._controlRepresentation = _controlRepresentation
            c._groupTarget = _groupTarget
            c._groupAction = _groupAction
            c._rebuildControl()
            return c
        }
    }
}

@available(macOS 10.15, *)
extension NSToolbarItemGroup {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritemgroup/controlrepresentation
    @available(macOS 10.15, *)
    public enum ControlRepresentation: Int, Sendable, Equatable, Hashable {
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritemgroup/controlrepresentation/automatic
        case automatic = 0
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritemgroup/controlrepresentation/collapsed
        case collapsed = 2
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritemgroup/controlrepresentation/expanded
        case expanded = 1
    }
}

@available(macOS 10.15, *)
extension NSToolbarItemGroup {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritemgroup/selectionmode
    @available(macOS 10.15, *)
    public enum SelectionMode: Int, Sendable, Equatable, Hashable {
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritemgroup/selectionmode/momentary
        case momentary = 2
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritemgroup/selectionmode/selectany
        case selectAny = 1
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritemgroup/selectionmode/selectone
        case selectOne = 0
    }
}
