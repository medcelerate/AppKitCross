// An X11 window painted through Cairo.

#if os(Linux)
import Foundation
import Glibc
import CoreGraphics
import CCairo
import CX11

@MainActor
final class LinuxWindow: PlatformWindow {
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

    private struct PixelRect { var x: Int32, y: Int32, w: Int32, h: Int32 }

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
            XStoreName(backend.display, xid, newValue)
            let utf8 = Array(newValue.utf8)
            utf8.withUnsafeBufferPointer { buf in
                _ = XChangeProperty(backend.display, xid, backend.netWmName, backend.utf8String, 8, PropModeReplace, buf.baseAddress, Int32(buf.count))
            }
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

    func close() {
        guard !destroying else { return }
        destroying = true
        backend.unregister(self)
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
        var flags: NSEvent.ModifierFlags = []
        if state & UInt32(ShiftMask) != 0 { flags.insert(.shift) }
        if state & UInt32(LockMask) != 0 { flags.insert(.capsLock) }
        // Ctrl plays Command (as on Windows) so AppKit key equivalents land on Ctrl+key; Super maps to .control.
        if state & UInt32(ControlMask) != 0 { flags.insert(.command) }
        if state & UInt32(Mod1Mask) != 0 { flags.insert(.option) }
        if state & UInt32(Mod4Mask) != 0 { flags.insert(.control) }
        NSEvent._currentModifierFlags = flags
        return flags
    }

    private func seconds(_ t: Time) -> TimeInterval { TimeInterval(t) / 1000 }

    private func mouse(_ type: NSEvent.EventType, x: Int32, y: Int32, state: UInt32, time: Time, button: Int, clickCount: Int = 1) {
        let e = NSEvent._mouseEvent(type: type, location: contentPoint(x: x, y: y), modifierFlags: modifierFlags(state),
                                    timestamp: seconds(time), windowNumber: windowNumber(), clickCount: clickCount, buttonNumber: button)
        owner?.platformWindowDispatch(e)
    }

    /// X keysyms that AppKit reports as function-key characters or control characters,
    /// with the macOS virtual key code AppKit clients may compare against.
    private static let specialKeys: [KeySym: (String, UInt16)] = [
        0xff51: ("\u{F702}", 123), 0xff53: ("\u{F703}", 124), 0xff52: ("\u{F700}", 126), 0xff54: ("\u{F701}", 125),
        0xff50: ("\u{F729}", 115), 0xff57: ("\u{F72B}", 119), 0xff55: ("\u{F72C}", 116), 0xff56: ("\u{F72D}", 121),
        0xffff: ("\u{F728}", 117), 0xff08: ("\u{7F}", 51), 0xff0d: ("\r", 36), 0xff8d: ("\r", 76), 0xff09: ("\t", 48),
        0xff1b: ("\u{1B}", 53), 0xff63: ("\u{F727}", 114),
        0xffbe: ("\u{F704}", 122), 0xffbf: ("\u{F705}", 120), 0xffc0: ("\u{F706}", 99), 0xffc1: ("\u{F707}", 118),
        0xffc2: ("\u{F708}", 96), 0xffc3: ("\u{F709}", 97), 0xffc4: ("\u{F70A}", 98), 0xffc5: ("\u{F70B}", 100),
        0xffc6: ("\u{F70C}", 101), 0xffc7: ("\u{F70D}", 109), 0xffc8: ("\u{F70E}", 103), 0xffc9: ("\u{F70F}", 111),
    ]
    private static let modifierKeysyms: Set<KeySym> = [0xffe1, 0xffe2, 0xffe3, 0xffe4, 0xffe9, 0xffea, 0xffeb, 0xffec, 0xffe5]

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
        if LinuxWindow.specialKeys[keysym] == nil && LinuxWindow.modifierKeysyms.contains(keysym) {
            let e = NSEvent(type: .flagsChanged, location: .zero, modifierFlags: modifierFlags(xkey.state), timestamp: seconds(xkey.time), windowNumber: windowNumber())
            owner?.platformWindowDispatch(e)
            return
        }
        var chars = chars0, plain = chars0
        var keyCode = UInt16(truncatingIfNeeded: keysym)
        if let special = LinuxWindow.specialKeys[keysym] {
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
        case UnmapNotify:
            isVisible = false
        case DestroyNotify:
            backend.unregister(self)
            if !destroying { destroying = true; owner?.platformWindowWillClose() }
            xid = 0
        case ClientMessage:
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
            guard b.button <= 3 else { return }
            let (type, bit, number): (NSEvent.EventType, Int, Int) = b.button == 1 ? (.leftMouseUp, 1, 0) : b.button == 3 ? (.rightMouseUp, 2, 1) : (.otherMouseUp, 4, 2)
            pressedButtons &= ~bit
            NSEvent._pressedMouseButtons = pressedButtons
            mouse(type, x: b.x, y: b.y, state: b.state, time: b.time, button: number, clickCount: clickCount)
        case MotionNotify:
            let m = event.xmotion
            if pressedButtons & 1 != 0 { mouse(.leftMouseDragged, x: m.x, y: m.y, state: m.state, time: m.time, button: 0) }
            else if pressedButtons & 2 != 0 { mouse(.rightMouseDragged, x: m.x, y: m.y, state: m.state, time: m.time, button: 1) }
            else if pressedButtons & 4 != 0 { mouse(.otherMouseDragged, x: m.x, y: m.y, state: m.state, time: m.time, button: 2) }
            else { mouse(.mouseMoved, x: m.x, y: m.y, state: m.state, time: m.time, button: 0, clickCount: 0) }
        case KeyPress:
            key(.keyDown, event.xkey)
        case KeyRelease:
            key(.keyUp, event.xkey)
        default:
            break
        }
    }
}
#endif
