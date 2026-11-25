// NSGlassEffectView (hand-written; seeded from the generated stub, see tools/apigen)
// Liquid Glass (ADR-0052): a lens over the content beneath it. With the Liquid Glass
// switch on, the view samples what the window drew under its rectangle at a quarter of
// the backing scale, the backend's material pass blurs and saturates it, and the lens
// stage shades the shape at the backing scale: the backdrop bent toward the rim, the veil
// (light or dark by the backdrop's own luminance), the tint, the rim line and specular
// sheen under a fixed light, the soft shadow. The sample is cached and taken again only
// when a view beneath dirties the glass rectangle. With the switch off the view draws the
// translucent tint an `NSVisualEffectView` within the window draws today, so an app
// written against the macOS 26 SDK keeps a sensible look on every port. The port's own
// types carry no `@available(macOS 26.0, *)`: the macOS host build runs on macOS 15, where
// a 26-gated type could never be exercised by the tests.

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
    /// SwiftUI's `Glass.interactive`: the surface brightens under the pointer and grows a
    /// little while pressed.
    public var _isInteractive = false {
        didSet {
            guard _isInteractive != oldValue else { return }
            if !_isInteractive { _isHovered = false; _isPressed = false }
            needsDisplay = true
            window?._trackingAreasDidChange()
        }
    }
    /// SwiftUI's `glassEffectUnion`: surfaces in one container sharing an identifier
    /// always draw as one shape.
    public var _unionID: AnyHashable? { didSet { _enclosingGlassContainer?.needsLayout = true } }
    /// A glass view in a container's merge group draws no surface of its own.
    internal var _surfaceDrawnByContainer = false { didSet { if _surfaceDrawnByContainer != oldValue { needsDisplay = true } } }
    internal var _isHovered = false { didSet { if _isHovered != oldValue { needsDisplay = true } } }
    internal var _isPressed = false { didSet { if _isPressed != oldValue { needsDisplay = true } } }
    private var _hoverArea: NSTrackingArea?

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

    /// The rectangle the surface fills: the bounds, less a point on every side for an
    /// interactive surface at rest (it grows back to the bounds while pressed).
    internal var _surfaceRect: NSRect {
        _isInteractive && !_isPressed ? bounds.insetBy(dx: 1, dy: 1) : bounds
    }

    /// The glass outline in bounds coordinates: the custom shape, else the rounded
    /// rectangle (a radius of half the height makes a capsule).
    internal var _glassPath: NSBezierPath {
        let r = _surfaceRect
        if let p = _shapePath { return p(r) }
        let radius = _effectiveCornerRadius(in: r)
        return radius > 0 ? NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius) : NSBezierPath(rect: r)
    }
    internal func _effectiveCornerRadius(in r: NSRect) -> CGFloat { min(_cornerRadius, r.width / 2, r.height / 2) }

    /// The container whose merge groups this view may join.
    internal var _enclosingGlassContainer: NSGlassEffectContainerView? {
        var v = superview
        while let s = v { if let c = s as? NSGlassEffectContainerView { return c }; v = s.superview }
        return nil
    }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        _GlassRegistry.observeKeyChanges(of: self)
    }
    open override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        _enclosingGlassContainer?.needsLayout = true
    }
    open override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        _enclosingGlassContainer?.needsLayout = true
    }
    open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        _enclosingGlassContainer?.needsLayout = true
    }

    open override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = _hoverArea { removeTrackingArea(a); _hoverArea = nil }
        guard _isInteractive else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        _hoverArea = area
    }
    open override func mouseEntered(with event: NSEvent) {
        if _isInteractive { _isHovered = true } else { super.mouseEntered(with: event) }
    }
    open override func mouseExited(with event: NSEvent) {
        if _isInteractive { _isHovered = false; _isPressed = false } else { super.mouseExited(with: event) }
    }
    open override func mouseDown(with event: NSEvent) {
        if _isInteractive { _isPressed = true } else { super.mouseDown(with: event) }
    }
    open override func mouseUp(with event: NSEvent) {
        if _isInteractive { _isPressed = false } else { super.mouseUp(with: event) }
    }

    open override func draw(_ dirtyRect: NSRect) {
        guard !_surfaceDrawnByContainer else { return }
        if _LiquidGlass.isEnabled {
            var spec = _GlassSpec.lens(clear: _style == .clear, in: self)
            spec.tint = _tintColor
            if _isInteractive { spec.brighten = _isPressed ? 0.2 : (_isHovered ? 0.1 : 0) }
            let r = _surfaceRect
            let outline: _GlassOutline = _shapePath == nil ? .roundedRect(_effectiveCornerRadius(in: r)) : .path
            _GlassRenderer.draw(spec, path: _glassPath, outline: outline, in: r, of: self)
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

/// The outline handed to the lens stage: a rounded rectangle (analytic distance field) or
/// any path (rasterised to a coverage mask).
internal enum _GlassOutline {
    case roundedRect(CGFloat)
    case path
}

/// What a glass surface looks like: how far the content beneath is blurred, the veil
/// laid over it, and whether it is a lens (bevel, rim and shadow) or a flat material (a
/// toolbar band, a sidebar column).
@MainActor
internal struct _GlassSpec {
    /// The light or dark variant, or whichever the backdrop's luminance calls for.
    enum Variant { case light, dark, adaptive }
    var variant: Variant = .adaptive
    /// Blur of the content beneath, in points, and the saturation lift of the blurred backdrop.
    var blurRadius: CGFloat = 16
    var saturation: CGFloat = 1.3
    /// The veil over the blurred content in each variant: how much of white, how much of
    /// the dark grey.
    var lightVeilAlpha: CGFloat = 0.42
    var darkVeilAlpha: CGFloat = 0.4
    var darkVeil = NSColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)
    /// A tint laid over the veil (`tintColor`, a prominent button's accent).
    var tint: NSColor?
    var tintAlpha: CGFloat = 0.55
    /// The lens: the bevel bending the backdrop at the edge, the rim line, the sheen, the
    /// soft shadow a floating lens casts. A flat material has none of them.
    var lens = true
    var edgeWidth: CGFloat = 6
    var refraction: CGFloat = 3
    var rimAlpha: CGFloat = 0.55
    var specular: CGFloat = 0.5
    var shadow = true
    /// A lift toward white (interactive hover and press).
    var brighten: CGFloat = 0
    /// The scroll-edge effect: when nothing but the window background lies beneath the
    /// surface, the content just beyond this window edge is mirrored into the sample so
    /// the material carries the colours of the content it borders (a toolbar band over a
    /// document that does not run under it). Only `.minY` (the strip below) is drawn.
    var extendsFrom: NSRectEdge?
    var active = true

    /// Whether `view`'s window is key (a view outside any window counts as active).
    static func isActive(_ view: NSView) -> Bool { view.window?.isKeyWindow ?? true }

    /// A lens (`NSGlassEffectView`, a glass button): regular or clear, for the view's
    /// appearance and window state. Dark appearance forces the dark variant; light
    /// appearance lets the backdrop decide. Inactive windows show a flatter, more opaque
    /// glass with a fainter rim and no shadow, as macOS does.
    static func lens(clear: Bool, in view: NSView) -> _GlassSpec {
        let dark = view.effectiveAppearance.isDark
        let active = isActive(view)
        var s = _GlassSpec()
        s.active = active
        s.variant = dark ? .dark : .adaptive
        if clear {
            s.lightVeilAlpha = active ? 0.16 : 0.3
            s.darkVeilAlpha = active ? 0.18 : 0.32
            s.darkVeil = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)
            s.blurRadius = 10; s.tintAlpha = 0.35; s.saturation = 1.15
        } else {
            s.lightVeilAlpha = active ? 0.42 : 0.6
            s.darkVeilAlpha = active ? 0.4 : 0.6
        }
        if !active { s.rimAlpha *= 0.5; s.specular *= 0.4; s.shadow = false }
        return s
    }

    /// A flat material (no bevel): the band behind a toolbar, a sidebar column, an effect
    /// view's material within the window.
    static func material(in view: NSView, alpha: CGFloat? = nil) -> _GlassSpec {
        let dark = view.effectiveAppearance.isDark
        let active = isActive(view)
        var s = _GlassSpec()
        s.active = active
        s.variant = dark ? .dark : .adaptive
        s.lens = false; s.edgeWidth = 0; s.refraction = 0; s.rimAlpha = 0; s.specular = 0; s.shadow = false
        s.blurRadius = 24
        s.saturation = 1.35
        s.darkVeil = NSColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1)
        s.lightVeilAlpha = alpha ?? (active ? 0.5 : 0.68)
        s.darkVeilAlpha = alpha ?? (active ? 0.5 : 0.68)
        return s
    }

    /// The variant for a backdrop of mean luminance `luminance` (the regular glass turns
    /// dark over dark content, as Apple's does).
    func resolvesDark(luminance: CGFloat?) -> Bool {
        switch variant {
        case .light: return false
        case .dark: return true
        case .adaptive: return (luminance ?? 1) < 0.35
        }
    }
}

