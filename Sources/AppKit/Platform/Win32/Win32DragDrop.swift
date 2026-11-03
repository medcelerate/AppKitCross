// OLE drag and drop for the Win32 backend (ADR-0011 stage B), over the CD2D shim.
//
// OLE runs drags: `beginDrag` hands the data object and the drag image to DoDragDrop,
// which pumps this thread's messages until the drop and returns the effect. Every
// window is registered as a drop target, so drags from any application (and this one)
// come back through the shim's callbacks and reach the window's owner.

#if os(Windows)
import Foundation
import WinSDK
import CD2D

@MainActor
final class Win32DragDrop: PlatformDragDrop {
    private unowned let backend: Win32Backend
    private static let dropEffectCopy: UInt32 = 1, dropEffectMove: UInt32 = 2, dropEffectLink: UInt32 = 4

    init(backend: Win32Backend) {
        self.backend = backend
        var callbacks = CD2DDragCallbacks()
        callbacks.context = Unmanaged.passUnretained(self).toOpaque()
        callbacks.enter = { context, hwnd, data, local, x, y, keys, allowed in
            MainActor.assumeIsolated { Win32DragDrop.from(context).entered(hwnd: hwnd, data: data, local: local, x: x, y: y, keys: keys, allowed: allowed) }
        }
        callbacks.over = { context, hwnd, x, y, keys, allowed in
            MainActor.assumeIsolated { Win32DragDrop.from(context).moved(hwnd: hwnd, x: x, y: y, keys: keys, allowed: allowed) }
        }
        callbacks.leave = { context, hwnd in
            MainActor.assumeIsolated { Win32DragDrop.from(context).left(hwnd: hwnd) }
        }
        callbacks.drop = { context, hwnd, data, local, x, y, keys, allowed in
            MainActor.assumeIsolated { Win32DragDrop.from(context).dropped(hwnd: hwnd, data: data, local: local, x: x, y: y, keys: keys, allowed: allowed) }
        }
        callbacks.sourceTick = { context in
            MainActor.assumeIsolated { Win32DragDrop.from(context).backend.serviceWhileNested() }
        }
        _ = cd2d_dnd_initialize(&callbacks)
    }

    private static func from(_ context: UnsafeMutableRawPointer?) -> Win32DragDrop {
        Unmanaged<Win32DragDrop>.fromOpaque(context!).takeUnretainedValue()
    }

    func register(_ hwnd: HWND) { _ = cd2d_dnd_register(UnsafeMutableRawPointer(hwnd)) }
    func revoke(_ hwnd: HWND) { cd2d_dnd_revoke(UnsafeMutableRawPointer(hwnd)) }

    // MARK: Conversions

    private static func operations(fromEffects e: UInt32) -> NSDragOperation {
        var op: NSDragOperation = []
        if e & dropEffectCopy != 0 { op.insert(.copy) }
        if e & dropEffectMove != 0 { op.insert(.move) }
        if e & dropEffectLink != 0 { op.insert(.link) }
        return op
    }

    private static func effects(from op: NSDragOperation) -> UInt32 {
        var e: UInt32 = 0
        if op.contains(.copy) || op.contains(.generic) || op.contains(.private) { e |= dropEffectCopy }
        if op.contains(.move) || op.contains(.delete) { e |= dropEffectMove }
        if op.contains(.link) { e |= dropEffectLink }
        return e
    }

    /// One effect for the answer OLE shows (the cursor badge).
    private static func effect(from op: NSDragOperation) -> UInt32 {
        if op.contains(.copy) || op.contains(.generic) || op.contains(.private) { return dropEffectCopy }
        if op.contains(.move) || op.contains(.delete) { return dropEffectMove }
        if op.contains(.link) { return dropEffectLink }
        return 0
    }

    /// AppKit modifiers from OLE key state: Ctrl plays Command (as for key events), Alt is Option.
    private static func modifierFlags(fromKeys keys: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if keys & UInt32(MK_SHIFT) != 0 { flags.insert(.shift) }
        if keys & UInt32(MK_CONTROL) != 0 { flags.insert(.command) }
        if keys & 0x20 != 0 { flags.insert(.option) }       // MK_ALT
        if GetKeyState(VK_LWIN) < 0 || GetKeyState(VK_RWIN) < 0 { flags.insert(.control) }
        NSEvent._currentModifierFlags = flags
        return flags
    }

    private static func fileURL(fromPath path: String) -> Data {
        Data(URL(fileURLWithPath: path.replacingOccurrences(of: "\\", with: "/")).absoluteString.utf8)
    }

    private static func path(fromFileURL data: Data) -> Data {
        let s = String(decoding: data, as: UTF8.self)
        let path = URL(string: s)?.path ?? s
        return Data(path.replacingOccurrences(of: "/", with: "\\").utf8)
    }

    // MARK: Source

