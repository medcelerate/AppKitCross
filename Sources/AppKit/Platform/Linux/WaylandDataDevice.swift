// The Wayland data device: the clipboard (wl_data_device.set_selection / selection) and
// drag and drop (wl_data_device.start_drag, enter/motion/leave/drop) over one object per
// seat. Data moves through pipes: a source answers `send` by writing the representation
// the other side asked for, a reader asks `receive` and reads the pipe to its end.
//
// The compositor runs drags: once `start_drag` is sent the pointer events stop and the
// drag comes back to this application's own surfaces as data-device events, so the
// core's tracker hands over at `beginDrag` and hears the outcome from the data source.

#if os(Linux)
import Foundation
import Glibc
import CCairo
import CWayland

@MainActor
final class WaylandDataDevice: PlatformPasteboard, PlatformDragDrop {
    private unowned let backend: WaylandBackend
    private var manager: OpaquePointer?          // wl_data_device_manager*
    private var managerVersion: UInt32 = 0
    private var device: OpaquePointer?           // wl_data_device*

    /// What another client offers (the selection, or the drag over our surface).
    private final class Offer {
        let proxy: OpaquePointer                 // wl_data_offer*
        var mimes: [String] = []
        var sourceActions: UInt32 = 0
        var action: UInt32 = 0
        init(proxy: OpaquePointer) { self.proxy = proxy }
    }
    private var offers: [Offer] = []             // announced, not yet claimed by enter/selection
    private var selectionOffer: Offer?
    private var dragOffer: Offer?

    private static let actionCopy: UInt32 = 1, actionMove: UInt32 = 2, actionAsk: UInt32 = 4

    init(backend: WaylandBackend) { self.backend = backend }

