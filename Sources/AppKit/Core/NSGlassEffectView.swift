// NSGlassEffectView (hand-written; seeded from the generated stub, see tools/apigen)
// Liquid Glass (ADR-0051): a lens over the content beneath it. With the Liquid Glass
// switch on, the view samples what the window drew under its rectangle at a quarter of
// the backing scale, blurs it through the backend's material pass, and draws the result
// tinted with the rim highlight and shadow macOS 26 gives glass; the sample is cached and
// taken again only when a view beneath dirties the glass rectangle. With the switch off
// the view draws the translucent tint an `NSVisualEffectView` within the window draws
// today, so an app written against the macOS 26 SDK keeps a sensible look on every port.
// The port's own types carry no `@available(macOS 26.0, *)`: the macOS host build runs on
// macOS 15, where a 26-gated type could never be exercised by the tests.

import Foundation
import QuartzCore

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsglasseffectview
@MainActor open class NSGlassEffectView: NSView {
    private var _contentView: NSView?
    private var _cornerRadius: CGFloat = 0
    private var _style: NSGlassEffectView.Style = .regular
    private var _tintColor: NSColor?
    /// A shape other than the rounded rectangle (SwiftUI's `glassEffect(in:)`), in bounds
    /// coordinates.
    public var _shapePath: ((NSRect) -> NSBezierPath)? { didSet { needsDisplay = true } }
    /// A glass view in a container's merge group draws no surface of its own.
    internal var _surfaceDrawnByContainer = false { didSet { if _surfaceDrawnByContainer != oldValue { needsDisplay = true } } }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsglasseffectview/contentview
    @MainActor open var contentView: NSView? {
        get { _contentView }
        set {
            guard newValue !== _contentView else { return }
            _contentView?.removeFromSuperview()
            _contentView = newValue
            if let v = newValue {
                v.frame = bounds
                v.autoresizingMask = [.width, .height]
                addSubview(v)
            }
            needsDisplay = true
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsglasseffectview/cornerradius
    @MainActor open var cornerRadius: CGFloat {
        get { _cornerRadius }
        set { _cornerRadius = max(0, newValue); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsglasseffectview/style
    @MainActor open var style: NSGlassEffectView.Style {
        get { _style }
        set { _style = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsglasseffectview/tintcolor
    @MainActor open var tintColor: NSColor? {
        get { _tintColor }
        set { _tintColor = newValue; needsDisplay = true }
    }

    open override var isOpaque: Bool { false }

    /// The glass outline in bounds coordinates: the custom shape, else the rounded
    /// rectangle (a radius of half the height makes a capsule).
    internal var _glassPath: NSBezierPath {
        if let p = _shapePath { return p(bounds) }
        let r = min(_cornerRadius, bounds.width / 2, bounds.height / 2)
        return r > 0 ? NSBezierPath(roundedRect: bounds, xRadius: r, yRadius: r) : NSBezierPath(rect: bounds)
    }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        _GlassRegistry.observeKeyChanges(of: self)
    }

    open override func draw(_ dirtyRect: NSRect) {
        guard !_surfaceDrawnByContainer else { return }
        if _LiquidGlass.isEnabled {
            var spec = _GlassSpec.lens(clear: _style == .clear, in: self)
            spec.tint = _tintColor
            _GlassRenderer.draw(spec, path: _glassPath, in: bounds, of: self)
        } else {
            // Today's look: the within-window tint of an effect view.
            let active = window?.isKeyWindow ?? true
            NSColor.windowBackgroundColor.withAlphaComponent(active ? 0.75 : 0.9).setFill()
            _glassPath.fill()
        }
    }
}

extension NSGlassEffectView {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsglasseffectview/style
        public enum Style: Int, Sendable, Equatable, Hashable {
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsglasseffectview/style/clear
        case clear = 0
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsglasseffectview/style/regular
        case regular = 1
    }
}

// MARK: - The glass pass

/// What a glass surface looks like: how far the content beneath is blurred, the veil
/// laid over it, and whether it is a lens (rim and shadow) or a flat material (a toolbar
/// band, a sidebar column).
@MainActor
internal struct _GlassSpec {
    /// Blur of the content beneath, in points.
    var blurRadius: CGFloat = 16
    /// The veil over the blurred content: the colour and how much of it.
    var veil: NSColor = .white
    var veilAlpha: CGFloat = 0.4
    /// A tint laid over the veil (`tintColor`, a prominent button's accent).
    var tint: NSColor?
    var tintAlpha: CGFloat = 0.55
    /// The rim: a highlight along the top edge and a shadow along the bottom, and the
    /// soft shadow a floating lens casts.
    var rim = true
    var shadow = true
    /// The edge's highlight strength (the inactive window halves it).
    var rimAlpha: CGFloat = 0.55

    /// Whether `view`'s window is key (a view outside any window counts as active).
    static func isActive(_ view: NSView) -> Bool { view.window?.isKeyWindow ?? true }

    /// A lens (`NSGlassEffectView`, a glass button): regular or clear, for the view's
    /// appearance and window state. Inactive windows show a flatter, more opaque glass
    /// with a fainter rim, as macOS does.
    static func lens(clear: Bool, in view: NSView) -> _GlassSpec {
        let dark = view.effectiveAppearance.isDark
        let active = isActive(view)
        var s = _GlassSpec()
        switch (clear, dark) {
        case (false, false): s.veil = .white; s.veilAlpha = active ? 0.42 : 0.6
        case (false, true): s.veil = NSColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1); s.veilAlpha = active ? 0.4 : 0.6
        case (true, false): s.veil = .white; s.veilAlpha = active ? 0.16 : 0.3
        case (true, true): s.veil = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1); s.veilAlpha = active ? 0.18 : 0.32
        }
        if clear { s.blurRadius = 10; s.tintAlpha = 0.35 }
        s.rimAlpha = (dark ? 0.3 : 0.55) * (active ? 1 : 0.5)
        if !active { s.shadow = false }
        return s
    }

    /// A flat material (no rim): the band behind a toolbar, a sidebar column, an effect
    /// view's material within the window.
    static func material(in view: NSView, alpha: CGFloat? = nil) -> _GlassSpec {
        let dark = view.effectiveAppearance.isDark
        let active = isActive(view)
        var s = _GlassSpec()
        s.rim = false; s.shadow = false
        s.blurRadius = 20
        s.veil = dark ? NSColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1) : .white
        s.veilAlpha = alpha ?? (active ? 0.5 : 0.68)
        return s
    }
}

/// Draws glass: the blurred sample of the content beneath, the veil and tint, the rim.
@MainActor
internal enum _GlassRenderer {
    /// The sample is taken at this fraction of the backing scale; the blur hides the
    /// resolution and the pass stays cheap.
    static let sampleScaleDivisor: CGFloat = 4

    /// Draws `spec` inside `path` (bounds coordinates of `view`), `rect` being the
    /// surface's bounds the sample covers.
    static func draw(_ spec: _GlassSpec, path: NSBezierPath, in rect: NSRect, of view: NSView) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let margin = spec.blurRadius
        if spec.shadow { drawShadow(path: path, in: ctx, dark: view.effectiveAppearance.isDark) }
        ctx.saveGState()
        path.addClip()
        if let sample = _GlassRegistry.sample(for: view).image(rect: rect.insetBy(dx: -margin, dy: -margin), blur: spec.blurRadius, view: view) {
            ctx.interpolationQuality = .default
            ctx.draw(sample.image, in: sample.rect)
        } else {
            // Nothing to sample (no window, no backing surface): the veil over the window colour.
            NSColor.windowBackgroundColor.setFill()
            ctx.fill(rect)
        }
        spec.veil.withAlphaComponent(spec.veilAlpha).setFill()
        ctx.fill(rect)
        if let tint = spec.tint {
            tint.withAlphaComponent(spec.tintAlpha * tint.alphaComponent).setFill()
            ctx.fill(rect)
        }
        ctx.restoreGState()
        if spec.rim { drawRim(path: path, in: rect, context: ctx, alpha: spec.rimAlpha, flipped: view.isFlipped) }
    }

    /// The rim: a one-point stroke inside the outline, white along the top fading to a
    /// faint dark line along the bottom, as the light catches a lens edge.
    private static func drawRim(path: NSBezierPath, in rect: NSRect, context ctx: CGContext, alpha: CGFloat, flipped: Bool) {
        let highlight = NSColor.white.withAlphaComponent(alpha)
        let mid = NSColor.white.withAlphaComponent(alpha * 0.35)
        let shade = NSColor.black.withAlphaComponent(min(0.18, alpha * 0.3))
        let stops: [(NSColor, CGFloat)] = flipped ? [(highlight, 0), (mid, 0.55), (shade, 1)] : [(shade, 0), (mid, 0.45), (highlight, 1)]
        let gradient = NSGradient(colorsAndLocations: stops[0], stops[1], stops[2])
        ctx.saveGState()
        // The ring between the outline and the outline inset by a point.
        let ring = NSBezierPath()
        ring.append(path)
        ring.append(inset(path, in: rect, by: 1))
        ring.windingRule = .evenOdd
        ring.addClip()
        gradient?.draw(in: rect, angle: 90)
        ctx.restoreGState()
    }

    /// The outline inset by `d` points: a rounded rectangle keeps its corner radius less `d`.
    private static func inset(_ path: NSBezierPath, in rect: NSRect, by d: CGFloat) -> NSBezierPath {
        let inner = rect.insetBy(dx: d, dy: d)
        guard inner.width > 0, inner.height > 0 else { return NSBezierPath() }
        var t = AffineTransform(translationByX: rect.midX, byY: rect.midY)
        t.scale(x: inner.width / rect.width, y: inner.height / rect.height)
        t.translate(x: -rect.midX, y: -rect.midY)
        let copy = path.copy() as! NSBezierPath
        copy.transform(using: t)
        return copy
    }

    /// The soft shadow under a floating lens: three rings of falling opacity outside the outline.
    private static func drawShadow(path: NSBezierPath, in ctx: CGContext, dark: Bool) {
        ctx.saveGState()
        let base: CGFloat = dark ? 0.35 : 0.14
        for (i, alpha) in [base * 0.5, base * 0.3, base * 0.15].enumerated() {
            let p = path.copy() as! NSBezierPath
            p.lineWidth = CGFloat(i + 1) * 1.5
            p.transform(using: AffineTransform(translationByX: 0, byY: -CGFloat(i) * 0.5 - 0.5))
            NSColor.black.withAlphaComponent(alpha).setStroke()
            p.stroke()
        }
        ctx.restoreGState()
    }
}

/// The cached sample of the content beneath one glass surface.
@MainActor
internal final class _GlassSample {
    weak var owner: NSView?
    private(set) var image: CGImage?
    /// The sampled rectangle in the owner's bounds and in the window.
    private(set) var rect = NSRect.null
    private(set) var windowRect = NSRect.null
    private var scale: CGFloat = 0
    private var blur: CGFloat = 0
    private var appearanceIsDark = false
    var dirty = true
    init(owner: NSView) { self.owner = owner }

