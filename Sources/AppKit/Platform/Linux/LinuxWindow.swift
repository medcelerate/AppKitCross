// An X11 window painted through Cairo.

#if os(Linux)
import Foundation
import Glibc
import CoreGraphics
import CCairo
import CX11

@MainActor
final class LinuxWindow: PlatformWindow, AtspiWindow {
    private unowned let backend: LinuxBackend
    private weak var owner: PlatformWindowOwner?
    private(set) var xid: Window = 0
    private var _styleMask: NSWindow.StyleMask
    private var _frame: NSRect                 // AppKit points, bottom-left origin
    private(set) var isVisible = false
    private(set) var isKey = false
    private var _title = ""
    private var _minSize = NSSize(width: 0, height: 0)
    private var _maxSize = NSSize(width: 100_000, height: 100_000)
    private var _chrome = PlatformWindowChrome()
    private var wantsKey = false
    private var destroying = false
    private var pressedButtons = 0
    private var lastClickTime: UInt = 0
    private var clickCount = 1

    // Painting
    private var backing: OpaquePointer?        // cairo image surface, window size in pixels
    private var backingCairo: OpaquePointer?   // cairo_t on the backing surface
    private var xsurface: OpaquePointer?       // cairo xlib surface
    private var dirty: NSRect? = nil           // content points
    var needsPaint: Bool { dirty != nil && isVisible }

    var scale: CGFloat { backend.scale }
    var backingScaleFactor: CGFloat { scale }
    var xDisplay: OpaquePointer { backend.display }
    /// Child windows that GPU swap chains present into (ADR-0012).
    private var presentationSurfaces: [LinuxPresentationSurface] = []

    init(backend: LinuxBackend, owner: PlatformWindowOwner, contentRect: NSRect, styleMask: NSWindow.StyleMask) {
        self.backend = backend
        self.owner = owner
        _styleMask = styleMask
        _frame = contentRect
        let d = backend.display
        let px = pixelRect(contentRect)
        xid = XCreateSimpleWindow(d, backend.root, px.x, px.y, UInt32(max(1, px.w)), UInt32(max(1, px.h)), 0,
                                  XBlackPixel(d, backend.screen), XWhitePixel(d, backend.screen))
        XSelectInput(d, xid, ExposureMask | StructureNotifyMask | ButtonPressMask | ButtonReleaseMask | PointerMotionMask |
                     KeyPressMask | KeyReleaseMask | FocusChangeMask | EnterWindowMask | LeaveWindowMask)
        var protocols = [backend.wmDeleteWindow]
        XSetWMProtocols(d, xid, &protocols, 1)
        if backend.xiGestureOpcode != nil {
            // Touchpad pinch and swipe gestures from every master pointer (XI 2.4).
            var bits = [UInt8](repeating: 0, count: Int(XI_LASTEVENT >> 3) + 1)
            for ev in [XI_GesturePinchBegin, XI_GesturePinchUpdate, XI_GesturePinchEnd, XI_GestureSwipeBegin, XI_GestureSwipeUpdate, XI_GestureSwipeEnd] {
                bits[Int(ev >> 3)] |= UInt8(1 << (ev & 7))
            }
            bits.withUnsafeMutableBufferPointer { buf in
                var mask = XIEventMask(deviceid: XIAllMasterDevices, mask_len: Int32(buf.count), mask: buf.baseAddress)
                _ = XISelectEvents(d, xid, &mask, 1)
            }
        }
        // Drags from other applications (XDND version 5).
        var xdndVersion: [UInt] = [5]
        xdndVersion.withUnsafeMutableBufferPointer { buf in
            _ = XChangeProperty(d, xid, backend.atom("XdndAware"), XA_ATOM, 32, PropModeReplace, UnsafeRawPointer(buf.baseAddress!).assumingMemoryBound(to: UInt8.self), 1)
        }
        if styleMask.contains(.nonactivatingPanel) {
            // Pop-ups (menus) bypass the window manager: no decorations, no focus, on top.
            var attrs = XSetWindowAttributes()
            attrs.override_redirect = 1
            XChangeWindowAttributes(d, xid, UInt(CWOverrideRedirect), &attrs)
        }
        if !styleMask.contains(.titled) {
            // Borderless: ask the window manager for no decorations (Motif hints).
            let motif = XInternAtom(d, "_MOTIF_WM_HINTS", 0)
            var hints: [UInt] = [2, 0, 0, 0, 0]   // flags = MWM_HINTS_DECORATIONS, decorations = 0
            hints.withUnsafeBufferPointer { buf in
                _ = XChangeProperty(d, xid, motif, motif, 32, PropModeReplace, UnsafeRawPointer(buf.baseAddress!).assumingMemoryBound(to: UInt8.self), 5)
            }
        }
        backend.register(self)
        applySizeHints()
    }

