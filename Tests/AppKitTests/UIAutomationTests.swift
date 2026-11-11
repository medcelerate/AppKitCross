// The UI Automation provider shim (CUIAutomation, ADR-0013), driven without a window:
// a node table goes in, properties, navigation, patterns and actions come back through
// the COM interfaces the shim exposes to UI Automation. Windows only; skipped elsewhere.

import XCTest
@testable import AppKit
#if os(Windows)
import CUIAutomation
import WinSDK
#endif

final class UIAutomationTests: XCTestCase, @unchecked Sendable {
    #if os(Windows)
    private final class Log: @unchecked Sendable {
        var invoked: [Int32] = []
        var toggled: [Int32] = []
        var values: [(Int32, String)] = []
        var ranges: [(Int32, Double)] = []
        var selected: [(Int32, Int32)] = []
        var focused: [Int32] = []
        var refreshes = 0
    }

    private static func utf16(_ s: String) -> [UInt16] { Array(s.utf16) + [0] }

    private func property(_ root: OpaquePointer, _ id: Int32, _ property: Int32) -> String? {
        var buffer = [UInt16](repeating: 0, count: 512)
        let ok = buffer.withUnsafeMutableBufferPointer { cuia_root_debug_property(root, id, property, $0.baseAddress, Int32($0.count)) }
        guard ok else { return nil }
        return String(decodingCString: buffer, as: UTF16.self)
    }