/// Draws glass: the blurred sample of the content beneath through the lens stage, the
/// soft shadow around a lens.
@MainActor
internal enum _GlassRenderer {
    /// The sample is taken at this fraction of the backing scale (a quarter for a lens,
    /// an eighth for a material whose wider blur hides the resolution): the blur hides the
    /// resolution and the pass stays cheap.
    static let sampleScaleDivisor: CGFloat = 4
    static let materialSampleScaleDivisor: CGFloat = 8

    /// Draws `spec` inside `path` (bounds coordinates of `view`), `rect` being the
    /// surface's rectangle the sample covers; `slot` distinguishes several surfaces one
    /// view draws (a container's merge groups).
    static func draw(_ spec: _GlassSpec, path: NSBezierPath, outline: _GlassOutline, in rect: NSRect, of view: NSView, slot: Int = 0) {
        guard let ctx = NSGraphicsContext.current?.cgContext, rect.width > 0, rect.height > 0 else { return }
        let margin = spec.blurRadius + spec.refraction
        if spec.shadow { drawShadow(path: path, in: ctx, dark: view.effectiveAppearance.isDark) }
        ctx.saveGState()
        path.addClip()
        let sample = _GlassRegistry.sample(for: view, slot: slot)
        // The GPU stage (ADR-0052 stage 2) takes every rounded-rectangle lens and every flat
        // material; a lens with any other outline keeps the software pass's coverage mask.
        if let program = _GlassGPU.program, !(spec.lens && isPath(outline)) {
            if drawWithProgram(program, spec: spec, outline: outline, in: rect, margin: margin, sample: sample, view: view, context: ctx) {
                ctx.restoreGState()
                return
            }
            _GlassGPU.disable("\(program.name) could not draw a \(Int(rect.width))x\(Int(rect.height)) pt surface")
        }
        if let backdrop = sample.backdrop(rect: rect.insetBy(dx: -margin, dy: -margin), spec: spec, view: view) {
            let scale = view.window?.backingScaleFactor ?? 1
            let dark = spec.resolvesDark(luminance: backdrop.luminance)
            var p = PlatformGlassParameters(width: max(1, Int((rect.width * scale).rounded(.up))), height: max(1, Int((rect.height * scale).rounded(.up))))
            if dark {
                let c = spec.darkVeil.usingColorSpace(.sRGB) ?? spec.darkVeil
                p.veil = .init(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)
                p.veilAlpha = spec.darkVeilAlpha
                p.rimAlpha = spec.rimAlpha * 0.55
                p.specular = spec.specular * 0.7
            } else {
                p.veil = .white
                p.veilAlpha = spec.lightVeilAlpha
                p.rimAlpha = spec.rimAlpha
                p.specular = spec.specular
            }
            if let tint = spec.tint, let c = tint.usingColorSpace(.sRGB) {
                p.tint = .init(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: c.alphaComponent)
                p.tintAlpha = spec.tintAlpha
            }
            p.edgeWidth = spec.edgeWidth * scale
            p.refraction = spec.refraction * scale
            p.rimWidth = spec.lens ? max(1, 1 * scale) : 0
            p.brighten = spec.brighten
            // The backdrop image in output pixels (the output's top row is the surface's
            // visual top): the margin lies outside the output, and a shared frame's crop
            // sits on its pixel grid, so the offsets come from the window rectangles.
            let backdropRect: CGRect
            if let imageRect = backdrop.imageRect {
                let inWindow = view.convert(rect, to: nil)
                backdropRect = CGRect(x: (imageRect.minX - inWindow.minX) * scale, y: (inWindow.maxY - imageRect.maxY) * scale, width: imageRect.width * scale, height: imageRect.height * scale)
            } else {
                backdropRect = CGRect(x: -margin * scale, y: -margin * scale, width: (rect.width + 2 * margin) * scale, height: (rect.height + 2 * margin) * scale)
            }
            let shape = spec.lens ? outlineShape(outline, path: path, in: rect, pixels: (p.width, p.height), scale: scale, flipped: view.isFlipped) : nil
            let shadeKey = spec.lens ? shapeKey(outline, path: path, parameters: p, flipped: view.isFlipped) : 0
            if spec.lens, let shape, let shaded = sample.shaded(key: shadeKey, make: { Platform.backend.material.shade(backdrop.image, in: backdropRect, shape: shape, parameters: p) }) {
                drawImage(shaded, in: rect, context: ctx, flipped: view.isFlipped)
            } else {
                // A flat material (no bevel, rim or sheen), or a lens whose shade stage
                // failed: the blurred backdrop drawn up to size by the graphics backend,
                // the veil, tint and lift as fills over it. No pixel loop runs, so a toolbar
                // band costs its blur alone.
                let imageRect = backdrop.imageRect.map { view.convert($0, from: nil) } ?? rect.insetBy(dx: -margin, dy: -margin)
                drawImage(backdrop.image, in: imageRect, context: ctx, flipped: view.isFlipped)
                (dark ? spec.darkVeil : NSColor.white).withAlphaComponent(dark ? spec.darkVeilAlpha : spec.lightVeilAlpha).setFill()
                ctx.fill(rect)
                if let tint = spec.tint {
                    tint.withAlphaComponent(tint.alphaComponent * spec.tintAlpha).setFill()
                    ctx.fill(rect)
                }
                if spec.brighten > 0 {
                    NSColor.white.withAlphaComponent(spec.brighten).setFill()
                    ctx.fill(rect)
                }
            }
        } else {
            // Nothing to sample (no window, no backing surface): the veil over the window colour.
            NSColor.windowBackgroundColor.setFill()
            ctx.fill(rect)
            let dark = spec.resolvesDark(luminance: nil)
            (dark ? spec.darkVeil : NSColor.white).withAlphaComponent(dark ? spec.darkVeilAlpha : spec.lightVeilAlpha).setFill()
            ctx.fill(rect)
        }
        ctx.restoreGState()
    }