    struct PixelRect { var x: Int32, y: Int32, w: Int32, h: Int32 }

    /// A content rect (points, y up) as pixels within the window (y down from its top).
    func childPixelRect(_ r: NSRect) -> PixelRect {
        PixelRect(x: Int32((r.minX * scale).rounded()), y: Int32(((_frame.height - r.maxY) * scale).rounded()),
                  w: max(1, Int32((r.width * scale).rounded())), h: max(1, Int32((r.height * scale).rounded())))
    }

    /// AppKit frame (points, y up) -> X pixels (y down from the top of the screen).
    private func pixelRect(_ r: NSRect) -> PixelRect {
        PixelRect(x: Int32((r.minX * scale).rounded()),
                  y: Int32((backend.screenHeightPx - r.maxY * scale).rounded()),
                  w: Int32((r.width * scale).rounded()), h: Int32((r.height * scale).rounded()))
    }

    var contentSize: NSSize { _frame.size }

    // MARK: PlatformWindow

    var title: String {
        get { _title }
        set {
            _title = newValue
            applyNativeTitle()
        }
    }
    /// `NSWindow.isDocumentEdited`: shown as "*" before the title, as GNOME's editors do.
    private var isDocumentEdited = false
    func setDocumentEdited(_ edited: Bool) {
        guard edited != isDocumentEdited else { return }
        isDocumentEdited = edited
        applyNativeTitle()
    }
    private func applyNativeTitle() {
        let shown = isDocumentEdited ? "*" + _title : _title
        XStoreName(backend.display, xid, shown)
        let utf8 = Array(shown.utf8)
        utf8.withUnsafeBufferPointer { buf in
            _ = XChangeProperty(backend.display, xid, backend.netWmName, backend.utf8String, 8, PropModeReplace, buf.baseAddress, Int32(buf.count))
        }
    }

    var frame: NSRect {
        get { _frame }
        set {
            _frame = newValue
            let px = pixelRect(newValue)
            XMoveResizeWindow(backend.display, xid, px.x, px.y, UInt32(max(1, px.w)), UInt32(max(1, px.h)))
            resizeBacking()
            dirty = NSRect(origin: .zero, size: _frame.size)
        }
    }

    var styleMask: NSWindow.StyleMask {
        get { _styleMask }
        set { _styleMask = newValue }
    }

    var minSize: NSSize {
        get { _minSize }
        set { _minSize = newValue; applySizeHints() }
    }

    var maxSize: NSSize {
        get { _maxSize }
        set { _maxSize = newValue; applySizeHints() }
    }

    var chrome: PlatformWindowChrome {
        get { _chrome }
        set { _chrome = newValue }
    }

