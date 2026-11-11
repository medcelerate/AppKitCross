// UI Automation for Win32 windows (ADR-0013): the window's accessibility snapshot goes
// to the CUIAutomation shim as a flat node table, WM_GETOBJECT hands UI Automation the
// shim's root provider, actions come back through the callbacks and the core's change
// notifications become UIA events.

#if os(Windows)
import Foundation
import WinSDK
import CoreGraphics
import CUIAutomation

extension Win32Window {
    /// The provider root, made on the first WM_GETOBJECT (or change) so windows no
    /// client inspects pay nothing.
    @discardableResult
    func ensureAccessibilityRoot() -> OpaquePointer? {
        if let root = uiaRoot { return root }
        guard let hwnd else { return nil }
        var callbacks = CUIACallbacks()
        callbacks.context = Unmanaged.passUnretained(self).toOpaque()
        callbacks.refresh = { context in MainActor.assumeIsolated { Win32Window.from(context).pushAccessibilityTree() } }
        callbacks.invoke = { context, id in MainActor.assumeIsolated { Win32Window.from(context).accessibilityPerform(.press, on: Int(id)) } }
        callbacks.toggle = { context, id in MainActor.assumeIsolated { Win32Window.from(context).accessibilityPerform(.press, on: Int(id)) } }
        callbacks.expandCollapse = { context, id, expand in MainActor.assumeIsolated { Win32Window.from(context).accessibilityPerform(expand ? .expand : .collapse, on: Int(id)) } }
        callbacks.setValue = { context, id, value in
            MainActor.assumeIsolated {
                let s = value.map { String(decodingCString: $0, as: UTF16.self) } ?? ""
                return Win32Window.from(context).accessibilitySetValue(.string(s), on: Int(id))
            }
        }
        callbacks.setRangeValue = { context, id, value in MainActor.assumeIsolated { Win32Window.from(context).accessibilitySetValue(.number(value), on: Int(id)) } }
        callbacks.select = { context, id, mode in
            MainActor.assumeIsolated {
                guard let provider = Win32Window.from(context).accessibilityOwner?.platformAccessibility else { return false }
                return provider.accessibilitySetSelected(mode != 2, on: Int(id), extending: mode != 0)
            }
        }
        callbacks.setFocus = { context, id in
            MainActor.assumeIsolated { Win32Window.from(context).accessibilityOwner?.platformAccessibility.accessibilityFocus(Int(id)) ?? false }
        }
        let root = cuia_root_create(UnsafeMutableRawPointer(hwnd), &callbacks)
        cuia_set_trace(NSView._traceInvalidation)
        cuia_set_use_com_threading(ProcessInfo.processInfo.environment["APPKITWIN_UIA_COM_THREADING"] != "0")
        uiaRoot = root
        return root
    }

    private static func from(_ context: UnsafeMutableRawPointer?) -> Win32Window {
        Unmanaged<Win32Window>.fromOpaque(context!).takeUnretainedValue()
    }

    private func accessibilityPerform(_ action: PlatformAccessibilityAction, on id: Int) -> Bool {
        accessibilityOwner?.platformAccessibility.accessibilityPerform(action, on: id) ?? false
    }

    private func accessibilitySetValue(_ value: PlatformAccessibilityValue, on id: Int) -> Bool {
        accessibilityOwner?.platformAccessibility.accessibilitySetValue(value, on: id) ?? false
    }

