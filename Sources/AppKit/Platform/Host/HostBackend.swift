// Headless backend used on macOS and Linux hosts for type-checking and unit tests.
// Windows are plain objects; drawing goes into an offscreen bitmap when CoreGraphics is
// available so tests can inspect pixels.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

@MainActor
final class HostBackend: PlatformBackend {
    var displays: [PlatformDisplay] = [
        PlatformDisplay(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
                        visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1055),
                        backingScaleFactor: 2, localizedName: "Host Display", isMain: true)
    ]
    private var running = false
    private var pending: [@MainActor () -> Void] = []
    var mouseLocation: NSPoint = .zero
    var beepCount = 0
    #if canImport(CoreText) && canImport(CoreGraphics)
    let text: any PlatformTextBackend = HostTextBackend()
    #else
    let text: any PlatformTextBackend = NoTextBackend()
    #endif
    #if canImport(ImageIO) && canImport(CoreGraphics)
    let image: any PlatformImageBackend = HostImageBackend()
    #else
    let image: any PlatformImageBackend = NoImageBackend()
    #endif

    func makeWindow(owner: PlatformWindowOwner, contentRect: NSRect, styleMask: NSWindow.StyleMask) -> PlatformWindow {
        HostWindow(owner: owner, contentRect: contentRect, styleMask: styleMask, backend: self)
    }

    func run() {
        running = true
        while running {
            drain()
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
    }

    func stop() { running = false }

    func post(_ block: @escaping @MainActor () -> Void) {
        pending.append(block)
    }

    /// Frames come from a one-shot timer on the main run loop (which `run()` services).
    /// Tests drive `CARuntime.tick()` directly instead.
    func scheduleFrame(_ callback: @escaping @MainActor () -> Void) {
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: false) { _ in MainActor.assumeIsolated { callback() } }
        RunLoop.main.add(t, forMode: .default)
    }

    /// Runs queued blocks. Tests call this instead of `run()`.
    func drain() {
        while !pending.isEmpty {
            let blocks = pending
            pending.removeAll()
            for b in blocks { b() }
        }
    }

    func beep() { beepCount += 1 }

    let systemPasteboard: any PlatformPasteboard = HostPasteboard()

    /// Test hook: what the next file dialog "chooses" (nil = cancel).
    var nextFileDialogResult: [URL]? = nil
    private(set) var lastFileDialogOptions: PlatformFileDialogOptions? = nil
    func runFileDialog(_ options: PlatformFileDialogOptions, parent: PlatformWindow?) -> [URL]? {
        lastFileDialogOptions = options
        return nextFileDialogResult
    }

    func runModal(for window: PlatformWindow?, until stop: @escaping @MainActor () -> Bool) {
        // Tests end modal sessions from inside the loop via posted blocks.
        var guardCount = 0
        while !stop() && guardCount < 10_000 {
            drain()
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
            guardCount += 1
        }
    }

    private(set) var cursor: PlatformCursor = .arrow
    private(set) var cursorHidden = false
    func setCursor(_ cursor: PlatformCursor) { self.cursor = cursor }
    func setCursorHidden(_ hidden: Bool) { cursorHidden = hidden }

    private(set) var mainMenu: PlatformMenu?
    private weak var menuHost: PlatformMenuHost?
    func setMainMenu(_ menu: PlatformMenu?, host: PlatformMenuHost?) {
        mainMenu = menu
        menuHost = host
    }
    /// Test hook: simulate the user choosing a menu item.
    func chooseMenuItem(_ id: Int) { menuHost?.platformMenuItemSelected(id) }
    /// Test hook: simulate a menu opening and return what would be shown.
    func openMenu(_ id: Int) -> PlatformMenu? { menuHost?.platformMenuWillOpen(id) }

    func frameRect(forContentRect contentRect: NSRect, styleMask: NSWindow.StyleMask) -> NSRect {
        guard styleMask.contains(.titled) else { return contentRect }
        return NSRect(x: contentRect.minX, y: contentRect.minY, width: contentRect.width, height: contentRect.height + HostWindow.titleBarHeight)
    }

    func contentRect(forFrameRect frameRect: NSRect, styleMask: NSWindow.StyleMask) -> NSRect {
        guard styleMask.contains(.titled) else { return frameRect }
        return NSRect(x: frameRect.minX, y: frameRect.minY, width: frameRect.width, height: max(0, frameRect.height - HostWindow.titleBarHeight))
    }
}

@MainActor
final class HostWindow: PlatformWindow {
    private weak var owner: PlatformWindowOwner?
    private unowned let backend: HostBackend
    var title: String = ""
    var styleMask: NSWindow.StyleMask
    var backingScaleFactor: CGFloat { backend.displays[0].backingScaleFactor }
    private(set) var isVisible = false
    private(set) var isKey = false
    var minSize = NSSize(width: 0, height: 0)
    var maxSize = NSSize(width: 100_000, height: 100_000)
    private var dirty: NSRect? = nil
    private var _frame: NSRect
    /// Title bar height used by this fake window manager.
    static let titleBarHeight: CGFloat = 28

