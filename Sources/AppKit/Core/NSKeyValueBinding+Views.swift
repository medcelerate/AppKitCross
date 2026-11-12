// The bindings views define (ADR-0032).
//
// NSView: hidden, toolTip. NSControl: enabled, value (objectValue; written back when the control
// sends its action). NSTextField: value (string, with the selection-marker and null placeholders,
// editable only while there is a single value; written back when editing ends, or on every change
// with `continuouslyUpdatesValue`), editable, textColor. NSButton: value (state). NSPopUpButton:
// content, contentObjects, contentValues, selectedIndex, selectedObject, selectedValue,
// selectedTag. NSTableView: content, selectionIndexes, sortDescriptors; a column's value binding
// to an array controller's `arrangedObjects.<key>` binds the table to the controller implicitly,
// as AppKit does. NSTableColumn: value.
//
// The hooks each class overrides (`_applyViewBinding`, `_viewBindingDidAttach`,
// `_definedViewBindings`) are declared in the class bodies: without the Objective-C runtime a
// member declared in an extension cannot be overridden.

import Foundation

// MARK: - NSView

extension NSView: _NSBindingTarget {
    nonisolated static var _definedBindings: [NSBindingName] { MainActor.assumeIsolated { self._definedViewBindings } }
    nonisolated func _applyBinding(_ b: _NSBinding) -> Bool { MainActor.assumeIsolated { _applyViewBinding(b) } }
    nonisolated func _bindingDidAttach(_ b: _NSBinding) { MainActor.assumeIsolated { _viewBindingDidAttach(b) } }
    nonisolated func _bindingDidDetach(_ b: _NSBinding) { MainActor.assumeIsolated { _viewBindingDidDetach(b) } }
}

extension NSView {
    func _applyBaseViewBinding(_ b: _NSBinding) -> Bool {
        switch b.name {
        case .hidden: isHidden = _KVC.bool(b.value)
        case .toolTip:
            let v = b.value
            toolTip = (v == nil || v is NSBindingSelectionMarker) ? nil : String(describing: v!)
        default: return false
        }
        return true
    }
}

// MARK: - NSControl

extension NSControl {
    func _applyControlBinding(_ b: _NSBinding) -> Bool {
        switch b.name {
        case .enabled:
            isEnabled = _KVC.bool(b.value)
            return true
        case .value:
            let v = b.value
            _conditionallySetEnabled(for: v, binding: b)
            objectValue = v is NSBindingSelectionMarker ? nil : v
            return true
        default: return false
        }
    }

    /// With `conditionallySetsEnabled` (the default), a control bound to no selection or to a
    /// key that does not apply is disabled — unless its `enabled` is bound itself.
    func _conditionallySetEnabled(for value: Any?, binding b: _NSBinding) {
        guard b.boolOption(.conditionallySetsEnabled, default: true), _NSBindings.binding(self, .enabled) == nil else { return }
        let original = (b.saved["enabled"] as? Bool) ?? true
        if let m = value as? NSBindingSelectionMarker, m !== NSBindingSelectionMarker.multipleValues {
            isEnabled = false
        } else {
            isEnabled = original
        }
    }

    func _controlBindingDidAttach(_ b: _NSBinding) {
        if b.name == .value { b.saved["enabled"] = isEnabled }
    }

    /// The control is about to send its action: write the bound value back.
    func _pushControlValueBinding() {
        guard let b = _NSBindings.binding(self, .value) else { return }
        let v = objectValue
        if _KVC.same(v, b.value) { return }
        b.push(v)
    }
}

// MARK: - NSTextField

/// Registers a text field that is editing a bound value with the controller, so the controller's
/// `commitEditing()` reaches it.
final class _NSBindingEditor: NSObject, NSEditor {
    weak var field: NSTextField?
    init(field: NSTextField) { self.field = field; super.init() }
    @MainActor func commitEditing() -> Bool {
        guard let f = field else { return true }
        if let e = f._fieldEditor { f._takeEditorValue(e) }
        f._pushTextFieldValueBinding()
        return true
    }
    @MainActor func discardEditing() {
        guard let f = field, let b = _NSBindings.binding(f, .value) else { return }
        _NSBindings.apply(b)
        if let e = f._fieldEditor { e.string = f.stringValue }
    }
}

extension NSTextField {
    func _applyTextFieldBinding(_ b: _NSBinding) -> Bool {
        switch b.name {
        case .value:
            let v = b.value
            if v == nil || v is NSBindingSelectionMarker {
                placeholderString = _NSBindingPlaceholders.placeholder(for: v, binding: b) ?? (b.saved["placeholder"] as? String)
                _setStringValueUpdatingEditor("")
            } else {
                placeholderString = b.saved["placeholder"] as? String
                if formatter != nil { objectValue = v } else { _setStringValueUpdatingEditor((v as? String) ?? String(describing: v!)) }
            }
            if b.boolOption(.conditionallySetsEditable, default: true), _NSBindings.binding(self, .editable) == nil {
                let original = (b.saved["editable"] as? Bool) ?? true
                let single = !(v is NSBindingSelectionMarker)
                    || ((v as? NSBindingSelectionMarker) === NSBindingSelectionMarker.multipleValues && b.boolOption(.allowsEditingMultipleValuesSelection, default: true))
                isEditable = original && single
            }
            return true
        case .editable:
            isEditable = _KVC.bool(b.value)
            return true
        case .textColor:
            if let c = b.value as? NSColor { textColor = c }
            return true
        default: return false
        }
    }