    func testNodesBecomeProvidersWithPropertiesPatternsAndActions() {
        let log = Log()
        var callbacks = CUIACallbacks()
        callbacks.context = Unmanaged.passUnretained(log).toOpaque()
        callbacks.refresh = { ctx in Unmanaged<Log>.fromOpaque(ctx!).takeUnretainedValue().refreshes += 1 }
        callbacks.invoke = { ctx, id in Unmanaged<Log>.fromOpaque(ctx!).takeUnretainedValue().invoked.append(id); return true }
        callbacks.toggle = { ctx, id in Unmanaged<Log>.fromOpaque(ctx!).takeUnretainedValue().toggled.append(id); return true }
        callbacks.setValue = { ctx, id, v in Unmanaged<Log>.fromOpaque(ctx!).takeUnretainedValue().values.append((id, String(decodingCString: v!, as: UTF16.self))); return true }
        callbacks.setRangeValue = { ctx, id, v in Unmanaged<Log>.fromOpaque(ctx!).takeUnretainedValue().ranges.append((id, v)); return true }
        callbacks.select = { ctx, id, mode in Unmanaged<Log>.fromOpaque(ctx!).takeUnretainedValue().selected.append((id, mode)); return true }
        callbacks.setFocus = { ctx, id in Unmanaged<Log>.fromOpaque(ctx!).takeUnretainedValue().focused.append(id); return true }
        let root = cuia_root_create(nil, &callbacks)!
        defer { cuia_root_destroy(root) }

        let title = Self.utf16("Hello"), button = Self.utf16("Clear dots"), check = Self.utf16("Show grid")
        let field = Self.utf16("type here"), text = Self.utf16("Ada Lovelace"), row = Self.utf16("Venus")
        title.withUnsafeBufferPointer { t in button.withUnsafeBufferPointer { b in check.withUnsafeBufferPointer { c in
        field.withUnsafeBufferPointer { f in text.withUnsafeBufferPointer { v in row.withUnsafeBufferPointer { r in
            var nodes: [CUIANode] = []
            var w = CUIANode(); w.id = 1; w.parent = -1; w.controlType = 50032; w.name = t.baseAddress
            w.left = 100; w.top = 100; w.right = 740; w.bottom = 500; w.flags = UInt32(CUIA_ENABLED | CUIA_IS_CONTENT | CUIA_FOCUSED)
            nodes.append(w)
            var b1 = CUIANode(); b1.id = 2; b1.parent = 1; b1.controlType = 50000; b1.name = b.baseAddress
            b1.left = 600; b1.top = 450; b1.right = 700; b1.bottom = 480; b1.flags = UInt32(CUIA_ENABLED | CUIA_FOCUSABLE | CUIA_HAS_INVOKE | CUIA_IS_CONTENT)
            nodes.append(b1)
            var c1 = CUIANode(); c1.id = 3; c1.parent = 1; c1.controlType = 50002; c1.name = c.baseAddress
            c1.flags = UInt32(CUIA_ENABLED | CUIA_FOCUSABLE | CUIA_HAS_TOGGLE | CUIA_IS_CONTENT); c1.toggleState = 1
            nodes.append(c1)
            var e1 = CUIANode(); e1.id = 4; e1.parent = 1; e1.controlType = 50004; e1.name = f.baseAddress; e1.value = v.baseAddress
            e1.flags = UInt32(CUIA_ENABLED | CUIA_FOCUSABLE | CUIA_SETTABLE | CUIA_HAS_VALUE | CUIA_HAS_TEXT | CUIA_IS_CONTENT)
            e1.textSelectionStart = 4; e1.textSelectionLength = 0
            nodes.append(e1)
            var s1 = CUIANode(); s1.id = 5; s1.parent = 1; s1.controlType = 50015
            s1.flags = UInt32(CUIA_ENABLED | CUIA_FOCUSABLE | CUIA_SETTABLE | CUIA_HAS_RANGE | CUIA_IS_CONTENT)
            s1.rangeValue = 120; s1.rangeMin = 40; s1.rangeMax = 200; s1.rangeStep = 1.6
            nodes.append(s1)
            var l1 = CUIANode(); l1.id = 6; l1.parent = 1; l1.controlType = 50008
            l1.flags = UInt32(CUIA_ENABLED | CUIA_HAS_SELECTION | CUIA_CAN_SELECT_MULTIPLE | CUIA_IS_CONTENT)
            nodes.append(l1)
            var r1 = CUIANode(); r1.id = 7; r1.parent = 6; r1.controlType = 50007; r1.name = r.baseAddress
            r1.flags = UInt32(CUIA_ENABLED | CUIA_HAS_SELECTION_ITEM | CUIA_SELECTED | CUIA_IS_CONTENT)
            nodes.append(r1)
            nodes.withUnsafeBufferPointer { cuia_root_set_nodes(root, $0.baseAddress, Int32($0.count)) }
        } } } } } }

        // Properties (the UIA_*PropertyId constants).
        XCTAssertEqual(property(root, 1, 30003), "50032", "ControlType of the window")
        XCTAssertEqual(property(root, 1, 30005), "Hello", "Name")
        XCTAssertEqual(property(root, 2, 30005), "Clear dots")
        XCTAssertEqual(property(root, 2, 30003), "50000")
        XCTAssertEqual(property(root, 2, 30009), "true", "IsKeyboardFocusable")
        XCTAssertEqual(property(root, 2, 30008), "false", "HasKeyboardFocus")
        XCTAssertEqual(property(root, 1, 30008), "true")
        XCTAssertEqual(property(root, 3, 30086), "1", "ToggleState On")
        XCTAssertEqual(property(root, 4, 30045), "Ada Lovelace", "Value.Value")
        XCTAssertEqual(property(root, 4, 30046), "false", "Value.IsReadOnly")
        XCTAssertEqual(property(root, 5, 30047), "120", "RangeValue.Value")
        XCTAssertEqual(property(root, 5, 30050), "200", "RangeValue.Maximum")
        XCTAssertEqual(property(root, 7, 30079), "true", "SelectionItem.IsSelected")
        XCTAssertEqual(property(root, 6, 30060), "true", "Selection.CanSelectMultiple")
        XCTAssertEqual(property(root, 2, 30024), "AppKitCross", "FrameworkId")
        XCTAssertEqual(property(root, 2, 30011), "AppKitCross.2", "AutomationId falls back to the element id")
        XCTAssertNil(property(root, 99, 30005), "an unknown id has no provider")
        // Navigation.
        XCTAssertEqual(cuia_root_debug_child_count(root, 1), 5)
        XCTAssertEqual(cuia_root_debug_child_count(root, 6), 1)
        XCTAssertEqual(cuia_root_debug_child_count(root, 2), 0)
        // Patterns (the UIA_*PatternId constants).
        XCTAssertTrue(cuia_root_debug_has_pattern(root, 2, 10000), "Invoke on the button")
        XCTAssertFalse(cuia_root_debug_has_pattern(root, 2, 10015), "no Toggle on the button")
        XCTAssertTrue(cuia_root_debug_has_pattern(root, 3, 10015), "Toggle on the check box")
        XCTAssertTrue(cuia_root_debug_has_pattern(root, 4, 10002), "Value on the field")
        XCTAssertTrue(cuia_root_debug_has_pattern(root, 4, 10014), "Text on the field")
        XCTAssertTrue(cuia_root_debug_has_pattern(root, 5, 10003), "RangeValue on the slider")
        XCTAssertTrue(cuia_root_debug_has_pattern(root, 6, 10001), "Selection on the table")
        XCTAssertTrue(cuia_root_debug_has_pattern(root, 7, 10010), "SelectionItem on the row")
        var buffer = [UInt16](repeating: 0, count: 64)
        XCTAssertTrue(buffer.withUnsafeMutableBufferPointer { cuia_root_debug_text(root, 4, $0.baseAddress, 64) })
        XCTAssertEqual(String(decodingCString: buffer, as: UTF16.self), "Ada Lovelace", "the Text pattern's document range")
        // After an invalidation the next request refreshes through the callback.
        XCTAssertEqual(log.refreshes, 0)
        cuia_root_invalidate(root)
        _ = property(root, 2, 30005)
        XCTAssertEqual(log.refreshes, 1)
        _ = property(root, 2, 30005)
        XCTAssertEqual(log.refreshes, 1, "fresh again until the next invalidation")
    }