    private static func isPath(_ outline: _GlassOutline) -> Bool {
        if case .path = outline { return true }
        return false
    }

    /// The glass through the GPU program: the request built from the spec as the software
    /// pass builds its parameters, the raw sample when the program blurs it itself, the
    /// result drawn in place or cached with the sample as the software pass's shaded image.
    private static func drawWithProgram(_ program: any PlatformGlassProgram, spec: _GlassSpec, outline: _GlassOutline, in rect: NSRect, margin: CGFloat,
                                        sample: _GlassSample, view: NSView, context ctx: CGContext) -> Bool {
        guard let backdrop = sample.backdrop(rect: rect.insetBy(dx: -margin, dy: -margin), spec: spec, view: view, raw: program.runsBackdropStage) else {
            // Nothing to sample: the software pass's fallback fill, not a program failure.
            return false
        }
        let scale = view.window?.backingScaleFactor ?? 1
        let request = glassRequest(spec, outline: outline, in: rect, margin: margin, scale: scale, view: view, backdrop: backdrop, blurPixels: sample.blurPixels, raw: program.runsBackdropStage)
        let t0 = NSView._traceFrames ? NSView._traceClock() : 0
        let ok: Bool
        if program.drawsInPlace {
            ok = program.draw(backdrop.image, request: request, in: rect, of: ctx, flipped: view.isFlipped)
        } else {
            var h = Hasher(); h.combine(request); h.combine(view.isFlipped)
            if let image = sample.shaded(key: h.finalize(), make: { program.render(backdrop.image, request: request) }) {
                drawImage(image, in: rect, context: ctx, flipped: view.isFlipped)
                ok = true
            } else {
                ok = false
            }
        }
        if NSView._traceFrames {
            NSView._trace(String(format: "glass %@ %dx%d px (%@): %.2f ms", program.name, request.parameters.width, request.parameters.height, spec.lens ? "lens" : "material", NSView._traceClock() - t0))
        }
        return ok
    }