    func _textFieldBindingDidAttach(_ b: _NSBinding) {
        guard b.name == .value else { return }
        b.saved["editable"] = isEditable
        if let p = placeholderString { b.saved["placeholder"] = p }
    }

    /// Writes the field's text back through its value binding (the formatter's object if it has one).
    func _pushTextFieldValueBinding() {
        guard let b = _NSBindings.binding(self, .value) else { return }
        let current = b.value
        if current is NSBindingSelectionMarker && stringValue.isEmpty { return }
        let v: Any? = formatter != nil ? objectValue : stringValue
        if let s = v as? String, let c = current, !(c is NSBindingSelectionMarker), String(describing: c) == s { return }
        b.push(v)
    }

    func _bindingEditingDidBegin() {
        guard let b = _NSBindings.binding(self, .value), let controller = b.observable as? NSController else { return }
        let editor = _NSBindingEditor(field: self)
        b.saved["editor"] = editor
        controller.objectDidBeginEditing(editor)
    }

    func _bindingEditingDidEnd() {
        guard let b = _NSBindings.binding(self, .value), let controller = b.observable as? NSController,
              let editor = b.saved.removeValue(forKey: "editor") as? _NSBindingEditor else { return }
        controller.objectDidEndEditing(editor)
    }

    func _bindingTextDidChange() {
        guard let b = _NSBindings.binding(self, .value), b.boolOption(.continuouslyUpdatesValue, default: false) else { return }
        _pushTextFieldValueBinding()
    }
}

// MARK: - NSButton

extension NSButton {
    func _applyButtonBinding(_ b: _NSBinding) -> Bool {
        switch b.name {
        case .value:
            let v = b.value
            _conditionallySetEnabled(for: v, binding: b)
            if (v as? NSBindingSelectionMarker) === NSBindingSelectionMarker.multipleValues, allowsMixedState { state = .mixed }
            else { state = _KVC.bool(v) ? .on : .off }
            return true
        case .title:
            if let v = b.value, !(v is NSBindingSelectionMarker) { title = String(describing: v) }
            return true
        default: return false
        }
    }

    func _pushButtonValueBinding() {
        guard let b = _NSBindings.binding(self, .value) else { return }
        b.push(state == .on)
    }
}

// MARK: - NSPopUpButton

extension NSPopUpButton {
    func _applyPopUpBinding(_ b: _NSBinding) -> Bool {
        switch b.name {
        case .content, .contentObjects, .contentValues:
            _rebuildBoundItems()
            for name in [NSBindingName.selectedIndex, .selectedObject, .selectedValue, .selectedTag] {
                if let s = _NSBindings.binding(self, name) { _ = _applyPopUpSelection(s) }
            }
            return true
        case .selectedIndex, .selectedObject, .selectedValue, .selectedTag:
            return _applyPopUpSelection(b)
        default: return false
        }
    }

    private func _applyPopUpSelection(_ b: _NSBinding) -> Bool {
        let v = b.value
        _conditionallySetEnabled(for: v, binding: b)
        switch b.name {
        case .selectedIndex:
            selectItem(at: (v.flatMap { _KVC.number($0) }).map { Int($0) } ?? -1)
        case .selectedObject:
            let objects = itemArray.map { $0.representedObject }
            selectItem(at: objects.firstIndex { _KVC.same($0, v) } ?? -1)
        case .selectedValue:
            if let v, !(v is NSBindingSelectionMarker) { selectItem(withTitle: String(describing: v)) } else { selectItem(at: -1) }
        case .selectedTag:
            _ = selectItem(withTag: (v.flatMap { _KVC.number($0) }).map { Int($0) } ?? -1)
        default: return false
        }
        return true
    }

    /// The items from the content bindings: titles from `contentValues` (else the content
    /// objects' descriptions), represented objects from `contentObjects` (else the content).
    private func _rebuildBoundItems() {
        let content = _NSBindings.binding(self, .content).map { NSArrayController._array($0.value) } ?? []
        let objects = _NSBindings.binding(self, .contentObjects).map { NSArrayController._array($0.value) } ?? content
        let titles: [String]
        if let b = _NSBindings.binding(self, .contentValues) {
            titles = NSArrayController._array(b.value).map { $0 is NSNull ? "" : String(describing: $0) }
        } else {
            titles = content.map { ($0 as? String) ?? String(describing: $0) }
        }
        // A fresh menu: addItem(withTitle:) would merge equal titles, the content may repeat them.
        let menu = NSMenu(title: "")
        for (i, t) in titles.enumerated() {
            let item = NSMenuItem(title: t, action: nil, keyEquivalent: "")
            if i < objects.count { item.representedObject = objects[i] }
            menu.addItem(item)
        }
        if let b = _NSBindings.binding(self, .content), b.boolOption(.insertsNullPlaceholder, default: false) {
            let title = (b.options[.nullPlaceholder]).map { String(describing: $0) } ?? ""
            menu.insertItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""), at: 0)
        }
        self.menu = menu
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    func _pushPopUpBindings() {
        let item = selectedItem
        if let b = _NSBindings.binding(self, .selectedIndex) { b.push(indexOfSelectedItem) }
        if let b = _NSBindings.binding(self, .selectedObject) { b.push(item?.representedObject) }
        if let b = _NSBindings.binding(self, .selectedValue) { b.push(item?.title) }
        if let b = _NSBindings.binding(self, .selectedTag) { b.push(item?.tag ?? -1) }
    }
}

