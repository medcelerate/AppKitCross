// ColorPicker over NSColorWell (ADR-0022): the well opens the shared colour panel, and
// the panel's changes come back through the well's action into the binding.

import Foundation
import AppKit
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/colorpicker
public struct ColorPicker<Label: View>: View, _PrimitiveView {
    public typealias Body = Never
    let selection: Binding<Color>
    let supportsOpacity: Bool
    let label: Label

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/colorpicker/init(selection:supportsopacity:label:)
    public init(selection: Binding<Color>, supportsOpacity: Bool = true, @ViewBuilder label: () -> Label) {
        self.selection = selection
        self.supportsOpacity = supportsOpacity
        self.label = label()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/colorpicker/init(selection:supportsopacity:label:)-4v3zz
    public init(selection: Binding<CGColor>, supportsOpacity: Bool = true, @ViewBuilder label: () -> Label) {
        self.init(selection: Binding(get: { Color(cgColor: selection.wrappedValue) }, set: { if let cg = $0.cgColor { selection.wrappedValue = cg } }),
                  supportsOpacity: supportsOpacity, label: label)
    }
    public func _makePrimitive(node: _ViewNode) -> _Primitive {
        _ColorPickerPrimitive(title: (label as? Text)?._string ?? "", selection: selection, supportsOpacity: supportsOpacity)
    }
}

extension ColorPicker where Label == Text {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/colorpicker/init(_:selection:supportsopacity:)-9cbbd
    public init(_ titleKey: LocalizedStringKey, selection: Binding<Color>, supportsOpacity: Bool = true) {
        self.init(selection: selection, supportsOpacity: supportsOpacity) { Text(titleKey) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/colorpicker/init(_:selection:supportsopacity:)-1kk5v
    public init<S: StringProtocol>(_ title: S, selection: Binding<Color>, supportsOpacity: Bool = true) {
        self.init(selection: selection, supportsOpacity: supportsOpacity) { Text(String(title)) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/colorpicker/init(_:selection:supportsopacity:)-6g7xc
    public init(_ titleKey: LocalizedStringKey, selection: Binding<CGColor>, supportsOpacity: Bool = true) {
        self.init(selection: selection, supportsOpacity: supportsOpacity) { Text(titleKey) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/colorpicker/init(_:selection:supportsopacity:)-3jxvx
    public init<S: StringProtocol>(_ title: S, selection: Binding<CGColor>, supportsOpacity: Bool = true) {
        self.init(selection: selection, supportsOpacity: supportsOpacity) { Text(String(title)) }
    }
}

/// The label and the well side by side.
@MainActor
final class _ColorPickerHostView: NSView {
    let label = NSTextField(labelWithString: "")
    let well = NSColorWell(frame: NSRect(x: 0, y: 0, width: 44, height: 24))
    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(label)
        addSubview(well)
    }
    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize {
        let l = label.stringValue.isEmpty ? NSSize.zero : label.intrinsicContentSize
        return NSSize(width: (l.width > 0 ? l.width + 8 : 0) + well.intrinsicContentSize.width, height: max(l.height, well.intrinsicContentSize.height))
    }
    override func layout() {
        super.layout()
        let wellSize = well.intrinsicContentSize
        let l = label.stringValue.isEmpty ? NSSize.zero : label.intrinsicContentSize
        label.frame = NSRect(x: 0, y: (bounds.height - l.height) / 2, width: l.width, height: l.height)
        well.frame = NSRect(x: bounds.width - wellSize.width, y: (bounds.height - wellSize.height) / 2, width: wellSize.width, height: wellSize.height)
    }
}

@MainActor
final class _ColorPickerPrimitive: _ControlPrimitive<_ColorPickerHostView> {
    var selection: Binding<Color>
    private static let action = Selector(("swiftUIColorPickerAction:"))
    init(title: String, selection: Binding<Color>, supportsOpacity: Bool) {
        self.selection = selection
        let host = _ColorPickerHostView(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        host.label.stringValue = title
        host.well.color = NSColor(selection.wrappedValue)
        if #available(macOS 14.0, *) { host.well.supportsAlpha = supportsOpacity }
        super.init(control: host)
        host.well.target = host.well
        host.well.action = _ColorPickerPrimitive.action
        host.well.setActionHandler(for: _ColorPickerPrimitive.action) { [weak self] _ in
            guard let self else { return }
            let c = Color(nsColor: self.control.well.color)
            if self.selection.wrappedValue != c { self.selection.wrappedValue = c }
        }
    }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _ColorPickerPrimitive else { return }
        selection = o.selection
        control.label.stringValue = o.control.label.stringValue
        apply()
    }
    override func attach(to node: _ViewNode) { super.attach(to: node); apply() }
    private func apply() {
        let wanted = NSColor(selection.wrappedValue)
        if !control.well.color.isEqual(wanted) { control.well.color = wanted }
        control.well.isEnabled = node?.environment.isEnabled ?? true
        control.needsLayout = true
    }
}