    private func applySizeHints() {
        var hints = XSizeHints()
        hints.flags = PMinSize | PMaxSize
        hints.min_width = Int32(_minSize.width * scale)
        hints.min_height = Int32(_minSize.height * scale)
        hints.max_width = Int32(min(_maxSize.width, 100_000) * scale)
        hints.max_height = Int32(min(_maxSize.height, 100_000) * scale)
        if !_styleMask.contains(.resizable) {
            hints.min_width = Int32(_frame.width * scale); hints.max_width = hints.min_width
            hints.min_height = Int32(_frame.height * scale); hints.max_height = hints.min_height
        }
        XSetWMNormalHints(backend.display, xid, &hints)
    }

    func frameRect(forContentRect contentRect: NSRect) -> NSRect { contentRect }
    func contentRect(forFrameRect frameRect: NSRect) -> NSRect { frameRect }

    func show() {
        guard !isVisible else { return }
        XMapRaised(backend.display, xid)
        isVisible = true
        dirty = NSRect(origin: .zero, size: _frame.size)
        XFlush(backend.display)
    }

    func hide() {
        guard isVisible else { return }
        XUnmapWindow(backend.display, xid)
        isVisible = false
    }

    func makeKey() {
        wantsKey = true
        if isVisible { XSetInputFocus(backend.display, xid, RevertToParent, Time(CurrentTime)) }
    }

    func orderBack() { XLowerWindow(backend.display, xid) }

    private var minimized = false
    private var maximized = false
    func miniaturize() {
        guard isVisible else { return }
        XIconifyWindow(backend.display, xid, backend.screen)
        XFlush(backend.display)
        minimized = true
    }
    func deminiaturize() {
        guard minimized else { return }
        XMapWindow(backend.display, xid)
        XFlush(backend.display)
        minimized = false
    }
    /// Toggles _NET_WM_STATE_MAXIMIZED_{HORZ,VERT} through the window manager (EWMH).
    func zoom() {
        let action = maximized ? 0 : 1   // _NET_WM_STATE_REMOVE / _NET_WM_STATE_ADD
        var ev = XEvent()
        ev.xclient.type = ClientMessage
        ev.xclient.window = xid
        ev.xclient.message_type = backend.atom("_NET_WM_STATE")
        ev.xclient.format = 32
        ev.xclient.data.l.0 = action
        ev.xclient.data.l.1 = Int(backend.atom("_NET_WM_STATE_MAXIMIZED_HORZ"))
        ev.xclient.data.l.2 = Int(backend.atom("_NET_WM_STATE_MAXIMIZED_VERT"))
        ev.xclient.data.l.3 = 1
        XSendEvent(backend.display, backend.root, 0, SubstructureRedirectMask | SubstructureNotifyMask, &ev)
        XFlush(backend.display)
        maximized.toggle()
    }
    var isMiniaturized: Bool { minimized }

    /// ICCCM WM_STATE: the window manager keeps the window's state in this property
    /// (1 normal, 3 iconic).
    private func wmStateIsIconic() -> Bool {
        let atom = backend.atom("WM_STATE")
        var actualType: Atom = 0, format: Int32 = 0, count: UInt = 0, after: UInt = 0
        var data: UnsafeMutablePointer<UInt8>? = nil
        guard XGetWindowProperty(backend.display, xid, atom, 0, 2, 0, atom, &actualType, &format, &count, &after, &data) == 0, let data else { return false }
        defer { XFree(data) }
        guard format == 32, count >= 1 else { return false }
        return data.withMemoryRebound(to: Int.self, capacity: 1) { $0.pointee == 3 }
    }
    var isZoomed: Bool { maximized }

    // MARK: Accessibility (ADR-0013)
    var atspiOwner: PlatformWindowOwner? { owner }
    var atspiIsVisible: Bool { isVisible }
    var atspiIsKey: Bool { isKey }
    func accessibilityDidChange(_ change: PlatformAccessibilityChange) { backend.atspi?.windowDidChange(self, change) }

    func close() {
        guard !destroying else { return }
        destroying = true
        backend.unregister(self)
        for s in presentationSurfaces { s.close() }
        releaseSurfaces()
        XDestroyWindow(backend.display, xid)
        XFlush(backend.display)
        xid = 0
    }