// MARK: - NSTableView

extension NSTableView {
    func _applyTableBinding(_ b: _NSBinding) -> Bool {
        switch b.name {
        case .content:
            reloadData()
            if let s = _NSBindings.binding(self, .selectionIndexes) { _applyTableSelection(s) }
            return true
        case .selectionIndexes:
            _applyTableSelection(b)
            return true
        case .sortDescriptors:
            _setSortDescriptorsFromBinding((b.value as? [NSSortDescriptor]) ?? [])
            return true
        default: return false
        }
    }

    private func _applyTableSelection(_ b: _NSBinding) {
        let rows = (b.value as? IndexSet) ?? IndexSet()
        _applyingSelectionBinding = true
        defer { _applyingSelectionBinding = false }
        if rows != selectedRowIndexes { selectRowIndexes(rows, byExtendingSelection: false) }
        if let last = rows.last { scrollRowToVisible(last) }
    }

    /// The rows from the content binding, or implicitly from the first column bound to
    /// `<array>.<key>`; nil when the table has no bound content.
    func _boundContent() -> [Any]? {
        if let b = _NSBindings.binding(self, .content) { return NSArrayController._array(b.value) }
        for c in tableColumns {
            guard let b = _NSBindings.binding(c, .value) else { continue }
            let (head, _) = b.splitKeyPath
            return NSArrayController._array(_KVC.value(b.observable, forKeyPath: head))
        }
        return nil
    }

    /// A bound column's value at `row` (the row's object when the column is not bound).
    func _boundObjectValue(for column: NSTableColumn?, row: Int) -> Any?? {
        if let column, let b = _NSBindings.binding(column, .value) {
            let (head, rest) = b.splitKeyPath
            let rows = NSArrayController._array(_KVC.value(b.observable, forKeyPath: head))
            guard row >= 0, row < rows.count else { return .some(nil) }
            return .some(rest.map { _KVC.value(rows[row], forKeyPath: $0) } ?? rows[row])
        }
        if let content = _boundContent() {
            guard row >= 0, row < content.count else { return .some(nil) }
            return .some(content[row])
        }
        return nil
    }

    /// A column bound to an array controller's `arrangedObjects` binds the table's content,
    /// selection and sort descriptors to the controller unless they are bound already.
    func _adoptColumnBinding(_ b: _NSBinding) {
        guard b.name == .value, let ac = b.observable as? NSArrayController, b.splitKeyPath.head == "arrangedObjects" else {
            reloadData()
            return
        }
        if _NSBindings.binding(self, .content) == nil { bind(.content, to: ac, withKeyPath: "arrangedObjects") }
        if _NSBindings.binding(self, .selectionIndexes) == nil { bind(.selectionIndexes, to: ac, withKeyPath: "selectionIndexes") }
        if _NSBindings.binding(self, .sortDescriptors) == nil { bind(.sortDescriptors, to: ac, withKeyPath: "sortDescriptors") }
        reloadData()
    }

    /// The selection changed in the table: tell the bound controller.
    func _pushSelectionBinding() {
        guard !_applyingSelectionBinding, let b = _NSBindings.binding(self, .selectionIndexes) else { return }
        b.push(selectedRowIndexes)
    }
}

// MARK: - NSTableColumn

extension NSTableColumn: _NSBindingTarget {
    nonisolated static var _definedBindings: [NSBindingName] { [.value, .editable, .hidden, .headerTitle, .maxWidth, .minWidth, .width] }

    nonisolated func _applyBinding(_ b: _NSBinding) -> Bool {
        MainActor.assumeIsolated {
            switch b.name {
            case .value: tableView?.reloadData()
            case .editable: isEditable = _KVC.bool(b.value)
            case .hidden: isHidden = _KVC.bool(b.value)
            case .headerTitle: title = b.value.map { String(describing: $0) } ?? ""
            case .maxWidth: if let n = b.value.flatMap({ _KVC.number($0) }) { maxWidth = CGFloat(n) }
            case .minWidth: if let n = b.value.flatMap({ _KVC.number($0) }) { minWidth = CGFloat(n) }
            case .width: if let n = b.value.flatMap({ _KVC.number($0) }) { width = CGFloat(n) }
            default: return false
            }
            return true
        }
    }

    nonisolated func _bindingDidAttach(_ b: _NSBinding) {
        MainActor.assumeIsolated { tableView?._adoptColumnBinding(b) }
    }
}
