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
    // The package's own ImageIO (ADR-0009) is importable on Windows and Linux too, but AppKit
    // keeps its platform image backends there; HostImageBackend is Apple's ImageIO on macOS.
    let image: any PlatformImageBackend = Platform.imageCodec

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
    var systemAppearanceIsDark = false

    let systemPasteboard: any PlatformPasteboard = HostPasteboard()

    /// The host has no native dialog: the panels draw themselves. Tests may install one
    /// (`HostFileDialog` records the options and answers a canned result).
    var fileDialogOverride: (any PlatformFileDialog)? = nil
    var fileDialog: (any PlatformFileDialog)? { fileDialogOverride }

    /// The in-process status area (StatusItem.swift): tests click its items.
    let hostStatusItems = HostStatusItems()
    var statusItems: (any PlatformStatusItemHost)? { hostStatusItems }
    /// Printing (Printing.swift): PDF through the platform writer, jobs kept for tests.
    let hostPrinting = HostPrintBackend()
    var printing: (any PlatformPrintBackend)? { hostPrinting }

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
    /// The window's own scale once a test moved it to a "monitor" of another scale;
    /// otherwise the host display's.
    private var scaleOverride: CGFloat?
    var backingScaleFactor: CGFloat { scaleOverride ?? backend.displays[0].backingScaleFactor }
    /// Test hook: the window moved to a monitor of another scale, as WM_DPICHANGED or a
    /// `wl_surface.enter` would report. The frame keeps its point size; the owner
    /// re-rasterises for the new pixel size.
    func setBackingScaleFactor(_ scale: CGFloat) {
        guard scale != backingScaleFactor else { return }
        scaleOverride = scale
        owner?.platformWindowDidChangeBackingScaleFactor(scale)
    }
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
    /// Test hook: the host window leaves its title bar to the package, as a Wayland
    /// compositor without server-side decorations does (ClientSideDecoration.swift).
    var clientSideTitleBar = false
    var hasClientSideTitleBar: Bool { clientSideTitleBar }
    private(set) var paintCount = 0
    /// Accessibility changes the core reported (ADR-0013), oldest first.
    private(set) var accessibilityChanges: [PlatformAccessibilityChange] = []
    func accessibilityDidChange(_ change: PlatformAccessibilityChange) { accessibilityChanges.append(change) }
    func clearAccessibilityChanges() { accessibilityChanges.removeAll() }

    /// Test hook: when set, the window hosts layer scenes and composites them itself
    /// (a reference for the DirectComposition implementation).
    var layerHostingEnabled = false
    private(set) var hostedScene: PlatformLayerScene?
    private(set) var sceneCommitCount = 0
    /// Rasterised node content, keyed by node id: re-drawn only when the version changes.
    #if canImport(CoreGraphics)
    private var rasters: [Int: (version: Int, scale: CGFloat, size: CGSize, image: CGImage)] = [:]
    #endif
    private(set) var rasterCount = 0

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

    /// The window this one is attached to as a sheet (ADR-0019); a sheet has no title bar.
    private(set) weak var sheetParent: HostWindow?
    func attachSheet(to parent: PlatformWindow?) { sheetParent = parent as? HostWindow }

    func frameRect(forContentRect contentRect: NSRect) -> NSRect { sheetParent != nil ? contentRect : backend.frameRect(forContentRect: contentRect, styleMask: styleMask) }
    func contentRect(forFrameRect frameRect: NSRect) -> NSRect { sheetParent != nil ? frameRect : backend.contentRect(forFrameRect: frameRect, styleMask: styleMask) }

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
        if let scene = hostedScene { composite(scene, into: ctx, height: content.height) }
        lastImage = ctx.makeImage()
        #else
        _ = rect
        #endif
    }

    func captureContent() -> CGImage? { lastImage }

    func hostLayerScene(_ scene: PlatformLayerScene?) -> Bool {
        guard layerHostingEnabled else { return false }
        hostedScene = scene
        sceneCommitCount += 1
        #if canImport(CoreGraphics)
        if let scene {
            let live = Set(scene.nodes.map(\.id))
            rasters = rasters.filter { live.contains($0.key) }
        } else {
            rasters.removeAll()
        }
        #endif
        setNeedsDisplay(nil)
        return true
    }

    #if canImport(CoreGraphics)
    /// Draws the scene over the window content: each node's content is rasterised once per
    /// version, then placed by its transform, exactly as a visual tree would be.
    private func composite(_ scene: PlatformLayerScene, into ctx: CGContext, height: CGFloat) {
        var children: [Int: [Int]] = [:]
        var roots: [Int] = []
        for (i, n) in scene.nodes.enumerated() {
            if let p = n.parent { children[p, default: []].append(i) } else { roots.append(i) }
        }
        func raster(_ node: _CALayerSceneNode) -> CGImage? {
            guard let content = node.content else { return nil }
            if let r = rasters[node.id], r.version == content.version, r.scale == scene.scale, r.size == node.size { return r.image }
            let w = max(1, Int((node.size.width * scene.scale).rounded(.up))), h = max(1, Int((node.size.height * scene.scale).rounded(.up)))
            guard let bc = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
            bc.scaleBy(x: scene.scale, y: scene.scale)
            content.draw(bc)
            guard let image = bc.makeImage() else { return nil }
            rasters[node.id] = (content.version, scene.scale, node.size, image)
            rasterCount += 1
            return image
        }
        /// The rect (node-local, y-down) the node's subtree reaches: its own rect plus
        /// its children's, through their transforms.
        func subtreeExtent(_ i: Int) -> CGRect {
            let n = scene.nodes[i]
            var r = CGRect(origin: .zero, size: n.size)
            if n.clipsToBounds { return r }
            for c in children[i] ?? [] {
                let child = scene.nodes[c]
                let inner = subtreeExtent(c)
                if let t3 = child.transform3D, let corners = _CAHomography(t3).corners(of: inner) {
                    let xs = corners.map(\.x), ys = corners.map(\.y)
                    r = r.union(CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!))
                } else {
                    r = r.union(inner.applying(child.transform))
                }
            }
            return r
        }
        /// Clip, content and children, in the node's local space.
        func drawLocal(_ i: Int, alpha a: CGFloat, into ctx: CGContext) {
            let n = scene.nodes[i]
            let rect = CGRect(origin: .zero, size: n.size)
            if n.clipsToBounds {
                if n.cornerRadius > 0 {
                    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: min(n.cornerRadius, rect.width / 2), cornerHeight: min(n.cornerRadius, rect.height / 2), transform: nil))
                } else {
                    ctx.addRect(rect)
                }
                ctx.clip()
            }
            if let image = raster(n) {
                ctx.saveGState()
                ctx.setAlpha(a)
                ctx.translateBy(x: 0, y: n.size.height)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(image, in: rect)
                ctx.restoreGState()
            }
            for c in children[i] ?? [] { draw(c, alpha: a, into: ctx) }
        }
        func draw(_ i: Int, alpha: CGFloat, into ctx: CGContext) {
            let n = scene.nodes[i]
            let a = alpha * CGFloat(n.opacity)
            // A 3D node: its z = 0 plane map. Affine (a rotation without perspective) is
            // placed exactly; projective is flattened to pixels and drawn through the
            // projection as a mesh, as the software compositor does (CAProjective.swift).
            // DirectComposition applies the 4x4 to the visual instead.
            let plane = n.transform3D.map { _CAHomography($0) }
            if let plane, !plane.isAffine {
                let extent = subtreeExtent(i)
                let s = scene.scale * plane.stretch(of: CGRect(origin: .zero, size: n.size))
                guard let image = _CAPixels.render(extent: extent, scale: (s, s), yDown: true, draw: { off in
                    drawLocal(i, alpha: 1, into: off)
                }) else { return }
                ctx.saveGState()
                _CAProjective.draw(image, extent: extent, yDown: true, through: plane, into: ctx, alpha: a)
                ctx.restoreGState()
                return
            }
            ctx.saveGState()
            ctx.concatenate(plane?.affine ?? n.transform)        // now in the node's local y-down space
            drawLocal(i, alpha: a, into: ctx)
            ctx.restoreGState()
        }
        ctx.saveGState()
        // Window content y-up → the scene's y-down space.
        ctx.translateBy(x: 0, y: height)
        ctx.scaleBy(x: 1, y: -1)
        for r in roots { draw(r, alpha: 1, into: ctx) }
        ctx.restoreGState()
    }
    #endif

    /// Test hook: deliver an event as the OS would.
    func inject(_ event: NSEvent) {
        owner?.platformWindowDispatch(event)
    }

    /// Test hook: the input-method target, as a backend would fetch it.
    func textInput() -> PlatformTextInput? { owner?.platformWindowTextInput() }

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
    nonisolated init() {}
    nonisolated func decode(_ data: Data) -> CGImage? { nil }
    nonisolated func encode(_ image: CGImage, format: String, quality: Double) -> Data? { nil }
    func makeOffscreen(size: CGSize, scale: CGFloat) -> PlatformOffscreenSurface? { nil }
}