    /// WM_GETOBJECT: returns the LRESULT for a UI Automation request, nil otherwise.
    func accessibilityHandleGetObject(_ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT? {
        // UiaRootObjectId is -25; other object ids (OBJID_CLIENT, MSAA) go to DefWindowProc.
        guard Int32(truncatingIfNeeded: lParam) == -25, let root = ensureAccessibilityRoot() else { return nil }
        cuia_root_invalidate(root)
        if NSView._traceInvalidation { NSView._trace("uia WM_GETOBJECT '\(title)'") }
        return LRESULT(cuia_root_handle_getobject(root, UInt(wParam), Int(lParam)))
    }

    /// WM_MOVE, WM_SIZE, WM_DPICHANGED: the rectangles are stale; the next provider call
    /// pushes a fresh snapshot.
    func accessibilityGeometryChanged() {
        if let root = uiaRoot { cuia_root_invalidate(root) }
    }

    /// WM_DESTROY: UI Automation forgets the window and its providers.
    func accessibilityWindowDestroyed() {
        guard let root = uiaRoot else { return }
        cuia_root_destroy(root)
        uiaRoot = nil
    }

    /// PlatformWindow: the core's change becomes a UIA event when a client listens. The
    /// snapshot is marked stale at once; the events go out on the next turn of the event
    /// loop, coalesced, so a tree is never pushed while the view hierarchy is mid-change
    /// or from inside a provider call (a press that changes views).
    func accessibilityDidChange(_ change: PlatformAccessibilityChange) {
        if uiaRoot == nil, cuia_clients_are_listening() {
            // A window no client has asked about yet (a menu that just opened) still
            // announces itself: Narrator follows the menu-opened and focus events into it.
            switch change {
            case .menuOpened, .focus: ensureAccessibilityRoot()
            default: break
            }
        }
        guard let root = uiaRoot else {
            if NSView._traceInvalidation { NSView._trace("uia change \(change) '\(title)': no provider root yet (no WM_GETOBJECT so far)") }
            return
        }
        if case .menuClosed(let id) = change {
            // The menu window is about to go: raise now, with the providers clients hold.
            cuia_root_raise_menu(root, Int32(id), false)
        }
        cuia_root_invalidate(root)
        let listening = cuia_clients_are_listening()
        if NSView._traceInvalidation { NSView._trace("uia change \(change) '\(title)': clients listening \(listening)") }
        guard listening else { return }
        pendingAccessibilityChanges.append(change)
        guard !accessibilityFlushScheduled else { return }
        accessibilityFlushScheduled = true
        accessibilityBackend.post { [weak self] in self?.flushAccessibilityChanges() }
    }

    private func flushAccessibilityChanges() {
        accessibilityFlushScheduled = false
        let changes = pendingAccessibilityChanges
        pendingAccessibilityChanges.removeAll()
        guard let root = uiaRoot, !changes.isEmpty else { return }
        pushAccessibilityTree()
        var raised = Set<String>()
        for change in changes {
            let key = "\(change)"
            guard raised.insert(key).inserted else { continue }
            switch change {
            case .focus(let id):
                cuia_root_raise_focus(root, Int32(id ?? (accessibilityOwner?.platformAccessibility.accessibilityTree().id ?? 0)))
            case .value(let id): cuia_root_raise_property_changed(root, Int32(id), 0)
            case .name(let id): cuia_root_raise_property_changed(root, Int32(id), 1)
            case .selection(let id): cuia_root_raise_property_changed(root, Int32(id), 2)
            case .structure(let id): cuia_root_raise_structure_changed(root, Int32(id))
            case .childAdded(let parent, let child): cuia_root_raise_structure_child(root, Int32(parent), Int32(child), true)
            case .childRemoved(let parent, let child): cuia_root_raise_structure_child(root, Int32(parent), Int32(child), false)
            case .menuOpened(let id): cuia_root_raise_menu(root, Int32(id), true)
            case .menuClosed: break         // raised when it arrived
            }
        }
        if NSView._traceInvalidation { NSView._trace("uia events '\(title)': \(raised.count) raised from \(changes.count) changes") }
    }

    // MARK: Snapshot → nodes

    /// Where the snapshot's frames land on the physical desktop: relative to the client
    /// area, through the window's own DPI, from the client area's physical origin
    /// (`ClientToScreen`). Nothing depends on the primary monitor, so a window on a
    /// monitor of another scale (or one whose core frame lags a DPI change) maps right.
    func accessibilityScreenMapping(clientFrame: NSRect) -> PlatformAccessibilityScreenMapping? {
        guard let hwnd else { return nil }
        var origin = POINT(x: 0, y: 0)
        ClientToScreen(hwnd, &origin)
        // A menu bar sits in the non-client area above the client rect; AppKit's content
        // rect never includes it, so the client origin is the content's top-left.
        return PlatformAccessibilityScreenMapping(clientFrame: clientFrame, clientOriginX: Double(origin.x), clientOriginY: Double(origin.y), scale: Double(scale))
    }

    /// Flattens the owner's tree into the shim's node table (parents before children).
    func pushAccessibilityTree() {
        guard let root = uiaRoot, let tree = accessibilityOwner?.platformAccessibility.accessibilityTree() else { return }
        let primaryHeight = Win32Backend.primaryHeightPixels
        let scale = self.scale
        let mapping = accessibilityScreenMapping(clientFrame: tree.mappingClientFrame)
        var windowRect = RECT()
        if let hwnd { GetWindowRect(hwnd, &windowRect) }
        func pixels(_ e: PlatformAccessibilityElement, isRoot: Bool) -> RECT {
            if isRoot, hwnd != nil { return windowRect }
            guard let mapping else { return Win32Backend.win32Rect(e.frame, scale: scale, primaryHeight: primaryHeight) }
            let r = mapping.pixelRect(e.frame)
            return RECT(left: r.x, top: r.y, right: r.x + r.width, bottom: r.y + r.height)
        }
        var pool: [UInt16] = []
        var nodes: [CUIANode] = []
        var strings: [(node: Int, field: Int, offset: Int)] = []     // resolved to pointers below
        func intern(_ s: String?, node: Int, field: Int) {
            guard let s else { return }
            strings.append((node, field, pool.count))
            pool.append(contentsOf: s.utf16)
            pool.append(0)
        }
        func visit(_ e: PlatformAccessibilityElement, parent: Int32) {
            var n = CUIANode()
            n.id = Int32(e.id)
            n.parent = parent
            n.controlType = Win32Window.controlType(for: e)
            let r = pixels(e, isRoot: parent < 0)
            n.left = r.left; n.top = r.top; n.right = r.right; n.bottom = r.bottom
            let index = nodes.count
            intern(Win32Window.name(for: e), node: index, field: 0)
            intern(e.value?.stringValue, node: index, field: 1)
            intern(e.help, node: index, field: 2)
            intern(e.identifier, node: index, field: 3)
            intern(e.roleDescription, node: index, field: 4)
            intern(e.keyEquivalent, node: index, field: 5)
            var flags: UInt32 = 0
            if e.isEnabled { flags |= UInt32(CUIA_ENABLED) }
            if e.isFocusable { flags |= UInt32(CUIA_FOCUSABLE) }
            if e.isFocused { flags |= UInt32(CUIA_FOCUSED) }
            if e.isSelected { flags |= UInt32(CUIA_SELECTED) }
            if e.isSettable { flags |= UInt32(CUIA_SETTABLE) }
            if e.isMultiline { flags |= UInt32(CUIA_MULTILINE) }
            if e.allowsMultipleSelection { flags |= UInt32(CUIA_CAN_SELECT_MULTIPLE) }
            if e.subrole == "AXSecureTextField" { flags |= UInt32(CUIA_PASSWORD) }
            if let expanded = e.isExpanded { flags |= UInt32(CUIA_HAS_EXPAND_COLLAPSE); if expanded { flags |= UInt32(CUIA_EXPANDED) } }
            let role = e.role
            switch role {
            case "AXCheckBox": flags |= UInt32(CUIA_HAS_TOGGLE)
            case "AXRadioButton": flags |= UInt32(CUIA_HAS_SELECTION_ITEM); if e.subrole != "AXTabButton" { flags |= UInt32(CUIA_HAS_INVOKE) }; if e.value?.doubleValue == 1 { flags |= UInt32(CUIA_SELECTED) }
            case "AXTextField", "AXTextArea": flags |= UInt32(CUIA_HAS_VALUE) | UInt32(CUIA_HAS_TEXT)
            case "AXStaticText": flags |= UInt32(CUIA_HAS_TEXT)
            case "AXPopUpButton", "AXComboBox": flags |= UInt32(CUIA_HAS_VALUE); if e.actions.contains(.press) { flags |= UInt32(CUIA_HAS_INVOKE) }
            case "AXSlider", "AXScrollBar", "AXIncrementor", "AXLevelIndicator", "AXProgressIndicator": flags |= UInt32(CUIA_HAS_RANGE)
            case "AXTable", "AXList", "AXOutline", "AXTabGroup", "AXRadioGroup": flags |= UInt32(CUIA_HAS_SELECTION)
            case "AXRow": flags |= UInt32(CUIA_HAS_SELECTION_ITEM)
            case "AXGrid": flags |= UInt32(CUIA_HAS_SELECTION)
            case "AXMenuItem", "AXMenuBarItem":
                // UIA's menu item: Invoke for a command, ExpandCollapse (above) for an item
                // with a submenu, Toggle for one with a check mark.
                if e.isExpanded == nil, e.actions.contains(.press) { flags |= UInt32(CUIA_HAS_INVOKE) }
                if let c = e.checkedState, c != 0 { flags |= UInt32(CUIA_HAS_TOGGLE) }
            default: if e.actions.contains(.press) { flags |= UInt32(CUIA_HAS_INVOKE) }
            }
            if e.isSelectable && role != "AXRow" { flags |= UInt32(CUIA_HAS_SELECTION_ITEM) }
            if role != "AXCell" && role != "AXUnknown" && role != "AXGroup" && role != "AXScrollArea" && role != "AXScrollBar" { flags |= UInt32(CUIA_IS_CONTENT) }
            n.flags = flags
            if flags & UInt32(CUIA_HAS_RANGE) != 0 {
                n.rangeValue = e.value?.doubleValue ?? 0
                n.rangeMin = e.minValue ?? 0
                n.rangeMax = e.maxValue ?? 1
                n.rangeStep = (n.rangeMax - n.rangeMin) / 100
            }
            n.toggleState = Int32(e.checkedState ?? Int(e.value?.doubleValue ?? 0))
            if let sel = e.selectedTextRange { n.textSelectionStart = Int32(sel.location); n.textSelectionLength = Int32(sel.length) } else { n.textSelectionStart = -1; n.textSelectionLength = 0 }
            nodes.append(n)
            for c in e.children { visit(c, parent: n.id) }
            // Custom actions: UI Automation has no named-action pattern a provider can
            // offer (LegacyIAccessible has a single default action), so each one is a
            // Button child of its element that Invoke performs. They cover the element's
            // rectangle for screen readers but never take a hit test from it.
            for a in e.customActions {
                var b = CUIANode()
                b.id = Int32(a.id)
                b.parent = n.id
                b.controlType = 50000
                b.left = r.left; b.top = r.top; b.right = r.right; b.bottom = r.bottom
                b.flags = UInt32(CUIA_ENABLED) | UInt32(CUIA_HAS_INVOKE) | UInt32(CUIA_IS_CONTENT) | UInt32(CUIA_SKIP_HIT_TEST)
                b.textSelectionStart = -1
                let bi = nodes.count
                intern(a.name, node: bi, field: 0)
                intern("custom action", node: bi, field: 4)
                nodes.append(b)
            }
        }
        visit(tree, parent: -1)
        if pool.isEmpty { pool.append(0) }      // keeps a base address for the (empty) string table
        pool.withUnsafeBufferPointer { base in
            for s in strings {
                let p = base.baseAddress! + s.offset
                switch s.field {
                case 0: nodes[s.node].name = p
                case 1: nodes[s.node].value = p
                case 2: nodes[s.node].help = p
                case 3: nodes[s.node].automationId = p
                case 5: nodes[s.node].acceleratorKey = p
                default: nodes[s.node].itemType = p
                }
            }
            nodes.withUnsafeBufferPointer { cuia_root_set_nodes(root, $0.baseAddress, Int32($0.count)) }
        }
        if NSView._traceInvalidation { NSView._trace("uia tree '\(title)': \(nodes.count) nodes") }
    }

    /// The UIA name: the label, else the title, else a static text's value.
    private static func name(for e: PlatformAccessibilityElement) -> String? {
        if let l = e.label, !l.isEmpty { return l }
        if let t = e.title, !t.isEmpty { return t }
        if e.role == "AXStaticText", case .string(let s)? = e.value { return s }
        return nil
    }

    /// AppKit roles → UIA control types (the UIA_*ControlTypeId constants).
    private static func controlType(for e: PlatformAccessibilityElement) -> Int32 {
        if e.subrole == "AXTabButton" { return 50019 }      // TabItem
        switch e.role {
        case "AXButton", "AXMenuButton": return 50000
        case "AXCheckBox": return 50002
        case "AXRadioButton": return 50013
        case "AXStaticText": return 50020
        case "AXTextField", "AXTextArea": return 50004
        case "AXSlider": return 50015
        case "AXPopUpButton", "AXComboBox": return 50003
        case "AXImage": return 50006
        case "AXTable", "AXList", "AXOutline", "AXGrid": return 50008
        case "AXRow": return 50007
        case "AXScrollArea": return 50033
        case "AXScrollBar": return 50014
        case "AXGroup", "AXSplitGroup", "AXCell": return 50026
        case "AXRadioGroup": return 50008      // List of radio-button items (a segmented control)
        case "AXTabGroup": return 50018
        case "AXWindow", "AXSheet", "AXDrawer": return 50032
        case "AXMenu": return 50009
        case "AXMenuBar": return 50010
        case "AXMenuItem", "AXMenuBarItem": return 50011
        case "AXLink": return 50005
        case "AXProgressIndicator", "AXLevelIndicator": return 50012
        case "AXIncrementor": return 50016
        case "AXToolbar": return 50021
        case "AXSplitter": return 50038
        default: return 50025
        }
    }
}
#endif