    func testActionsReachTheCallbacks() {
        let log = Log()
        var callbacks = CUIACallbacks()
        callbacks.context = Unmanaged.passUnretained(log).toOpaque()
        callbacks.invoke = { ctx, id in Unmanaged<Log>.fromOpaque(ctx!).takeUnretainedValue().invoked.append(id); return true }
        callbacks.toggle = { ctx, id in Unmanaged<Log>.fromOpaque(ctx!).takeUnretainedValue().toggled.append(id); return true }
        callbacks.setValue = { ctx, id, v in Unmanaged<Log>.fromOpaque(ctx!).takeUnretainedValue().values.append((id, String(decodingCString: v!, as: UTF16.self))); return true }
        callbacks.setRangeValue = { ctx, id, v in Unmanaged<Log>.fromOpaque(ctx!).takeUnretainedValue().ranges.append((id, v)); return true }
        callbacks.select = { ctx, id, mode in Unmanaged<Log>.fromOpaque(ctx!).takeUnretainedValue().selected.append((id, mode)); return true }
        callbacks.setFocus = { ctx, id in Unmanaged<Log>.fromOpaque(ctx!).takeUnretainedValue().focused.append(id); return true }
        let root = cuia_root_create(nil, &callbacks)!
        defer { cuia_root_destroy(root) }
        var nodes: [CUIANode] = []
        var w = CUIANode(); w.id = 1; w.parent = -1; w.controlType = 50032; w.flags = UInt32(CUIA_ENABLED)
        var b = CUIANode(); b.id = 2; b.parent = 1; b.controlType = 50000; b.flags = UInt32(CUIA_ENABLED | CUIA_HAS_INVOKE)
        var c = CUIANode(); c.id = 3; c.parent = 1; c.controlType = 50002; c.flags = UInt32(CUIA_ENABLED | CUIA_HAS_TOGGLE)
        var e = CUIANode(); e.id = 4; e.parent = 1; e.controlType = 50004; e.flags = UInt32(CUIA_ENABLED | CUIA_SETTABLE | CUIA_HAS_VALUE)
        var s = CUIANode(); s.id = 5; s.parent = 1; s.controlType = 50015; s.flags = UInt32(CUIA_ENABLED | CUIA_SETTABLE | CUIA_HAS_RANGE)
        var d = CUIANode(); d.id = 6; d.parent = 1; d.controlType = 50000; d.flags = UInt32(CUIA_HAS_INVOKE)   // disabled
        nodes = [w, b, c, e, s, d]
        nodes.withUnsafeBufferPointer { cuia_root_set_nodes(root, $0.baseAddress, Int32($0.count)) }
        XCTAssertTrue(cuia_debug_invoke(root, 2))
        XCTAssertEqual(log.invoked, [2])
        XCTAssertFalse(cuia_debug_invoke(root, 6), "a disabled element refuses")
        XCTAssertTrue(cuia_debug_toggle(root, 3))
        XCTAssertEqual(log.toggled, [3])
        XCTAssertTrue(Self.utf16("Grace").withUnsafeBufferPointer { cuia_debug_set_value(root, 4, $0.baseAddress) })
        XCTAssertEqual(log.values.map(\.1), ["Grace"])
        XCTAssertTrue(cuia_debug_set_range_value(root, 5, 150))
        XCTAssertEqual(log.ranges.map(\.1), [150])
        XCTAssertFalse(cuia_debug_set_range_value(root, 4, 1), "no RangeValue pattern on the field")
        XCTAssertTrue(cuia_debug_set_focus(root, 2))
        XCTAssertEqual(log.focused, [2])
        // Replacing the table drops the providers of vanished nodes.
        nodes = [w, b]
        nodes.withUnsafeBufferPointer { cuia_root_set_nodes(root, $0.baseAddress, Int32($0.count)) }
        XCTAssertFalse(cuia_debug_toggle(root, 3), "gone")
        XCTAssertEqual(cuia_root_debug_child_count(root, 1), 1)
    }
    /// Snapshots replace each other while providers for every node stay in use: the
    /// vanished ones answer "not available", the survivors keep their identity, and
    /// nothing is freed twice (the Windows job runs this under the debug CRT).
    func testSnapshotsReplaceEachOtherUnderLiveProviders() {
        let log = Log()
        var callbacks = CUIACallbacks()
        callbacks.context = Unmanaged.passUnretained(log).toOpaque()
        callbacks.refresh = { ctx in Unmanaged<Log>.fromOpaque(ctx!).takeUnretainedValue().refreshes += 1 }
        let root = cuia_root_create(nil, &callbacks)!
        defer { cuia_root_destroy(root) }
        let names = (0..<80).map { Self.utf16("Element \($0)") }
        func push(_ count: Int32, offset: Int32 = 0) {
            var nodes: [CUIANode] = []
            var w = CUIANode(); w.id = 1; w.parent = -1; w.controlType = 50032; w.flags = UInt32(CUIA_ENABLED)
            nodes.append(w)
            for i in 0..<count {
                var n = CUIANode(); n.id = 2 + offset + i; n.parent = i % 8 == 0 ? 1 : 2 + offset + (i / 8) * 8
                n.controlType = i % 3 == 0 ? 50000 : 50020
                n.flags = UInt32(CUIA_ENABLED | CUIA_HAS_INVOKE | CUIA_HAS_TEXT | CUIA_IS_CONTENT)
                nodes.append(n)
            }
            names.withUnsafeBufferPointer { _ in
                for i in 1..<nodes.count { nodes[i].name = UnsafePointer(names[(i - 1) % names.count].withUnsafeBufferPointer { $0.baseAddress! }) }
                nodes.withUnsafeBufferPointer { cuia_root_set_nodes(root, $0.baseAddress, Int32($0.count)) }
            }
        }
        for round in 0..<6 {
            push(64, offset: Int32(round % 2) * 40)      // alternating, overlapping id ranges
            for id in Int32(2)...Int32(2 + 64 + 40) {
                _ = property(root, id, 30005)
                _ = cuia_root_debug_child_count(root, id)
                _ = cuia_root_debug_has_pattern(root, id, 10014)
            }
            XCTAssertEqual(cuia_root_debug_child_count(root, 1), 8)
            cuia_root_invalidate(root)
            _ = property(root, 1, 30005)
        }
        XCTAssertEqual(log.refreshes, 6)
        XCTAssertNotNil(property(root, 42, 30005), "the last round pushed ids 42...105")
        XCTAssertNil(property(root, 2, 30005), "the other range's first id is gone")
        XCTAssertNil(property(root, 106, 30005))
    }