    /// The blurred content beneath `rect` (bounds coordinates), sampled afresh when the
    /// cache is dirty or the surface moved, scaled or re-themed.
    func image(rect: NSRect, blur: CGFloat, view: NSView) -> (image: CGImage, rect: NSRect)? {
        let backing = view.window?.backingScaleFactor ?? 1
        let dark = view.effectiveAppearance.isDark
        let inWindow = view.convert(rect, to: nil)
        if dirty || image == nil || rect != self.rect || inWindow != windowRect || backing != scale || blur != self.blur || dark != appearanceIsDark {
            self.rect = rect; windowRect = inWindow; scale = backing; self.blur = blur; appearanceIsDark = dark
            dirty = false
            let sampleScale = max(0.25, backing / _GlassRenderer.sampleScaleDivisor)
            image = nil
            if let raw = _GlassRegistry.render(beneath: view, rect: rect, scale: sampleScale) {
                let radius = Int((blur * sampleScale).rounded())
                image = Platform.backend.material.blur(raw, radius: radius) ?? raw
            }
        }
        guard let image else { return nil }
        return (image, rect)
    }
}

/// Every live glass surface, so a view dirtying the content beneath one marks its sample
/// stale (and the surface for redisplay), and a window's key change redraws them all.
@MainActor
internal enum _GlassRegistry {
    private static var samples: [ObjectIdentifier: _GlassSample] = [:]
    private static var keyObserverInstalled = false