    func setNeedsDisplay(_ rect: NSRect?) {
        let bounds = NSRect(origin: .zero, size: _frame.size)
        if let r = rect { dirty = (dirty ?? NSRect.null).union(r).intersection(bounds) } else { dirty = bounds }
    }

    func displayIfNeeded() { if dirty != nil { paintIfNeeded() } }

    func display() {
        dirty = NSRect(origin: .zero, size: _frame.size)
        paintIfNeeded()
    }

    // MARK: Painting

    private func releaseSurfaces() {
        if let c = backingCairo { cairo_destroy(c) }
        if let b = backing { cairo_surface_destroy(b) }
        if let x = xsurface { cairo_surface_destroy(x) }
        backingCairo = nil; backing = nil; xsurface = nil
    }

    private func resizeBacking() {
        releaseSurfaces()
    }

    private func ensureSurfaces() -> Bool {
        let w = Int32(max(1, (_frame.width * scale).rounded())), h = Int32(max(1, (_frame.height * scale).rounded()))
        if backing == nil {
            backing = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h)
            guard let b = backing else { return false }
            backingCairo = cairo_create(b)
        }
        if xsurface == nil {
            let visual = XDefaultVisual(backend.display, backend.screen)
            xsurface = cairo_xlib_surface_create(backend.display, xid, visual, w, h)
        } else {
            cairo_xlib_surface_set_size(xsurface, w, h)
        }
        return backingCairo != nil && xsurface != nil
    }

    func paintIfNeeded() {
        guard isVisible, xid != 0, let rect = dirty, ensureSurfaces(), let cr = backingCairo, let xs = xsurface else { return }
        dirty = nil
        let size = _frame.size
        let flip = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: 0, ty: size.height * scale)
        cairo_save(cr)
        do {
            let ctx = CGContext(cairo: cr, baseTransform: flip, width: Int(size.width * scale), height: Int(size.height * scale))
            ctx.clip(to: rect)
            owner?.platformWindowDraw(into: ctx, dirtyRect: rect)
        }
        cairo_restore(cr)
        cairo_surface_flush(backing)
        // Blit the dirty pixels to the window.
        guard let xcr = cairo_create(xs) else { return }
        cairo_set_source_surface(xcr, backing, 0, 0)
        let px = NSRect(x: rect.minX * scale, y: (size.height - rect.maxY) * scale, width: rect.width * scale, height: rect.height * scale)
        cairo_rectangle(xcr, Double(px.minX.rounded(.down)), Double(px.minY.rounded(.down)), Double(px.width.rounded(.up) + 1), Double(px.height.rounded(.up) + 1))
        cairo_fill(xcr)
        cairo_surface_flush(xs)
        cairo_destroy(xcr)
        XFlush(backend.display)
    }

    // MARK: Presentation surfaces (ADR-0012)

    func makePresentationSurface(frame: NSRect) -> (any PlatformPresentationSurface)? {
        guard xid != 0, !destroying else { return nil }
        let s = LinuxPresentationSurface(window: self, frame: frame)
        presentationSurfaces.append(s)
        return s
    }

    func presentationSurfaceClosed(_ s: LinuxPresentationSurface) { presentationSurfaces.removeAll { $0 === s } }

    /// The window's pixels from the server (`XGetImage`), child windows included: what a
    /// swap chain presented is in it once the server has processed the present.
    func captureContent() -> CGImage? {
        guard xid != 0, isVisible else { return nil }
        let d = backend.display
        XSync(d, 0)
        let w = Int(max(1, (_frame.width * scale).rounded())), h = Int(max(1, (_frame.height * scale).rounded()))
        guard let image = XGetImage(d, xid, 0, 0, UInt32(w), UInt32(h), ~UInt(0), ZPixmap) else { return nil }
        defer { _ = image.pointee.f.destroy_image?(image) }
        guard image.pointee.bits_per_pixel == 32, let src = image.pointee.data else { return nil }
        let rowStride = w * 4
        var data = Data(count: rowStride * h)
        let rowBytes = Int(image.pointee.bytes_per_line)
        data.withUnsafeMutableBytes { dst in
            for y in 0..<h { memcpy(dst.baseAddress! + y * rowStride, src + y * rowBytes, rowStride) }
            // A 24-bit visual leaves the top byte undefined: the window is opaque.
            for i in Swift.stride(from: 3, to: rowStride * h, by: 4) { dst[i] = 255 }
        }
        return CGImage.fromBGRA(width: w, height: h, stride: rowStride, data: data)
    }

    // MARK: Cursor

    func applyCursor(_ cursor: Cursor) {
        guard xid != 0 else { return }
        XDefineCursor(backend.display, xid, cursor)
    }

    private static var blank: Cursor = 0
    func blankCursor() -> Cursor {
        if LinuxWindow.blank == 0 {
            var fg = XColor(), bg = XColor()
            var bits: [CChar] = [0]
            let pixmap = XCreateBitmapFromData(backend.display, xid, &bits, 1, 1)
            LinuxWindow.blank = XCreatePixmapCursor(backend.display, pixmap, pixmap, &fg, &bg, 0, 0)
            XFreePixmap(backend.display, pixmap)
        }
        return LinuxWindow.blank
    }

    // MARK: Events

    private func windowNumber() -> Int { (owner as? NSWindow)?.windowNumber ?? 0 }

    private func contentPoint(x: Int32, y: Int32) -> NSPoint {
        NSPoint(x: CGFloat(x) / scale, y: _frame.height - CGFloat(y) / scale)
    }

    private func modifierFlags(_ state: UInt32) -> NSEvent.ModifierFlags {
        let flags = LinuxBackend.modifierFlags(fromState: state)
        NSEvent._currentModifierFlags = flags
        return flags
    }

    // Drags delivered by XDND (LinuxDragDrop.swift) reach the owner through these.
    func ownerDragEntered(_ drag: PlatformDragInfo) -> NSDragOperation { owner?.platformDragEntered(drag) ?? [] }
    func ownerDragUpdated(_ drag: PlatformDragInfo) -> NSDragOperation { owner?.platformDragUpdated(drag) ?? [] }
    func ownerDragExited() { owner?.platformDragExited() }
    func ownerDrop(_ drag: PlatformDragInfo) -> NSDragOperation { owner?.platformDrop(drag) ?? [] }

    private func seconds(_ t: Time) -> TimeInterval { TimeInterval(t) / 1000 }

    private func mouse(_ type: NSEvent.EventType, x: Int32, y: Int32, state: UInt32, time: Time, button: Int, clickCount: Int = 1) {
        let e = NSEvent._mouseEvent(type: type, location: contentPoint(x: x, y: y), modifierFlags: modifierFlags(state),
                                    timestamp: seconds(time), windowNumber: windowNumber(), clickCount: clickCount, buttonNumber: button)
        owner?.platformWindowDispatch(e)
    }

    private func lookup(_ xkey: inout XKeyEvent) -> (String, KeySym) {
        var buffer = [CChar](repeating: 0, count: 32)
        var keysym: KeySym = 0
        let n = XLookupString(&xkey, &buffer, 32, &keysym, nil)
        var text = ""
        if n > 0 {
            let bytes = buffer[0..<Int(n)].map { UInt8(bitPattern: $0) }
            text = String(String.UnicodeScalarView(bytes.map { UnicodeScalar($0) }))
        } else if keysym & 0x0100_0000 != 0, let scalar = UnicodeScalar(UInt32(keysym & 0x00FF_FFFF)) {
            text = String(scalar)
        }
        return (text, keysym)
    }

    private func key(_ type: NSEvent.EventType, _ xkey: XKeyEvent) {
        var ev = xkey
        let (chars0, keysym) = lookup(&ev)
        if LinuxKeys.special[keysym] == nil && LinuxKeys.modifiers.contains(keysym) {
            let e = NSEvent(type: .flagsChanged, location: .zero, modifierFlags: modifierFlags(xkey.state), timestamp: seconds(xkey.time), windowNumber: windowNumber())
            owner?.platformWindowDispatch(e)
            return
        }
        var chars = chars0, plain = chars0
        var keyCode = UInt16(truncatingIfNeeded: keysym)
        if let special = LinuxKeys.special[keysym] {
            chars = special.0; plain = special.0; keyCode = special.1
        } else {
            var noMods = xkey
            noMods.state &= ~UInt32(ControlMask | Mod1Mask | Mod4Mask)
            let (p, _) = lookup(&noMods)
            if !p.isEmpty { plain = p }
            if plain.unicodeScalars.count == 1, let v = plain.unicodeScalars.first?.value, v < 0x20, keysym >= 0x61, keysym <= 0x7a {
                plain = String(UnicodeScalar(UInt8(keysym)))
            }
        }
        let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifierFlags(xkey.state), timestamp: seconds(xkey.time),
                                 windowNumber: windowNumber(), context: nil, characters: chars,
                                 charactersIgnoringModifiers: plain, isARepeat: false, keyCode: keyCode)!
        owner?.platformWindowDispatch(e)
    }

    // MARK: Gestures (XInput 2.4)

    private var pinchScale = 1.0
    private var swipeTotal = (x: 0.0, y: 0.0)

    /// A touchpad pinch: begin/end bracket the gesture; each update carries the
    /// cumulative scale (1 at the start) and the angle change in degrees (clockwise
    /// positive in XI, counterclockwise in AppKit).
    func gesturePinch(evtype: Int32, time: Time, x: Double, y: Double, scale s: Double, deltaAngle: Double, state: UInt32, cancelled: Bool) {
        let p = contentPoint(x: Int32(x), y: Int32(y))
        let flags = LinuxBackend.modifierFlags(fromState: state)
        func send(_ e: NSEvent) { owner?.platformWindowDispatch(e) }
        switch evtype {
        case XI_GesturePinchBegin:
            pinchScale = 1
            send(NSEvent._gestureEvent(type: .beginGesture, location: p, modifierFlags: flags, timestamp: seconds(time), windowNumber: windowNumber()))
        case XI_GesturePinchUpdate:
            let magnification = pinchScale > 0 ? CGFloat(s / pinchScale - 1) : 0
            pinchScale = s
            if magnification != 0 {
                send(NSEvent._gestureEvent(type: .magnify, location: p, modifierFlags: flags, timestamp: seconds(time), windowNumber: windowNumber(),
                                           magnification: magnification, phase: .changed))
            }
            if deltaAngle != 0 {
                send(NSEvent._gestureEvent(type: .rotate, location: p, modifierFlags: flags, timestamp: seconds(time), windowNumber: windowNumber(),
                                           rotation: Float(-deltaAngle), phase: .changed))
            }
        default:
            send(NSEvent._gestureEvent(type: .endGesture, location: p, modifierFlags: flags, timestamp: seconds(time), windowNumber: windowNumber(),
                                       phase: cancelled ? .cancelled : .ended))
        }
    }

    /// A three-finger swipe: reported once, at the end, as AppKit's swipe event with the
    /// dominant direction (deltaX 1 for a swipe to the left, deltaY 1 for a swipe up).
    func gestureSwipe(evtype: Int32, time: Time, x: Double, y: Double, dx: Double, dy: Double, state: UInt32, cancelled: Bool) {
        switch evtype {
        case XI_GestureSwipeBegin: swipeTotal = (0, 0)
        case XI_GestureSwipeUpdate: swipeTotal.x += dx; swipeTotal.y += dy
        default:
            guard !cancelled, abs(swipeTotal.x) + abs(swipeTotal.y) > 20 else { return }
            let horizontal = abs(swipeTotal.x) >= abs(swipeTotal.y)
            let e = NSEvent._gestureEvent(type: .swipe, location: contentPoint(x: Int32(x), y: Int32(y)), modifierFlags: LinuxBackend.modifierFlags(fromState: state),
                                          timestamp: seconds(time), windowNumber: windowNumber(),
                                          deltaX: horizontal ? (swipeTotal.x < 0 ? 1 : -1) : 0, deltaY: horizontal ? 0 : (swipeTotal.y < 0 ? 1 : -1))
            owner?.platformWindowDispatch(e)
        }
    }

    func handle(_ event: inout XEvent) {
        switch Int32(event.type) {
        case Expose:
            let e = event.xexpose
            let r = NSRect(x: CGFloat(e.x) / scale, y: _frame.height - CGFloat(e.y + e.height) / scale,
                           width: CGFloat(e.width) / scale, height: CGFloat(e.height) / scale)
            setNeedsDisplay(r)
        case ConfigureNotify:
            let c = event.xconfigure
            let newSize = NSSize(width: CGFloat(c.width) / scale, height: CGFloat(c.height) / scale)
            var x = c.x, y = c.y
            if c.send_event == 0 {
                // Position is relative to the parent (frame) window: translate to root.
                var child: Window = 0
                XTranslateCoordinates(backend.display, xid, backend.root, 0, 0, &x, &y, &child)
            }
            let origin = NSPoint(x: CGFloat(x) / scale, y: (backend.screenHeightPx - CGFloat(y)) / scale - newSize.height)
            let old = _frame
            _frame = NSRect(origin: origin, size: newSize)
            if old.size != newSize {
                resizeBacking()
                dirty = NSRect(origin: .zero, size: newSize)
            }
            if old != _frame { owner?.platformWindowDidChangeFrame(_frame) }
        case MapNotify:
            isVisible = true
            if wantsKey { XSetInputFocus(backend.display, xid, RevertToParent, Time(CurrentTime)) }
            dirty = NSRect(origin: .zero, size: _frame.size)
            if minimized { minimized = false; owner?.platformWindowDidDeminiaturize() }
        case UnmapNotify:
            isVisible = false
            // The window manager iconified the window (its WM_STATE says so), or
            // `miniaturize()` did: either way the owner hears it once.
            if minimized || wmStateIsIconic() { minimized = true; owner?.platformWindowDidMiniaturize() }
        case DestroyNotify:
            backend.unregister(self)
            if !destroying { destroying = true; owner?.platformWindowWillClose() }
            for s in presentationSurfaces { s.windowWasDestroyed() }
            presentationSurfaces.removeAll()
            xid = 0
        case ClientMessage:
            if backend.x11DragDrop.handle(&event, window: self) { return }
            if Atom(event.xclient.data.l.0) == backend.wmDeleteWindow {
                if owner?.platformWindowShouldClose() ?? true {
                    if let owner { owner.platformWindowWillClose() } else { close() }
                }
            }
        case FocusIn:
            isKey = true
            owner?.platformWindowDidBecomeKey()
        case FocusOut:
            isKey = false
            owner?.platformWindowDidResignKey()
        case ButtonPress:
            let b = event.xbutton
            backend.lastEventTime = b.time
            switch b.button {
            case 4, 5, 6, 7:
                let vertical = b.button == 4 || b.button == 5
                let delta: CGFloat = (b.button == 4 || b.button == 6) ? 3 : -3
                let e = NSEvent._scrollEvent(location: contentPoint(x: b.x, y: b.y), modifierFlags: modifierFlags(b.state), timestamp: seconds(b.time),
                                             windowNumber: windowNumber(), deltaX: vertical ? 0 : delta, deltaY: vertical ? delta : 0, precise: false)
                owner?.platformWindowDispatch(e)
            default:
                let (type, bit, number): (NSEvent.EventType, Int, Int) = b.button == 1 ? (.leftMouseDown, 1, 0) : b.button == 3 ? (.rightMouseDown, 2, 1) : (.otherMouseDown, 4, 2)
                if b.time - lastClickTime < 400 { clickCount += 1 } else { clickCount = 1 }
                lastClickTime = b.time
                pressedButtons |= bit
                NSEvent._pressedMouseButtons = pressedButtons
                mouse(type, x: b.x, y: b.y, state: b.state, time: b.time, button: number, clickCount: clickCount)
            }
        case ButtonRelease:
            let b = event.xbutton
            backend.lastEventTime = b.time
            guard b.button <= 3 else { return }
            let (type, bit, number): (NSEvent.EventType, Int, Int) = b.button == 1 ? (.leftMouseUp, 1, 0) : b.button == 3 ? (.rightMouseUp, 2, 1) : (.otherMouseUp, 4, 2)
            pressedButtons &= ~bit
            NSEvent._pressedMouseButtons = pressedButtons
            mouse(type, x: b.x, y: b.y, state: b.state, time: b.time, button: number, clickCount: clickCount)
        case MotionNotify:
            let m = event.xmotion
            backend.lastEventTime = m.time
            if pressedButtons & 1 != 0 { mouse(.leftMouseDragged, x: m.x, y: m.y, state: m.state, time: m.time, button: 0) }
            else if pressedButtons & 2 != 0 { mouse(.rightMouseDragged, x: m.x, y: m.y, state: m.state, time: m.time, button: 1) }
            else if pressedButtons & 4 != 0 { mouse(.otherMouseDragged, x: m.x, y: m.y, state: m.state, time: m.time, button: 2) }
            else { mouse(.mouseMoved, x: m.x, y: m.y, state: m.state, time: m.time, button: 0, clickCount: 0) }
        case KeyPress:
            backend.lastEventTime = event.xkey.time
            key(.keyDown, event.xkey)
        case KeyRelease:
            backend.lastEventTime = event.xkey.time
            key(.keyUp, event.xkey)
        default:
            break
        }
    }
}