    /// Menus (ADR-0013 follow-ups): a menu with items whose key equivalents are the
    /// AcceleratorKey, a checked item with Toggle, an item with a submenu with
    /// ExpandCollapse, and a custom-action button that never answers a hit test.
    func testMenusAcceleratorsAndCustomActionButtons() {
        let log = Log()
        var callbacks = CUIACallbacks()
        callbacks.context = Unmanaged.passUnretained(log).toOpaque()
        callbacks.invoke = { ctx, id in Unmanaged<Log>.fromOpaque(ctx!).takeUnretainedValue().invoked.append(id); return true }
        callbacks.toggle = { ctx, id in Unmanaged<Log>.fromOpaque(ctx!).takeUnretainedValue().toggled.append(id); return true }
        callbacks.expandCollapse = { ctx, id, expand in Unmanaged<Log>.fromOpaque(ctx!).takeUnretainedValue().invoked.append(expand ? -id : id); return true }
        let root = cuia_root_create(nil, &callbacks)!
        defer { cuia_root_destroy(root) }
        let open = Self.utf16("Open…"), ctrlO = Self.utf16("Ctrl+O"), ruler = Self.utf16("Show Ruler"), recent = Self.utf16("Open Recent"), archive = Self.utf16("Archive")
        open.withUnsafeBufferPointer { o in ctrlO.withUnsafeBufferPointer { k in ruler.withUnsafeBufferPointer { r in
        recent.withUnsafeBufferPointer { re in archive.withUnsafeBufferPointer { a in
            var m = CUIANode(); m.id = 1; m.parent = -1; m.controlType = 50009; m.flags = UInt32(CUIA_ENABLED | CUIA_IS_CONTENT)
            m.left = 0; m.top = 0; m.right = 200; m.bottom = 100
            var i1 = CUIANode(); i1.id = 2; i1.parent = 1; i1.controlType = 50011; i1.name = o.baseAddress; i1.acceleratorKey = k.baseAddress
            i1.flags = UInt32(CUIA_ENABLED | CUIA_HAS_INVOKE | CUIA_IS_CONTENT); i1.left = 0; i1.top = 5; i1.right = 200; i1.bottom = 27
            var i2 = CUIANode(); i2.id = 3; i2.parent = 1; i2.controlType = 50011; i2.name = r.baseAddress
            i2.flags = UInt32(CUIA_ENABLED | CUIA_HAS_INVOKE | CUIA_HAS_TOGGLE | CUIA_IS_CONTENT); i2.toggleState = 1
            i2.left = 0; i2.top = 27; i2.right = 200; i2.bottom = 49
            var i3 = CUIANode(); i3.id = 4; i3.parent = 1; i3.controlType = 50011; i3.name = re.baseAddress
            i3.flags = UInt32(CUIA_ENABLED | CUIA_HAS_EXPAND_COLLAPSE | CUIA_IS_CONTENT); i3.left = 0; i3.top = 49; i3.right = 200; i3.bottom = 71
            var b = CUIANode(); b.id = 5; b.parent = 2; b.controlType = 50000; b.name = a.baseAddress
            b.flags = UInt32(CUIA_ENABLED | CUIA_HAS_INVOKE | CUIA_IS_CONTENT | CUIA_SKIP_HIT_TEST); b.left = 0; b.top = 5; b.right = 200; b.bottom = 27
            let nodes = [m, i1, i2, i3, b]
            nodes.withUnsafeBufferPointer { cuia_root_set_nodes(root, $0.baseAddress, Int32($0.count)) }
        } } } } }
        XCTAssertEqual(property(root, 1, 30003), "50009", "Menu")
        XCTAssertEqual(property(root, 2, 30003), "50011", "MenuItem")
        XCTAssertEqual(property(root, 2, 30006), "Ctrl+O", "AcceleratorKey")
        XCTAssertNil(property(root, 3, 30006), "no key equivalent, no accelerator")
        XCTAssertEqual(property(root, 3, 30086), "1", "the checked item's ToggleState is On")
        XCTAssertTrue(cuia_root_debug_has_pattern(root, 4, 10005), "ExpandCollapse on the item with a submenu")
        XCTAssertFalse(cuia_root_debug_has_pattern(root, 4, 10000), "and no Invoke")
        XCTAssertEqual(cuia_root_debug_child_count(root, 2), 1, "the custom action is a child button")
        XCTAssertTrue(cuia_debug_invoke(root, 5))
        XCTAssertTrue(cuia_debug_expand_collapse(root, 4, true))
        XCTAssertEqual(log.invoked, [5, -4])
        XCTAssertEqual(cuia_root_debug_hit_test(root, 100, 10), 2, "the item, not the custom-action button over it")
        XCTAssertEqual(cuia_root_debug_hit_test(root, 100, 60), 4)
        XCTAssertEqual(cuia_root_debug_hit_test(root, 500, 500), -1)
        // Without a window the events are no-ops (no host provider to raise them from).
        cuia_root_raise_structure_child(root, 1, 2, true)
        cuia_root_raise_structure_child(root, 1, 99, false)
        cuia_root_raise_menu(root, 1, true)
        cuia_root_raise_menu(root, 1, false)
    }
    #else
    func testSkippedWithoutUIAutomation() throws {
        throw XCTSkip("UI Automation exists on Windows only")
    }
    #endif
}