    /// The program's request: the parameters of both variants, the shape, where the
    /// backdrop lies in output pixels, the backdrop stage's blur and saturation.
    static func glassRequest(_ spec: _GlassSpec, outline: _GlassOutline, in rect: NSRect, margin: CGFloat, scale: CGFloat, view: NSView,
                             backdrop: (image: CGImage, imageRect: NSRect?, luminance: CGFloat?), blurPixels: Int, raw: Bool) -> PlatformGlassRequest {
        var p = PlatformGlassParameters(width: max(1, Int((rect.width * scale).rounded(.up))), height: max(1, Int((rect.height * scale).rounded(.up))))
        p.veil = .white
        p.veilAlpha = spec.lightVeilAlpha
        p.rimAlpha = spec.rimAlpha
        p.specular = spec.specular
        if let tint = spec.tint, let c = tint.usingColorSpace(.sRGB) {
            p.tint = .init(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: c.alphaComponent)
            p.tintAlpha = spec.tintAlpha
        }
        p.edgeWidth = spec.edgeWidth * scale
        p.refraction = spec.refraction * scale
        p.rimWidth = spec.lens ? max(1, 1 * scale) : 0
        p.brighten = spec.brighten
        let dv = spec.darkVeil.usingColorSpace(.sRGB) ?? spec.darkVeil
        let variant: PlatformGlassRequest.Variant
        switch spec.variant { case .light: variant = .light; case .dark: variant = .dark; case .adaptive: variant = .adaptive }
        let backdropRect: CGRect
        if let imageRect = backdrop.imageRect {
            let inWindow = view.convert(rect, to: nil)
            backdropRect = CGRect(x: (imageRect.minX - inWindow.minX) * scale, y: (inWindow.maxY - imageRect.maxY) * scale, width: imageRect.width * scale, height: imageRect.height * scale)
        } else {
            backdropRect = CGRect(x: -margin * scale, y: -margin * scale, width: (rect.width + 2 * margin) * scale, height: (rect.height + 2 * margin) * scale)
        }
        let radius: CGFloat
        if spec.lens, case .roundedRect(let r) = outline { radius = r * scale } else { radius = 0 }
        return PlatformGlassRequest(parameters: p, darkVeil: .init(red: dv.redComponent, green: dv.greenComponent, blue: dv.blueComponent), darkVeilAlpha: spec.darkVeilAlpha,
                                    darkRimAlpha: spec.rimAlpha * 0.55, darkSpecular: spec.specular * 0.7, variant: variant,
                                    shapeRect: CGRect(x: 0, y: 0, width: CGFloat(p.width), height: CGFloat(p.height)), cornerRadius: radius,
                                    backdropRect: backdropRect, blurRadius: blurPixels, saturation: spec.saturation,
                                    luminance: raw ? nil : (backdrop.luminance ?? 1))
    }

    /// The lens stage's shape for `outline`: the rounded rectangle in output pixels, or the
    /// path rasterised into a coverage mask whose top row is the view's top.
    private static func outlineShape(_ outline: _GlassOutline, path: NSBezierPath, in rect: NSRect, pixels: (Int, Int), scale: CGFloat, flipped: Bool) -> PlatformGlassShape? {
        switch outline {
        case .roundedRect(let radius):
            return .roundedRect(CGRect(x: 0, y: 0, width: CGFloat(pixels.0), height: CGFloat(pixels.1)), cornerRadius: radius * scale)
        case .path:
            guard let surface = Platform.backend.image.makeOffscreen(size: rect.size, scale: scale) else { return nil }
            let c = surface.context
            if flipped {
                c.translateBy(x: -rect.minX, y: rect.height + rect.minY); c.scaleBy(x: 1, y: -1)
            } else {
                c.translateBy(x: -rect.minX, y: -rect.minY)
            }
            c.setFillColor(CGColor(gray: 1, alpha: 1))
            c.addPath(path.cgPath)
            c.fillPath()
            guard let mask = surface.makeImage(), mask.width == pixels.0, mask.height == pixels.1 else { return nil }
            return .coverage(mask)
        }
    }

    /// The cache key of a shaded image: the parameters and the outline (its bounds and
    /// element count stand for a path).
    private static func shapeKey(_ outline: _GlassOutline, path: NSBezierPath, parameters: PlatformGlassParameters, flipped: Bool) -> Int {
        var h = Hasher()
        h.combine(parameters)
        h.combine(flipped)
        switch outline {
        case .roundedRect(let r): h.combine(0); h.combine(r)
        case .path:
            h.combine(1); h.combine(path.elementCount)
            let b = path.bounds
            h.combine(b.origin.x); h.combine(b.origin.y); h.combine(b.width); h.combine(b.height)
        }
        return h.finalize()
    }

