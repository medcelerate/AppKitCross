// Formatted values in text: `Text(_:format:)`, `TextField(_:value:format:)` over a
// `ParseableFormatStyle`, `TextField(_:value:formatter:)` over a `Formatter`, and the
// view-level `monospacedDigit()`.

import Foundation

// MARK: Text

extension Text {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/text/init(_:format:)
    ///
    /// Formats with the style as given; a style that should follow the view's locale takes
    /// it from `.locale(_:)` on the style, as the environment's locale is not applied here.
    public init<F: FormatStyle>(_ input: F.FormatInput, format: F) where F.FormatInput: Equatable, F.FormatOutput == String {
        self.init(verbatim: format.format(input))
    }
}

// MARK: TextField with a value

/// How a value-backed field shows and reads its value.
struct _TextFieldFormatting {
    /// The value as text now.
    let format: () -> String
    /// Parses committed text into the value; false when the text does not parse.
    let commit: (String) -> Bool
}

extension TextField {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/textfield/init(_:value:format:prompt:)-3tksi
    ///
    /// As on macOS the value changes when editing commits (Return, or focus leaving the
    /// field), not on every keystroke; the text then shows the value formatted again, and
    /// text that does not parse goes back to the current value.
    public init<F: ParseableFormatStyle>(_ titleKey: LocalizedStringKey, value: Binding<F.FormatInput>, format: F, prompt: Text? = nil) where F.FormatOutput == String, Label == Text {
        self.init(titleKey, text: .constant(""), prompt: prompt, axis: .horizontal)
        _formatting = _TextFieldFormatting(format: _formatStyleText(value, format), commit: _formatStyleCommit(value, format))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/textfield/init(_:value:format:prompt:)-6ug7k
    @_disfavoredOverload
    public init<S: StringProtocol, F: ParseableFormatStyle>(_ title: S, value: Binding<F.FormatInput>, format: F, prompt: Text? = nil) where F.FormatOutput == String, Label == Text {
        self.init(String(title), text: .constant(""), prompt: prompt)
        _formatting = _TextFieldFormatting(format: _formatStyleText(value, format), commit: _formatStyleCommit(value, format))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/textfield/init(value:format:prompt:label:)
    public init<F: ParseableFormatStyle>(value: Binding<F.FormatInput>, format: F, prompt: Text? = nil, @ViewBuilder label: () -> Label) where F.FormatOutput == String {
        self.init(text: .constant(""), prompt: prompt, label: label)
        _formatting = _TextFieldFormatting(format: _formatStyleText(value, format), commit: _formatStyleCommit(value, format))
    }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/textfield/init(_:value:formatter:prompt:)-8nyyb
    public init<V>(_ titleKey: LocalizedStringKey, value: Binding<V>, formatter: Formatter, prompt: Text?) where Label == Text {
        self.init(titleKey, text: .constant(""), prompt: prompt, axis: .horizontal)
        _formatting = _formatterFormatting(value, formatter)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/textfield/init(_:value:formatter:prompt:)-5vlr2
    @_disfavoredOverload
    public init<S: StringProtocol, V>(_ title: S, value: Binding<V>, formatter: Formatter, prompt: Text?) where Label == Text {
        self.init(String(title), text: .constant(""), prompt: prompt)
        _formatting = _formatterFormatting(value, formatter)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/textfield/init(value:formatter:prompt:label:)
    public init<V>(value: Binding<V>, formatter: Formatter, prompt: Text? = nil, @ViewBuilder label: () -> Label) {
        self.init(text: .constant(""), prompt: prompt, label: label)
        _formatting = _formatterFormatting(value, formatter)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/textfield/init(_:value:formatter:)-1ii0p
    public init<V>(_ titleKey: LocalizedStringKey, value: Binding<V>, formatter: Formatter) where Label == Text {
        self.init(titleKey, value: value, formatter: formatter, prompt: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/textfield/init(_:value:formatter:)-4osn0
    @_disfavoredOverload
    public init<S: StringProtocol, V>(_ title: S, value: Binding<V>, formatter: Formatter) where Label == Text {
        self.init(title, value: value, formatter: formatter, prompt: nil)
    }
}

private func _formatStyleText<F: ParseableFormatStyle>(_ value: Binding<F.FormatInput>, _ format: F) -> () -> String where F.FormatOutput == String {
    { format.format(value.wrappedValue) }
}

private func _formatStyleCommit<F: ParseableFormatStyle>(_ value: Binding<F.FormatInput>, _ format: F) -> (String) -> Bool where F.FormatOutput == String {
    { text in
        guard let parsed = try? format.parseStrategy.parse(text) else { return false }
        value.wrappedValue = parsed
        return true
    }
}

private func _formatterFormatting<V>(_ value: Binding<V>, _ formatter: Formatter) -> _TextFieldFormatting {
    _TextFieldFormatting(
        format: { formatter.string(for: value.wrappedValue) ?? "" },
        commit: { text in
            guard let parsed = _parse(text, with: formatter) else { return false }
            if let v = parsed as? V { value.wrappedValue = v; return true }
            // A formatter answers NSNumber; the binding may be any numeric type.
            if let n = parsed as? NSNumber, let v = _number(n, as: V.self) { value.wrappedValue = v; return true }
            return false
        })
}

/// The object a formatter reads from `text`, or nil when the text does not parse.
private func _parse(_ text: String, with formatter: Formatter) -> Any? {
    if let f = formatter as? NumberFormatter { return f.number(from: text) }
    if let f = formatter as? DateFormatter { return f.date(from: text) }
    #if canImport(Darwin)
    var object: AnyObject?
    return formatter.getObjectValue(&object, for: text, errorDescription: nil) ? object : nil
    #else
    unimplemented("TextField(value:formatter:) parsing with \(type(of: formatter)) (NumberFormatter and DateFormatter are supported)")
    #endif
}

private func _number<V>(_ n: NSNumber, as type: V.Type) -> V? {
    switch type {
    case is Int.Type: return n.intValue as? V
    case is Int8.Type: return n.int8Value as? V
    case is Int16.Type: return n.int16Value as? V
    case is Int32.Type: return n.int32Value as? V
    case is Int64.Type: return n.int64Value as? V
    case is UInt.Type: return n.uintValue as? V
    case is UInt8.Type: return n.uint8Value as? V
    case is UInt16.Type: return n.uint16Value as? V
    case is UInt32.Type: return n.uint32Value as? V
    case is UInt64.Type: return n.uint64Value as? V
    case is Float.Type: return n.floatValue as? V
    case is Double.Type: return n.doubleValue as? V
    case is CGFloat.Type: return CGFloat(n.doubleValue) as? V
    case is Bool.Type: return n.boolValue as? V
    default: return nil
    }
}

/// A value-backed text field: the field edits a draft string, and the value takes the
/// draft when editing commits.
@MainActor
final class _FormattedTextFieldPrimitive: _TextFieldPrimitive {
    private final class Draft { var text = "" }
    private let draft: Draft
    private var formatting: _TextFieldFormatting
    /// The value's text when the field last showed it: a change of the value from outside
    /// replaces the draft, an unchanged value leaves the user's typing alone.
    private var shown: String
    private var endObserver: Any?

    init(placeholder: String, formatting: _TextFieldFormatting, axis: Axis) {
        let draft = Draft()
        let initial = formatting.format()
        draft.text = initial
        self.draft = draft
        self.formatting = formatting
        shown = initial
        super.init(placeholder: placeholder, text: Binding(get: { draft.text }, set: { draft.text = $0 }), onCommit: {}, axis: axis)
        onCommit = { [weak self] in self?.commit() }
        endObserver = NotificationCenter.default.addObserver(forName: NSControl.textDidEndEditingNotification, object: control, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.commit() }
        }
    }
    deinit { if let o = endObserver { NotificationCenter.default.removeObserver(o) } }

    override func update(from other: _Primitive) {
        if let o = other as? _FormattedTextFieldPrimitive {
            formatting = o.formatting
            // Keep this field's draft and commit handler; take everything else.
            o.text = text
            o.onCommit = onCommit
            let current = formatting.format()
            if current != shown { shown = current; draft.text = current }
        }
        super.update(from: other)
    }

    /// Parses the draft into the value; the field then shows the value formatted.
    func commit() {
        draft.text = control.stringValue
        if draft.text != shown, formatting.commit(draft.text) {
            node?.setNeedsUpdate()
        }
        let current = formatting.format()
        shown = current
        draft.text = current
        if control.stringValue != current { control._setStringValueUpdatingEditor(current) }
    }
}

// MARK: monospacedDigit

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/monospaceddigit()
    public func monospacedDigit() -> some View {
        transformEnvironment(\.font) { $0 = ($0 ?? .body).monospacedDigit() }
    }
}