    func beginDrag(from window: PlatformWindow, entries: [(item: Int, entry: PlatformPasteboardEntry)], operations: NSDragOperation,
                   image: PlatformDragImage?, source: any PlatformDragSource) -> Bool {
        // Paths for CF_HDROP; everything else as is. Buffers live for the call.
        var types: [[UInt16]] = []
        var bytes: [[UInt8]] = []
        for (_, e) in entries {
            types.append(Array(e.type.utf16) + [0])
            bytes.append(e.type == "public.file-url" ? [UInt8](Win32DragDrop.path(fromFileURL: e.data)) : [UInt8](e.data))
        }
        var cEntries: [CD2DDragEntry] = []
        var effect: UInt32 = 0
        backend.beginNestedDrag()
        withExtendedLifetime((types, bytes)) {
            for i in entries.indices {
                cEntries.append(CD2DDragEntry(item: UInt32(entries[i].item),
                                              type: types[i].withUnsafeBufferPointer { $0.baseAddress },
                                              bytes: bytes[i].withUnsafeBufferPointer { $0.baseAddress },
                                              length: UInt32(bytes[i].count)))
            }
            let allowed = Win32DragDrop.effects(from: operations)
            if let image {
                effect = image.bgra.withUnsafeBufferPointer { px in
                    cd2d_dnd_do_drag(cEntries, UInt32(cEntries.count), allowed, px.baseAddress, UInt32(image.width), UInt32(image.height), Int32(image.hotspot.x), Int32(image.hotspot.y))
                }
            } else {
                effect = cd2d_dnd_do_drag(cEntries, UInt32(cEntries.count), allowed, nil, 0, 0, 0, 0)
            }
        }
        backend.endNestedDrag()
        source.platformDragEnded(at: backend.mouseLocation, operation: Win32DragDrop.operations(fromEffects: effect))
        return true
    }

    func foreignDragMoved(to screenPoint: NSPoint, operations: NSDragOperation) -> NSDragOperation { [] }
    func foreignDrop(at screenPoint: NSPoint, operations: NSDragOperation) -> Bool { false }
    func foreignDragEnded() { }

    // MARK: Target

    private var inbound: PlatformDragInfo?
    private var inboundWindow: Win32Window?

    /// Reads the data object into per-item type lists and a lookup for `load`.
    private func makeInfo(data: OpaquePointer?, local: Bool, window: Win32Window, x: Int32, y: Int32, keys: UInt32, allowed: UInt32) -> PlatformDragInfo {
        var entries: [(item: Int, type: String, data: Data)] = []
        if !local, let data {
            var count: UInt32 = 0
            if let read = cd2d_drag_data_read(data, &count) {
                for i in 0..<Int(count) {
                    let e = read[i]
                    let type = String(decodingCString: e.type!, as: UTF16.self)
                    var d = Data(bytes: e.bytes!, count: Int(e.length))
                    if type == "public.file-url" { d = Win32DragDrop.fileURL(fromPath: String(decoding: d, as: UTF8.self)) }
                    entries.append((Int(e.item), type, d))
                }
                cd2d_drag_data_free_entries(read, count)
            }
        }
        let itemCount = (entries.map(\.item).max() ?? -1) + 1
        let items: [[String]] = (0..<itemCount).map { i in entries.filter { $0.item == i }.map(\.type) }
        let location = window.contentPoint(screenX: x, screenY: y)
        return PlatformDragInfo(location: location, sourceOperations: Win32DragDrop.operations(fromEffects: allowed),
                                modifierFlags: Win32DragDrop.modifierFlags(fromKeys: keys), items: items, isFromThisApplication: local) { item, type in
            entries.first { $0.item == item && $0.type == type }?.data
        }
    }

    private func entered(hwnd: UnsafeMutableRawPointer?, data: OpaquePointer?, local: Bool, x: Int32, y: Int32, keys: UInt32, allowed: UInt32) -> UInt32 {
        guard let window = backend.windows.first(where: { $0.hwnd.map { UnsafeMutableRawPointer($0) } == hwnd }) else { return 0 }
        if let old = inboundWindow, old !== window { old.ownerDragExited() }
        let info = makeInfo(data: data, local: local, window: window, x: x, y: y, keys: keys, allowed: allowed)
        inbound = info
        inboundWindow = window
        return Win32DragDrop.effect(from: window.ownerDragEntered(info))
    }

    private func moved(hwnd: UnsafeMutableRawPointer?, x: Int32, y: Int32, keys: UInt32, allowed: UInt32) -> UInt32 {
        guard let info = inbound, let window = inboundWindow else { return 0 }
        info.location = window.contentPoint(screenX: x, screenY: y)
        info.sourceOperations = Win32DragDrop.operations(fromEffects: allowed)
        info.modifierFlags = Win32DragDrop.modifierFlags(fromKeys: keys)
        return Win32DragDrop.effect(from: window.ownerDragUpdated(info))
    }

    private func left(hwnd: UnsafeMutableRawPointer?) {
        inboundWindow?.ownerDragExited()
        inbound = nil
        inboundWindow = nil
    }

    private func dropped(hwnd: UnsafeMutableRawPointer?, data: OpaquePointer?, local: Bool, x: Int32, y: Int32, keys: UInt32, allowed: UInt32) -> UInt32 {
        guard let window = inboundWindow else { return 0 }
        let info = inbound ?? makeInfo(data: data, local: local, window: window, x: x, y: y, keys: keys, allowed: allowed)
        info.location = window.contentPoint(screenX: x, screenY: y)
        info.sourceOperations = Win32DragDrop.operations(fromEffects: allowed)
        info.modifierFlags = Win32DragDrop.modifierFlags(fromKeys: keys)
        inbound = nil
        inboundWindow = nil
        return Win32DragDrop.effect(from: window.ownerDrop(info))
    }
}
#endif