    /// Draws an image whose top row is the view's top into `rect`, in a flipped view too.
    private static func drawImage(_ image: CGImage, in rect: NSRect, context ctx: CGContext, flipped: Bool) {
        ctx.interpolationQuality = .default
        if flipped {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: rect.minY + rect.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: rect)
            ctx.restoreGState()
        } else {
            ctx.draw(image, in: rect)
        }
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


/// The cached sample of the content beneath one glass surface: the blurred backdrop, and
/// the shaded image last drawn from it.
@MainActor
internal final class _GlassSample {
    weak var owner: NSView?
    /// The blurred, saturated backdrop.
    private(set) var image: CGImage?
    /// Its mean luminance (the adaptive variant reads it).
    private(set) var luminance: CGFloat?
    /// Whether the sample was the mirrored strip beyond the edge (nothing but the window
    /// background lay beneath the surface).
    private(set) var extended = false
    /// The rectangle asked for, in the owner's bounds and in the window, and the rectangle
    /// the image covers (the request snapped to the sample's pixel grid), in the window.
    private(set) var rect = NSRect.null
    private(set) var windowRect = NSRect.null
    private(set) var imageWindowRect = NSRect.null
    private var scale: CGFloat = 0
    private var blur: CGFloat = 0
    private var saturation: CGFloat = 0
    private var extendsFrom: NSRectEdge?
    private var appearanceIsDark = false
    /// Whether the image is the raw sample (the GPU program blurs it) or the blurred one.
    private(set) var isRaw = false
    /// The blur radius in sample pixels the backdrop stage uses.
    private(set) var blurPixels = 0
    private var generation = 0
    private var shadeKey: Int?
    private var shadeGeneration = -1
    private(set) var shadedImage: CGImage?
    var dirty = true
    init(owner: NSView) { self.owner = owner }

    /// The blurred content beneath `rect` (bounds coordinates), sampled afresh when the
    /// cache is dirty or the surface moved, scaled or re-themed. `imageRect` is the
    /// rectangle the image covers, in window coordinates (nil without a window).
    /// With `raw` the image is the sample as rendered, for a GPU program that runs the
    /// backdrop stage itself (ADR-0052 stage 2), and no luminance is probed.
    func backdrop(rect: NSRect, spec: _GlassSpec, view: NSView, raw: Bool = false) -> (image: CGImage, imageRect: NSRect?, luminance: CGFloat?)? {
        let backing = view.window?.backingScaleFactor ?? 1
        let dark = view.effectiveAppearance.isDark
        let inWindow = view.convert(rect, to: nil)
        if dirty || image == nil || rect != self.rect || inWindow != windowRect || backing != scale || spec.blurRadius != blur || spec.saturation != saturation || spec.extendsFrom != extendsFrom || dark != appearanceIsDark || raw != isRaw {
            self.rect = rect; windowRect = inWindow; scale = backing; blur = spec.blurRadius; saturation = spec.saturation; extendsFrom = spec.extendsFrom; appearanceIsDark = dark; isRaw = raw
            dirty = false
            generation += 1
            let sampleScale = max(0.125, backing / (spec.lens ? _GlassRenderer.sampleScaleDivisor : _GlassRenderer.materialSampleScaleDivisor))
            image = nil; luminance = nil; extended = false; imageWindowRect = .null
            let t0 = NSView._traceFrames ? NSView._traceClock() : 0
            if let raw = _GlassRegistry.render(beneath: view, rect: rect, scale: sampleScale, extendsFrom: spec.extendsFrom, margin: spec.blurRadius + spec.refraction) {
                extended = raw.extended
                imageWindowRect = raw.windowRect ?? .null
                let radius = Int((spec.blurRadius * sampleScale).rounded())
                blurPixels = radius
                let t1 = NSView._traceFrames ? NSView._traceClock() : 0
                if isRaw {
                    image = raw.image
                } else {
                    let blurred = Platform.backend.material.blur(raw.image, radius: radius, saturation: spec.saturation) ?? raw.image
                    image = blurred
                }
                let t2 = NSView._traceFrames ? NSView._traceClock() : 0
                if !isRaw, let image { luminance = Platform.backend.material.averageLuminance(image) }
                if NSView._traceFrames { NSView._trace(String(format: "glass sample stages: crop %.2f blur %.2f luminance %.2f ms", t1 - t0, t2 - t1, NSView._traceClock() - t2)) }
            }
            if NSView._traceFrames, let image {
                NSView._trace(String(format: "glass sample %@ %dx%d px, blur %.0f: %.2f ms%@", String(describing: type(of: view)), image.width, image.height, spec.blurRadius * sampleScale, NSView._traceClock() - t0, extended ? " (mirrored strip)" : ""))
            }
        }
        guard let image else { return nil }
        return (image, imageWindowRect.isNull ? nil : imageWindowRect, luminance)
    }