@MainActor
final class HostPasteboard: PlatformPasteboard {
    private var entries: [PlatformPasteboardEntry] = []
    private(set) var changeCount = 0
    func write(_ entries: [PlatformPasteboardEntry]) { self.entries = entries; changeCount += 1 }
    func read() -> [PlatformPasteboardEntry] { entries }
}

/// A stand-in native dialog for tests: records what the panel asked for and answers with
/// `result` (nil cancels).
@MainActor
final class HostFileDialog: PlatformFileDialog {
    var result: [URL]?
    private(set) var lastOptions: PlatformFileDialogOptions?
    private(set) var runCount = 0
    init(result: [URL]?) { self.result = result }
    func run(_ options: PlatformFileDialogOptions, parent: PlatformWindow?) -> [URL]? {
        lastOptions = options
        runCount += 1
        return result
    }
}

/// The host backend's status area: a registry of the items with what they show, and a
/// `click` hook that delivers what a user would do in a real notification area.
@MainActor
final class HostStatusItems: PlatformStatusItemHost {
    private(set) var items: [HostStatusItem] = []
    var thickness: CGFloat { 22 }
    func makeStatusItem(owner: PlatformStatusItemOwner) -> PlatformStatusItem {
        let item = HostStatusItem(owner: owner, host: self)
        items.append(item)
        return item
    }
    fileprivate func forget(_ item: HostStatusItem) { items.removeAll { $0 === item } }
    /// The items a user would see (visible, not removed).
    var visibleItems: [HostStatusItem] { items.filter { $0.isVisible } }
}

@MainActor
final class HostStatusItem: PlatformStatusItem {
    private weak var owner: PlatformStatusItemOwner?
    private unowned let host: HostStatusItems
    var title = ""
    var toolTip: String?
    var isVisible = true
    var appearsDisabled = false
    private(set) var image: CGImage?
    private(set) var imageScale: CGFloat = 1
    private(set) var removed = false

    init(owner: PlatformStatusItemOwner, host: HostStatusItems) {
        self.owner = owner
        self.host = host
    }
    func setImage(_ image: CGImage?, scale: CGFloat) { self.image = image; imageScale = scale }
    func remove() { removed = true; isVisible = false; host.forget(self) }
    /// Test hook: the user clicked the item at `screenPoint` (AppKit screen coordinates).
    func click(_ click: PlatformStatusItemClick, at screenPoint: NSPoint = NSPoint(x: 1800, y: 1070)) {
        guard isVisible, !removed else { return }
        owner?.platformStatusItemClicked(click, at: screenPoint)
    }
}