/// A child X window at a content rect of a `LinuxWindow`, for a Vulkan swap chain
/// (`VK_KHR_xlib_surface`). It selects no input, so pointer and key events propagate to
/// the window as if the child were not there; its background is None, so the server
/// never paints it and the swap chain's frames are all that shows.
@MainActor
final class LinuxPresentationSurface: PlatformPresentationSurface {
    private unowned let window: LinuxWindow
    private let display: OpaquePointer
    private(set) var child: Window = 0

    init(window: LinuxWindow, frame: NSRect) {
        self.window = window
        display = window.xDisplay
        let px = window.childPixelRect(frame)
        child = XCreateSimpleWindow(display, window.xid, px.x, px.y, UInt32(px.w), UInt32(px.h), 0, 0, 0)
        XSetWindowBackgroundPixmap(display, child, 0)
        XMapWindow(display, child)
        XFlush(display)
    }

    var handle: PlatformPresentationSurfaceHandle {
        PlatformPresentationSurfaceHandle(kind: .xlib, display: UnsafeMutableRawPointer(display), window: UInt(child))
    }

    func setFrame(_ frame: NSRect) {
        guard child != 0 else { return }
        let px = window.childPixelRect(frame)
        XMoveResizeWindow(display, child, px.x, px.y, UInt32(px.w), UInt32(px.h))
        XFlush(display)
    }

    /// The parent went away (with its children): nothing to destroy.
    func windowWasDestroyed() { child = 0 }

    func close() {
        guard child != 0 else { return }
        XDestroyWindow(display, child)
        XFlush(display)
        child = 0
        window.presentationSurfaceClosed(self)
    }
}
#endif