    /// The shaded image for `key` over the current backdrop, made when either changed.
    func shaded(key: Int, make: () -> CGImage?) -> CGImage? {
        if shadeKey == key, shadeGeneration == generation, let shadedImage { return shadedImage }
        let t0 = NSView._traceFrames ? NSView._traceClock() : 0
        shadedImage = make()
        shadeKey = key; shadeGeneration = generation
        if NSView._traceFrames, let shadedImage {
            NSView._trace(String(format: "glass shade %dx%d px: %.2f ms", shadedImage.width, shadedImage.height, NSView._traceClock() - t0))
        }
        return shadedImage
    }
}

/// What one paint of a window drew beneath its glass, at the sample scale: everything up
/// to the first glass surface in the paint order, rendered once per paint however many
/// surfaces the window has, each cropping its own rectangle (ADR-0052). The frame lives
/// until a view outside the glass dirties the window.
@MainActor
internal final class _GlassFrame {
    /// The window rectangle the pixels cover; the top row is its top edge.
    let rect: NSRect
    let scale: CGFloat
    let pixels: _MaterialPixels
    let invalidation: Int
    init(rect: NSRect, scale: CGFloat, pixels: _MaterialPixels, invalidation: Int) {
        self.rect = rect; self.scale = scale; self.pixels = pixels; self.invalidation = invalidation
    }

    /// This frame at half the scale: every pixel the rounded mean of a 2x2 block (the last
    /// row or column of an odd size repeats), the top edge kept.
    func halved(invalidation: Int) -> _GlassFrame {
        let sw = pixels.width, sh = pixels.height, ss = pixels.stride
        let w = (sw + 1) / 2, h = (sh + 1) / 2, stride = w * 4
        var out = [UInt8](repeating: 0, count: stride * h)
        pixels.bytes.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for y in 0..<h {
                    let r0 = 2 * y * ss, r1 = min(sh - 1, 2 * y + 1) * ss
                    for x in 0..<w {
                        let c0 = 2 * x * 4, c1 = min(sw - 1, 2 * x + 1) * 4
                        for c in 0..<4 {
                            let sum = Int(src[r0 + c0 + c]) + Int(src[r0 + c1 + c]) + Int(src[r1 + c0 + c]) + Int(src[r1 + c1 + c])
                            dst[y * stride + x * 4 + c] = UInt8((sum + 2) >> 2)
                        }
                    }
                }
            }
        }
        let half = scale / 2
        let r = NSRect(x: rect.minX, y: rect.maxY - CGFloat(h) / half, width: CGFloat(w) / half, height: CGFloat(h) / half)
        return _GlassFrame(rect: r, scale: half, pixels: _MaterialPixels(bytes: out, width: w, height: h, stride: stride, template: pixels.template), invalidation: invalidation)
    }

    /// The pixel rows and columns covering `windowRect`, clamped to the frame.
    func cells(for windowRect: NSRect) -> (columns: Range<Int>, rows: Range<Int>)? {
        let c0 = max(0, Int(((windowRect.minX - rect.minX) * scale).rounded(.down)))
        let c1 = min(pixels.width, Int(((windowRect.maxX - rect.minX) * scale).rounded(.up)))
        let r0 = max(0, Int(((rect.maxY - windowRect.maxY) * scale).rounded(.down)))
        let r1 = min(pixels.height, Int(((rect.maxY - windowRect.minY) * scale).rounded(.up)))
        guard c1 > c0, r1 > r0 else { return nil }
        return (c0..<c1, r0..<r1)
    }

    /// The window rectangle the cells cover.
    func windowRect(columns: Range<Int>, rows: Range<Int>) -> NSRect {
        NSRect(x: rect.minX + CGFloat(columns.lowerBound) / scale, y: rect.maxY - CGFloat(rows.upperBound) / scale,
               width: CGFloat(columns.count) / scale, height: CGFloat(rows.count) / scale)
    }

    /// The pixels of the cells; `mirrorBelow` (a row index within `rows`) takes the rows
    /// above it from the rows below it in reverse, a strip beyond an edge mirrored in.
    func crop(columns: Range<Int>, rows: Range<Int>, mirrorBelow edge: Int? = nil) -> _MaterialPixels {
        let w = columns.count, h = rows.count, outStride = w * 4
        var out = [UInt8](repeating: 0, count: outStride * h)
        let inStride = pixels.stride, x0 = columns.lowerBound * 4
        pixels.bytes.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for r in 0..<h {
                    var source = rows.lowerBound + r
                    if let edge, r < edge {
                        // Row k above the edge mirrors row k below it.
                        source = min(pixels.height - 1, rows.lowerBound + edge + (edge - 1 - r))
                    }
                    let s = source * inStride + x0, d = r * outStride
                    for i in 0..<outStride { dst[d + i] = src[s + i] }
                }
            }
        }
        return _MaterialPixels(bytes: out, width: w, height: h, stride: outStride, template: pixels.template)
    }
}

/// Every live glass surface, so a view dirtying the content beneath one marks its sample
/// stale (and the surface for redisplay), and a window's key change redraws them all.
@MainActor
internal enum _GlassRegistry {
    private struct Key: Hashable { let view: ObjectIdentifier; let slot: Int }
    private static var samples: [Key: _GlassSample] = [:]
    private static var keyObserverInstalled = false
    /// The shared frame per window and the count of invalidations it has seen, which a
    /// frame records so a stale one is never cropped.
    private static var frames: [ObjectIdentifier: [CGFloat: _GlassFrame]] = [:]
    private static var invalidations: [ObjectIdentifier: Int] = [:]
    /// Frames rendered, for the tests of the per-paint sharing.
    internal static var frameRenders = 0