    var opaque: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }
    private static func from(_ data: UnsafeMutableRawPointer?) -> WaylandDataDevice? {
        data.map { Unmanaged<WaylandDataDevice>.fromOpaque($0).takeUnretainedValue() }
    }

    // MARK: Setup

    func managerAdded(name: UInt32, version: UInt32) {
        managerVersion = min(version, 3)
        manager = OpaquePointer(appkitwin_wl_registry_bind(backend.registry, name, "wl_data_device_manager", managerVersion))
        ensureDevice()
    }

    func seatDidChange() { ensureDevice() }

    private func ensureDevice() {
        guard device == nil, let manager, let seat = backend.seat else { return }
        device = wl_data_device_manager_get_data_device(manager, seat)
        wl_data_device_add_listener(device, WaylandDataDevice.deviceListener, opaque)
    }

    private static let offerListener = WaylandBackend.listener(wl_data_offer_listener(
        offer: { data, offer, mime in
            guard let mime, let d = WaylandDataDevice.from(data) else { return }
            MainActor.assumeIsolated { d.offer(offer)?.mimes.append(String(cString: mime)) }
        },
        source_actions: { data, offer, actions in
            guard let d = WaylandDataDevice.from(data) else { return }
            MainActor.assumeIsolated { d.offer(offer)?.sourceActions = actions }
        },
        action: { data, offer, action in
            guard let d = WaylandDataDevice.from(data) else { return }
            MainActor.assumeIsolated { d.offer(offer)?.action = action }
        }))

    private func offer(_ proxy: OpaquePointer?) -> Offer? {
        if let o = offers.first(where: { $0.proxy == proxy }) { return o }
        if selectionOffer?.proxy == proxy { return selectionOffer }
        if dragOffer?.proxy == proxy { return dragOffer }
        return nil
    }

    private static let deviceListener = WaylandBackend.listener(wl_data_device_listener(
        data_offer: { data, _, id in
            guard let id, let d = WaylandDataDevice.from(data) else { return }
            MainActor.assumeIsolated {
                let o = Offer(proxy: id)
                wl_data_offer_add_listener(id, WaylandDataDevice.offerListener, d.opaque)
                d.offers.append(o)
            }
        },
        enter: { data, _, serial, surface, x, y, id in
            guard let d = WaylandDataDevice.from(data) else { return }
            MainActor.assumeIsolated { d.dragEntered(serial: serial, surface: surface, x: wl_fixed_to_double(x), y: wl_fixed_to_double(y), offer: id) }
        },
        leave: { data, _ in
            guard let d = WaylandDataDevice.from(data) else { return }
            MainActor.assumeIsolated { d.dragLeft() }
        },
        motion: { data, _, _, x, y in
            guard let d = WaylandDataDevice.from(data) else { return }
            MainActor.assumeIsolated { d.dragMoved(x: wl_fixed_to_double(x), y: wl_fixed_to_double(y)) }
        },
        drop: { data, _ in
            guard let d = WaylandDataDevice.from(data) else { return }
            MainActor.assumeIsolated { d.dropped() }
        },
        selection: { data, _, id in
            guard let d = WaylandDataDevice.from(data) else { return }
            MainActor.assumeIsolated { d.selectionChanged(offer: id) }
        }))

    // MARK: Reading offers

    /// Asks the offer's source for `mime` and reads the pipe to its end (bounded).
    private func receive(_ offer: Offer, mime: String, timeout: TimeInterval = 2) -> Data? {
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else { return nil }
        wl_data_offer_receive(offer.proxy, mime, fds[1])
        wl_display_flush(backend.display)
        close(fds[1])
        defer { close(fds[0]) }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        let deadline = Date(timeIntervalSinceNow: timeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return nil }
            var p = [pollfd(fd: fds[0], events: Int16(POLLIN), revents: 0)]
            guard poll(&p, 1, Int32(remaining * 1000)) > 0 else { return nil }
            let n = Glibc.read(fds[0], &buffer, buffer.count)
            if n < 0 { if errno == EINTR || errno == EAGAIN { continue }; return nil }
            if n == 0 { return result }
            result.append(contentsOf: buffer[0..<n])
        }
    }

    /// The entries an offer can deliver, reading the best MIME type for each AppKit type.
    private func readAll(_ offer: Offer) -> [PlatformPasteboardEntry] {
        var result: [PlatformPasteboardEntry] = []
        var seen: Set<String> = []
        for mime in offer.mimes {
            guard let type = LinuxMime.type(for: mime), !seen.contains(type), let data = receive(offer, mime: mime) else { continue }
            let decoded = LinuxMime.decode(target: mime, data: data)
            guard !decoded.isEmpty else { continue }
            seen.insert(type)
            result += decoded
        }
        return result
    }

    // MARK: Sources (what this application offers)

    private final class Source {
        let proxy: OpaquePointer                 // wl_data_source*
        var entries: [PlatformPasteboardEntry]
        var isDrag = false
        var action: UInt32 = 0
        var dropPerformed = false
        init(proxy: OpaquePointer, entries: [PlatformPasteboardEntry]) { self.proxy = proxy; self.entries = entries }
    }
    private var selectionSource: Source?
    private var dragSource: Source?
    private weak var dragTracker: (any PlatformDragSource)?
    private var dragIcon: OpaquePointer?         // wl_surface*
    private var dragIconBuffer: OpaquePointer?   // wl_buffer*

    private static let sourceListener = WaylandBackend.listener(wl_data_source_listener(
        target: { _, _, _ in },
        send: { data, source, mime, fd in
            guard let d = WaylandDataDevice.from(data), let mime else { close(fd); return }
            MainActor.assumeIsolated { d.send(source, mime: String(cString: mime), fd: fd) }
        },
        cancelled: { data, source in
            guard let d = WaylandDataDevice.from(data) else { return }
            MainActor.assumeIsolated { d.cancelled(source) }
        },
        dnd_drop_performed: { data, source in
            guard let d = WaylandDataDevice.from(data) else { return }
            MainActor.assumeIsolated { d.source(source)?.dropPerformed = true }
        },
        dnd_finished: { data, source in
            guard let d = WaylandDataDevice.from(data) else { return }
            MainActor.assumeIsolated { d.finished(source) }
        },
        action: { data, source, action in
            guard let d = WaylandDataDevice.from(data) else { return }
            MainActor.assumeIsolated { d.source(source)?.action = action }
        }))

    private func source(_ proxy: OpaquePointer?) -> Source? {
        if selectionSource?.proxy == proxy { return selectionSource }
        if dragSource?.proxy == proxy { return dragSource }
        return nil
    }

    private func makeSource(entries: [PlatformPasteboardEntry]) -> Source? {
        guard let manager, let proxy = wl_data_device_manager_create_data_source(manager) else { return nil }
        let s = Source(proxy: proxy, entries: entries)
        wl_data_source_add_listener(proxy, WaylandDataDevice.sourceListener, opaque)
        for mime in LinuxMime.offeredTargets(for: entries) { wl_data_source_offer(proxy, mime) }
        return s
    }

    private func send(_ proxy: OpaquePointer?, mime: String, fd: Int32) {
        defer { close(fd) }
        guard let s = source(proxy), let data = LinuxMime.encode(target: mime, entries: s.entries) else { return }
        // Write it all, waiting for the reader (bounded) when the pipe fills.
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let deadline = Date(timeIntervalSinceNow: 5)
        var offset = 0
        data.withUnsafeBytes { buf in
            while offset < buf.count {
                let n = Glibc.write(fd, buf.baseAddress! + offset, buf.count - offset)
                if n > 0 { offset += n; continue }
                if n < 0 && errno != EAGAIN && errno != EINTR { return }
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else { return }
                var p = [pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)]
                guard poll(&p, 1, Int32(remaining * 1000)) > 0 else { return }
            }
        }
    }

    private func cancelled(_ proxy: OpaquePointer?) {
        if selectionSource?.proxy == proxy {
            wl_data_source_destroy(proxy)
            selectionSource = nil
            count += 1
        } else if dragSource?.proxy == proxy {
            endDrag(operation: [])
        }
    }

    private func finished(_ proxy: OpaquePointer?) {
        guard let s = dragSource, s.proxy == proxy else { return }
        endDrag(operation: operation(for: s.action))
    }

    private func operation(for action: UInt32) -> NSDragOperation {
        if action & WaylandDataDevice.actionMove != 0 { return .move }
        if action & WaylandDataDevice.actionCopy != 0 { return .copy }
        if action & WaylandDataDevice.actionAsk != 0 { return .generic }
        return []
    }

    private func actions(for op: NSDragOperation) -> UInt32 {
        var a: UInt32 = 0
        if op.contains(.copy) || op.contains(.link) || op.contains(.generic) || op.contains(.private) { a |= WaylandDataDevice.actionCopy }
        if op.contains(.move) || op.contains(.delete) { a |= WaylandDataDevice.actionMove }
        return a
    }

    // MARK: PlatformPasteboard

    private var count = 0
    private var cached: [PlatformPasteboardEntry]?

    func write(_ entries: [PlatformPasteboardEntry]) {
        guard let device, let s = makeSource(entries: entries) else { return }
        if let old = selectionSource { wl_data_source_destroy(old.proxy) }
        selectionSource = s
        wl_data_device_set_selection(device, s.proxy, backend.lastInputSerial)
        wl_display_flush(backend.display)
        count += 1
        cached = nil
    }

    func read() -> [PlatformPasteboardEntry] {
        if let s = selectionSource { return s.entries }
        if let cached { return cached }
        guard let offer = selectionOffer else { return [] }
        let entries = readAll(offer)
        cached = entries
        return entries
    }

    var changeCount: Int { count }

    private func selectionChanged(offer proxy: OpaquePointer?) {
        if let old = selectionOffer { wl_data_offer_destroy(old.proxy) }
        selectionOffer = nil
        if let proxy, let i = offers.firstIndex(where: { $0.proxy == proxy }) {
            selectionOffer = offers.remove(at: i)
        }
        // Our own source coming back as the selection is not a change.
        if selectionSource == nil || proxy == nil { cached = nil; count += 1 }
    }

    // MARK: PlatformDragDrop (source)

    func beginDrag(from window: PlatformWindow, entries: [(item: Int, entry: PlatformPasteboardEntry)], operations: NSDragOperation,
                   image: PlatformDragImage?, source: any PlatformDragSource) -> Bool {
        guard let device, let w = window as? WaylandWindow, let origin = w.surface, managerVersion >= 3,
              let s = makeSource(entries: entries.map(\.entry)) else { return false }
        s.isDrag = true
        wl_data_source_set_actions(s.proxy, actions(for: operations))
        dragSource = s
        dragTracker = source
        var icon: OpaquePointer? = nil
        if let image, let (surface, buffer) = makeIconSurface(image) { icon = surface; dragIcon = surface; dragIconBuffer = buffer }
        wl_data_device_start_drag(device, s.proxy, origin, icon, backend.lastButtonSerial)
        if let icon, let image {
            wl_surface_attach(icon, dragIconBuffer, 0, 0)
            wl_surface_damage(icon, 0, 0, Int32(image.width), Int32(image.height))
            wl_surface_commit(icon)
        }
        wl_display_flush(backend.display)
        return true
    }

    /// A surface showing the drag image, with the pointer at its hotspot.
    private func makeIconSurface(_ image: PlatformDragImage) -> (OpaquePointer, OpaquePointer)? {
        guard let shm = backend.shm, let compositor = backend.compositor, image.width > 0, image.height > 0 else { return nil }
        let stride = image.width * 4, length = stride * image.height
        let name = "/appkitwin-dnd-\(getpid())"
        let fd = shm_open(name, O_RDWR | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { return nil }
        shm_unlink(name)
        defer { close(fd) }
        guard ftruncate(fd, off_t(length)) == 0, let data = mmap(nil, length, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0), data != appkitwin_mmap_failed() else { return nil }
        image.bgra.withUnsafeBytes { src in data.copyMemory(from: src.baseAddress!, byteCount: min(length, src.count)) }
        munmap(data, length)
        guard let pool = wl_shm_create_pool(shm, fd, Int32(length)) else { return nil }
        defer { wl_shm_pool_destroy(pool) }
        guard let buffer = wl_shm_pool_create_buffer(pool, 0, Int32(image.width), Int32(image.height), Int32(stride), UInt32(WL_SHM_FORMAT_ARGB8888.rawValue)),
              let surface = wl_compositor_create_surface(compositor) else { return nil }
        let scale = Int32(max(1, Int(image.scale.rounded())))
        if backend.compositorVersion >= 3 { wl_surface_set_buffer_scale(surface, scale) }
        // The hotspot: the surface's offset is set when the role is given (start_drag),
        // through the attach position below (negative, in surface units).
        wl_surface_attach(surface, buffer, -Int32(image.hotspot.x) / scale, -Int32(image.hotspot.y) / scale)
        return (surface, buffer)
    }

    private func endDrag(operation: NSDragOperation) {
        guard let s = dragSource else { return }
        wl_data_source_destroy(s.proxy)
        dragSource = nil
        if let icon = dragIcon { wl_surface_destroy(icon); dragIcon = nil }
        if let b = dragIconBuffer { wl_buffer_destroy(b); dragIconBuffer = nil }
        wl_display_flush(backend.display)
        let t = dragTracker
        dragTracker = nil
        t?.platformDragEnded(at: backend.mouseLocation, operation: operation)
    }

    func foreignDragMoved(to screenPoint: NSPoint, operations: NSDragOperation) -> NSDragOperation { [] }
    func foreignDrop(at screenPoint: NSPoint, operations: NSDragOperation) -> Bool { false }
    func foreignDragEnded() { }

    // MARK: PlatformDragDrop (target)

    private var dragWindow: WaylandWindow?
    private var dragInfo: PlatformDragInfo?
    private var dragSerial: UInt32 = 0
    private var dragAcceptedMime: String?

    private func dragEntered(serial: UInt32, surface: OpaquePointer?, x: Double, y: Double, offer proxy: OpaquePointer?) {
        dragSerial = serial
        if let old = dragOffer { wl_data_offer_destroy(old.proxy) }
        dragOffer = nil
        if let proxy, let i = offers.firstIndex(where: { $0.proxy == proxy }) { dragOffer = offers.remove(at: i) }
        guard let window = backend.window(for: surface) else { return }
        dragWindow = window
        let location = window.windowPoint(fromSurface: NSPoint(x: x, y: y))
        let local = dragSource != nil
        var items: [[String]] = []
        var best: [String: String] = [:]
        var urls: [PlatformPasteboardEntry] = []
        if local, let s = dragSource {
            items = [Array(Set(s.entries.map(\.type)))]
        } else if let offer = dragOffer {
            var types: [String] = []
            for mime in offer.mimes {
                guard let type = LinuxMime.type(for: mime), best[type] == nil else { continue }
                best[type] = mime
                types.append(type)
            }
            items = [types]
            // A uri-list is read now so each file becomes an item (sources answer before the drop).
            if let uri = best[LinuxMime.fileURL], let data = receive(offer, mime: uri, timeout: 1) {
                urls = LinuxMime.decode(target: uri, data: data)
                let others = types.filter { $0 != LinuxMime.fileURL }
                if !urls.isEmpty { items = urls.enumerated().map { i, u in i == 0 ? others + [u.type] : [u.type] } }
            }
        }
        var ops: NSDragOperation = .copy
        if local { ops = .every }
        else if managerVersion >= 3, let a = dragOffer?.sourceActions, a != 0 {
            ops = []
            if a & WaylandDataDevice.actionCopy != 0 { ops.insert(.copy) }
            if a & WaylandDataDevice.actionMove != 0 { ops.insert(.move) }
            if a & WaylandDataDevice.actionAsk != 0 { ops.insert(.generic) }
        }
        let offer = dragOffer
        let info = PlatformDragInfo(location: location, sourceOperations: ops == [] ? .copy : ops, modifierFlags: backend.modifierFlags, items: items, isFromThisApplication: local) { [weak self] item, type in
            guard let self, let offer else { return nil }
            if type == LinuxMime.fileURL || type == LinuxMime.url { return urls.indices.contains(item) ? urls[item].data : nil }
            guard item == 0, let mime = best[type], let data = self.receive(offer, mime: mime) else { return nil }
            return LinuxMime.decode(target: mime, data: data).first { $0.type == type }?.data
        }
        dragInfo = info
        answer(window.ownerDragEntered(info), best: best)
    }

    /// Tells the source what the destination under the pointer would do.
    private func answer(_ op: NSDragOperation, best: [String: String]) {
        guard let offer = dragOffer else { return }
        let mime = op == [] ? nil : (best.values.first ?? offer.mimes.first)
        dragAcceptedMime = mime
        wl_data_offer_accept(offer.proxy, dragSerial, mime)
        if managerVersion >= 3 {
            let a = actions(for: op)
            wl_data_offer_set_actions(offer.proxy, a, op.contains(.move) ? WaylandDataDevice.actionMove : (a == 0 ? 0 : WaylandDataDevice.actionCopy))
        }
        wl_display_flush(backend.display)
    }

    private func dragMoved(x: Double, y: Double) {
        guard let window = dragWindow, let info = dragInfo else { return }
        info.location = window.windowPoint(fromSurface: NSPoint(x: x, y: y))
        info.modifierFlags = backend.modifierFlags
        answer(window.ownerDragUpdated(info), best: [:])
    }

    private func dragLeft() {
        dragWindow?.ownerDragExited()
        dragWindow = nil
        dragInfo = nil
        if let o = dragOffer { wl_data_offer_destroy(o.proxy); dragOffer = nil }
    }

    private func dropped() {
        guard let window = dragWindow, let info = dragInfo else { dragLeft(); return }
        info.modifierFlags = backend.modifierFlags
        let performed = window.ownerDrop(info)
        if let o = dragOffer {
            if managerVersion >= 3 {
                if performed != [] { wl_data_offer_finish(o.proxy) }
            }
            wl_data_offer_destroy(o.proxy)
            dragOffer = nil
        }
        wl_display_flush(backend.display)
        dragWindow = nil
        dragInfo = nil
    }
}
#endif