    static func sample(for view: NSView) -> _GlassSample {
        let id = ObjectIdentifier(view)
        if let s = samples[id], s.owner === view { return s }
        let s = _GlassSample(owner: view)
        samples[id] = s
        observeKeyChanges(of: view)
        return s
    }

    /// Called by the window for every invalidation: a view outside the glass surface (not
    /// the surface itself nor one of its subviews, whose pixels lie over the glass)
    /// dirtying its rectangle invalidates the sample.
    static func noteInvalidation(in window: NSWindow, from view: NSView?, rect: NSRect?) {
        guard !samples.isEmpty else { return }
        for (id, s) in samples {
            guard let owner = s.owner else { samples[id] = nil; continue }
            guard owner.window === window, !s.dirty else { continue }
            if let view, view === owner || view.isDescendant(of: owner) { continue }
            if let rect, !s.windowRect.isNull, !s.windowRect.intersects(rect) { continue }
            s.dirty = true
            owner.needsDisplay = true
        }
    }

    /// Glass follows the window's key state (a flatter veil, a fainter rim when inactive).
    static func observeKeyChanges(of view: NSView) {
        guard !keyObserverInstalled else { return }
        keyObserverInstalled = true
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { note in
                let window = note.object as? NSWindow
                MainActor.assumeIsolated {
                    for s in samples.values { if let o = s.owner, o.window === window { o.needsDisplay = true } }
                }
            }
        }
    }