    static func sample(for view: NSView, slot: Int = 0) -> _GlassSample {
        let key = Key(view: ObjectIdentifier(view), slot: slot)
        if let s = samples[key], s.owner === view { return s }
        let s = _GlassSample(owner: view)
        samples[key] = s
        observeKeyChanges(of: view)
        return s
    }

    /// Whether `view` draws a glass surface this registry knows.
    static func isOwner(_ view: NSView) -> Bool {
        samples.contains { $0.key.view == ObjectIdentifier(view) && $0.value.owner === view }
    }

    /// Called by the window for every invalidation: a view outside the glass surface (not
    /// the surface itself nor one of its subviews, whose pixels lie over the glass)
    /// dirtying its rectangle invalidates the sample. Only the samples the rectangle
    /// reaches go stale: content scrolling under the toolbar band re-samples the band and
    /// leaves the lenses elsewhere alone, and the other way round.
    static func noteInvalidation(in window: NSWindow, from view: NSView?, rect: NSRect?) {
        guard !samples.isEmpty else { return }
        var outsideGlass = false
        for (key, s) in samples {
            guard let owner = s.owner else { samples[key] = nil; continue }
            guard owner.window === window else { continue }
            if let view, view === owner || view.isDescendant(of: owner) { continue }
            outsideGlass = true
            guard !s.dirty else { continue }
            if let rect, !s.windowRect.isNull, !s.windowRect.intersects(rect) {
                // An extended sample also watches the strip it mirrored.
                guard s.extended, s.windowRect.offsetBy(dx: 0, dy: -s.windowRect.height).intersects(rect) else { continue }
            }
            s.dirty = true
            owner.needsDisplay = true
        }
        if outsideGlass || view == nil {
            let id = ObjectIdentifier(window)
            invalidations[id, default: 0] += 1
            frames[id] = nil
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
    /// every view drawn before the glass in the paint order. With `extendsFrom` set and
    /// nothing but the window background beneath the surface (the part of `rect` inside
    /// the `margin`), the content beyond that edge is mirrored in. `windowRect` is the
    /// rectangle the image covers (the request snapped to the sample's pixels); it is nil
    /// for a view without a window, whose image covers `rect` exactly.
    static func render(beneath view: NSView, rect: NSRect, scale: CGFloat, extendsFrom: NSRectEdge? = nil, margin: CGFloat = 0) -> (image: CGImage, extended: Bool, windowRect: NSRect?)? {
        guard rect.width > 0, rect.height > 0, rect.width.isFinite, rect.height.isFinite else { return nil }
        guard let window = view.window else {
            guard let image = renderStandalone(beneath: view, rect: rect, scale: scale) else { return nil }
            return (image, false, nil)
        }
        guard let frame = frame(of: window, beneath: view, scale: scale) else { return nil }
        let inWindow = view.convert(rect, to: nil)
        guard let cells = frame.cells(for: inWindow) else { return nil }
        let covered = frame.windowRect(columns: cells.columns, rows: cells.rows)
        var mirrorBelow: Int?
        if extendsFrom == .minY, let bg = window._backgroundColor.usingColorSpace(.sRGB) {
            // The surface's rows within the crop: the request less its margins. When they
            // hold nothing but the window background, the rows below the surface's bottom
            // edge (as many as lie above it) are mirrored about that edge; the margin
            // below the edge keeps the real content, so the mirror joins it without a seam.
            let background = PlatformGlassParameters.Color(red: bg.redComponent, green: bg.greenComponent, blue: bg.blueComponent)
            let top = Int(((covered.maxY - (inWindow.maxY - margin)) * scale).rounded())
            let bottom = Int(((covered.maxY - (inWindow.minY + margin)) * scale).rounded())
            if bottom > top, top >= 0, bottom <= cells.rows.count {
                let surface = frame.crop(columns: cells.columns, rows: (cells.rows.lowerBound + top)..<(cells.rows.lowerBound + bottom))
                if surface.mostly(background) { mirrorBelow = bottom }
            }
        }
        let pixels = frame.crop(columns: cells.columns, rows: cells.rows, mirrorBelow: mirrorBelow)
        guard let image = pixels.makeImage() else { return nil }
        return (image, mirrorBelow != nil, covered)
    }

    /// The window's shared frame, rendered now unless the one from this paint is current.
    private static func frame(of window: NSWindow, beneath view: NSView, scale: CGFloat) -> _GlassFrame? {
        let id = ObjectIdentifier(window)
        let invalidation = invalidations[id, default: 0]
        if let f = frames[id]?[scale], f.invalidation == invalidation { return f }
        // One render of the window per paint (ADR-0052 stage 2): a material's frame (an eighth
        // of the backing scale) is the lens frame (a quarter) halved, not a second paint of
        // the view tree, which on Windows cost as much as the first (3.4 ms at 1x on the PC).
        let lensScale = max(0.125, window.backingScaleFactor / _GlassRenderer.sampleScaleDivisor)
        if scale < lensScale, abs(lensScale / scale - 2) < 1e-6, let full = frame(of: window, beneath: view, scale: lensScale) {
            let t0 = NSView._traceFrames ? NSView._traceClock() : 0
            let f = full.halved(invalidation: invalidation)
            frames[id, default: [:]][scale] = f
            if NSView._traceFrames {
                NSView._trace(String(format: "glass frame %dx%d px at %.2fx (halved): %.2f ms", f.pixels.width, f.pixels.height, scale, NSView._traceClock() - t0))
            }
            return f
        }
        // The area the window paints: the content, the toolbar band above it, accessories.
        var area = window._contentView?.frame ?? .zero
        if let t = window._toolbarView, !t.isHidden { area = area.union(t.frame) }
        if let a = window._accessoryHost, !a.isHidden { area = area.union(a.frame) }
        guard area.width > 0, area.height > 0, area.width.isFinite, area.height.isFinite else { return nil }
        area = NSRect(x: area.minX, y: area.minY, width: (area.width * scale).rounded(.up) / scale, height: (area.height * scale).rounded(.up) / scale)
        let t0 = NSView._traceFrames ? NSView._traceClock() : 0
        guard let surface = Platform.backend.image.makeOffscreen(size: area.size, scale: scale) else { return nil }
        let ctx = surface.context
        // Every glass surface stops the paint: the frame holds what lies beneath the first
        // of them in the paint order (the content under a lens, never the lens itself).
        var stops = Set<ObjectIdentifier>(), stopLayers = Set<ObjectIdentifier>()
        for s in samples.values {
            guard let o = s.owner, o.window === window else { continue }
            stops.insert(ObjectIdentifier(o))
            if let l = o.layer { stopLayers.insert(ObjectIdentifier(l)) }
        }
        stops.insert(ObjectIdentifier(view))
        if let l = view.layer { stopLayers.insert(ObjectIdentifier(l)) }
        let previousStop = NSView._glassStop, previousStops = NSView._glassStops, previousStopped = CALayer._composeStopped
        let previousStopLayer = CALayer._composeStopLayer, previousStopLayers = CALayer._composeStopLayers
        let previousCaching = NSView._cachingDisplay
        let previousContext = NSGraphicsContext.current
        let previousAppearance = NSAppearance.current
        NSView._glassStop = view; NSView._glassStops = stops; CALayer._composeStopped = false
        CALayer._composeStopLayer = view.layer ?? placeholderStopLayer; CALayer._composeStopLayers = stopLayers
        NSView._cachingDisplay = true
        defer {
            NSView._glassStop = previousStop; NSView._glassStops = previousStops; CALayer._composeStopped = previousStopped
            CALayer._composeStopLayer = previousStopLayer; CALayer._composeStopLayers = previousStopLayers
            NSView._cachingDisplay = previousCaching
            NSGraphicsContext.current = previousContext
            NSAppearance.current = previousAppearance
        }
        ctx.saveGState()
        ctx.translateBy(x: -area.minX, y: -area.minY)
        NSAppearance.current = window.effectiveAppearance
        window._drawBeneathGlass(into: ctx, rect: area)
        ctx.restoreGState()
        guard let image = surface.makeImage(), let pixels = _MaterialPixels(image) else { return nil }
        let f = _GlassFrame(rect: area, scale: scale, pixels: pixels, invalidation: invalidation)
        frames[id, default: [:]][scale] = f
        frameRenders += 1
        if NSView._traceFrames {
            NSView._trace(String(format: "glass frame %dx%d px at %.2fx: %.2f ms", pixels.width, pixels.height, scale, NSView._traceClock() - t0))
        }
        return f
    }

    /// The view tree beneath `view` for `rect` (bounds coordinates) when it has no window:
    /// a detached hierarchy drawn into an offscreen image.
    private static func renderStandalone(beneath view: NSView, rect: NSRect, scale: CGFloat) -> CGImage? {
        guard let root = view._glassRootView, root !== view else { return nil }
        guard let surface = Platform.backend.image.makeOffscreen(size: rect.size, scale: scale) else { return nil }
        let ctx = surface.context
        let previousStop = NSView._glassStop, previousStopped = CALayer._composeStopped, previousStopLayer = CALayer._composeStopLayer
        let previousCaching = NSView._cachingDisplay
        let previousContext = NSGraphicsContext.current
        NSView._glassStop = view; CALayer._composeStopped = false
        CALayer._composeStopLayer = view.layer ?? placeholderStopLayer
        NSView._cachingDisplay = true
        defer {
            NSView._glassStop = previousStop; CALayer._composeStopped = previousStopped; CALayer._composeStopLayer = previousStopLayer
            NSView._cachingDisplay = previousCaching
            NSGraphicsContext.current = previousContext
        }
        ctx.saveGState()
        let inRoot = view.convert(rect, to: root)
        ctx.translateBy(x: -inRoot.minX, y: -inRoot.minY)
        if root.isFlipped { ctx.translateBy(x: 0, y: root.bounds.height); ctx.scaleBy(x: 1, y: -1) }
        root._displayHierarchy(in: ctx, dirtyRect: root.frame)
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
    /// shares), so the sample holds only what lies under the glass. `_glassStops` are the
    /// other glass surfaces of the window, which stop a shared frame too.
    @MainActor internal static var _glassStop: NSView?
    @MainActor internal static var _glassStops = Set<ObjectIdentifier>()

    /// Whether a glass sample in progress stops at this view.
    @MainActor internal var _stopsGlassSample: Bool {
        guard let stop = NSView._glassStop else { return false }
        return stop === self || NSView._glassStops.contains(ObjectIdentifier(self))
    }

    @MainActor internal var _glassRootView: NSView? {
        var v: NSView = self
        while let s = v.superview { v = s }
        return v
    }
}

extension NSWindow {
    /// Draws the window as `platformWindowDraw` does (background, content, toolbar band,
    /// accessories, in that order) until the paint reaches a glass surface.
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