    /// Last rendered content, for tests. Premultiplied BGRA, `backingScaleFactor` scaled.
    #if canImport(CoreGraphics)
    private(set) var lastImage: CGImage?
    var chrome = PlatformWindowChrome()
    private var surface: CGContext?     // retained between paints, like the Direct2D target
    #endif
    private(set) var paintCount = 0

    init(owner: PlatformWindowOwner, contentRect: NSRect, styleMask: NSWindow.StyleMask, backend: HostBackend) {
        self.owner = owner
        self.styleMask = styleMask
        self.backend = backend
        self._frame = .zero
        self._frame = frameRect(forContentRect: contentRect)
    }

    var frame: NSRect {
        get { _frame }
        set {
            var f = newValue
            f.size.width = min(max(f.size.width, minSize.width), maxSize.width)
            f.size.height = min(max(f.size.height, minSize.height), maxSize.height)
            guard f != _frame else { return }
            _frame = f
            owner?.platformWindowDidChangeFrame(f)
        }
    }

    func frameRect(forContentRect contentRect: NSRect) -> NSRect { backend.frameRect(forContentRect: contentRect, styleMask: styleMask) }
    func contentRect(forFrameRect frameRect: NSRect) -> NSRect { backend.contentRect(forFrameRect: frameRect, styleMask: styleMask) }

    func show() {
        isVisible = true
        setNeedsDisplay(nil)
    }

    func hide() {
        isVisible = false
        if isKey { isKey = false; owner?.platformWindowDidResignKey() }
    }

    func makeKey() {
        guard !isKey else { return }
        isKey = true
        owner?.platformWindowDidBecomeKey()
    }

    func orderBack() {}

    func close() {
        if isKey { isKey = false; owner?.platformWindowDidResignKey() }
        isVisible = false
        owner?.platformWindowWillClose()
    }

    func setNeedsDisplay(_ rect: NSRect?) {
        let content = contentRect(forFrameRect: _frame)
        let bounds = NSRect(origin: .zero, size: content.size)
        if let r = rect { dirty = (dirty ?? NSRect.null).union(r).intersection(bounds) } else { dirty = bounds }
    }

    func displayIfNeeded() {
        if dirty != nil { display() }
    }

    func display() {
        let content = contentRect(forFrameRect: _frame)
        let rect = dirty ?? NSRect(origin: .zero, size: content.size)
        dirty = nil
        paintCount += 1
        #if canImport(CoreGraphics)
        let scale = backingScaleFactor
        let w = max(1, Int(content.width * scale)), h = max(1, Int(content.height * scale))
        if surface == nil || surface!.width != w || surface!.height != h {
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
            // CGContext bitmaps are already bottom-left origin; only the scale is needed.
            ctx.scaleBy(x: scale, y: scale)
            surface = ctx
        }
        guard let ctx = surface else { return }
        ctx.saveGState()
        owner?.platformWindowDraw(into: ctx, dirtyRect: rect)
        ctx.restoreGState()
        lastImage = ctx.makeImage()
        #else
        _ = rect
        #endif
    }

    /// Test hook: deliver an event as the OS would.
    func inject(_ event: NSEvent) {
        owner?.platformWindowDispatch(event)
    }

    /// Test hook: simulate the user closing the window.
    func userRequestedClose() {
        if owner?.platformWindowShouldClose() == true { close() }
    }
}

/// Used on hosts without CoreText (Linux dev builds): text has no size and draws nothing.
@MainActor
final class NoTextBackend: PlatformTextBackend {
    func makeFont(family: String?, size: CGFloat, weight: CGFloat, italic: Bool, monospaced: Bool) -> PlatformFontHandle? { nil }
    func measure(_ text: String, font: PlatformFontHandle, maxWidth: CGFloat?) -> CGSize { .zero }
    func draw(_ text: String, font: PlatformFontHandle, color: CGColor, topLeft: CGPoint, maxWidth: CGFloat?, flipped: Bool, in context: CGContext) {}
}

@MainActor
final class NoImageBackend: PlatformImageBackend {
    func decode(_ data: Data) -> CGImage? { nil }
    func encode(_ image: CGImage, format: String, quality: Double) -> Data? { nil }
    func makeOffscreen(size: CGSize, scale: CGFloat) -> PlatformOffscreenSurface? { nil }
}

@MainActor
final class HostPasteboard: PlatformPasteboard {
    private var entries: [PlatformPasteboardEntry] = []
    private(set) var changeCount = 0
    func write(_ entries: [PlatformPasteboardEntry]) { self.entries = entries; changeCount += 1 }
    func read() -> [PlatformPasteboardEntry] { entries }
}