    /// What the window drew beneath `view` in `rect` (bounds coordinates of `view`), at
    /// `scale` pixels per point, as premultiplied pixels: the window's background and
    /// every view drawn before `view` in the paint order, stopping at `view` itself.
    static func render(beneath view: NSView, rect: NSRect, scale: CGFloat) -> CGImage? {
        guard rect.width > 0, rect.height > 0, rect.width.isFinite, rect.height.isFinite else { return nil }
        guard let surface = Platform.backend.image.makeOffscreen(size: rect.size, scale: scale) else { return nil }
        let ctx = surface.context
        let previousStop = NSView._glassStop, previousStopped = CALayer._composeStopped, previousStopLayer = CALayer._composeStopLayer
        let previousCaching = NSView._cachingDisplay
        let previousContext = NSGraphicsContext.current
        let previousAppearance = NSAppearance.current
        NSView._glassStop = view; CALayer._composeStopped = false
        // A layer-backed glass view stops the layer compositor as well as the view paint.
        CALayer._composeStopLayer = view.layer ?? _GlassRegistry.placeholderStopLayer
        NSView._cachingDisplay = true
        defer {
            NSView._glassStop = previousStop; CALayer._composeStopped = previousStopped; CALayer._composeStopLayer = previousStopLayer
            NSView._cachingDisplay = previousCaching
            NSGraphicsContext.current = previousContext
            NSAppearance.current = previousAppearance
        }
        ctx.saveGState()
        if let window = view.window {
            // The surface's origin at the sampled rectangle's origin in window space.
            let inWindow = view.convert(rect, to: nil)
            ctx.translateBy(x: -inWindow.minX, y: -inWindow.minY)
            NSAppearance.current = window.effectiveAppearance
            window._drawBeneathGlass(into: ctx, rect: inWindow)
        } else if let root = view._glassRootView, root !== view {
            let inRoot = view.convert(rect, to: root)
            ctx.translateBy(x: -inRoot.minX, y: -inRoot.minY)
            if root.isFlipped { ctx.translateBy(x: 0, y: root.bounds.height); ctx.scaleBy(x: 1, y: -1) }
            root._displayHierarchy(in: ctx, dirtyRect: root.frame)
        } else {
            ctx.restoreGState()
            return nil
        }
        ctx.restoreGState()
        return surface.makeImage()
    }
}

extension _GlassRegistry {
    /// Stands in for the stop layer of a glass view without one, so the layer compositor
    /// still honours a stop the view paint has set.
    static let placeholderStopLayer = CALayer()
}

extension NSView {
    /// The view the glass pass is sampling beneath: `_displayHierarchy` stops when it
    /// reaches it (`CALayer._composeStopped` carries the state the layer compositor
    /// shares), so the sample holds only what lies under the glass.
    @MainActor internal static var _glassStop: NSView?

    @MainActor internal var _glassRootView: NSView? {
        var v: NSView = self
        while let s = v.superview { v = s }
        return v
    }
}

extension NSWindow {
    /// Draws the window as `platformWindowDraw` does (background, content, toolbar band,
    /// accessories, in that order) until the paint reaches `NSView._glassStop`.
    internal func _drawBeneathGlass(into ctx: CGContext, rect: NSRect) {
        if _isOpaque {
            ctx.setFillColor(_backgroundColor.cgColor)
            ctx.fill(rect)
        }
        _contentView?._displayHierarchy(in: ctx, dirtyRect: rect)
        if CALayer._composeStopped { return }
        if let t = _toolbarView, !t.isHidden { t._displayHierarchy(in: ctx, dirtyRect: rect) }
        if CALayer._composeStopped { return }
        if let a = _accessoryHost, !a.isHidden { a._displayHierarchy(in: ctx, dirtyRect: rect) }
    }
}
