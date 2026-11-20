// NSVisualEffectView (hand-written; seeded from the generated stub, see tools/apigen)
// A translucent material. Blending behind the window asks the window for a system
// backdrop (Mica/Acrylic on Windows 11); within the window it is a tinted fill, or with
// Liquid Glass on (ADR-0051) the glass material over the content beneath.

import Foundation

// MARK: - Liquid Glass switch (ADR-0051)

/// Whether the port draws macOS 26's Liquid Glass: `APPKITWIN_LIQUID_GLASS=1` in the
/// environment, else the `AppKitCrossLiquidGlass` Info.plist key. Off, every surface
/// keeps the look it had before the switch existed, pixel for pixel.
@MainActor
public enum _LiquidGlass {
    /// Pins the switch (tests); nil reads the environment and Info.plist.
    public static var _override: Bool?
    private static var _resolved: Bool?

    public static var isEnabled: Bool {
        if let o = _override { return o }
        if let r = _resolved { return r }
        let r = _read()
        _resolved = r
        return r
    }

    private static func _read() -> Bool {
        func truth(_ v: Any?) -> Bool? {
            switch v {
            case let b as Bool: return b
            case let n as NSNumber: return n.boolValue
            case let s as String:
                switch s.lowercased() { case "1", "yes", "true": return true; case "0", "no", "false": return false; default: return nil }
            default: return nil
            }
        }
        if let v = truth(ProcessInfo.processInfo.environment["APPKITWIN_LIQUID_GLASS"]) { return v }
        return truth(NSDocumentController._infoDictionary()["AppKitCrossLiquidGlass"]) ?? false
    }
}

/// The surfaces the port draws with glass when the switch is on: the band behind a
/// toolbar, one toolbar item's capsule, a sidebar column and a glass control.
public enum _MaterialKind {
    case toolbarBand
    case toolbarItem(highlighted: Bool)
    case sidebar
    case control(prominent: Bool, highlighted: Bool)
}

/// The hook a toolbar band, a sidebar column or a control calls before its own fill:
/// with Liquid Glass on it draws the glass material in `rect` and answers true; off it
/// draws nothing and answers false, so the caller keeps today's drawing untouched.
@MainActor
public enum _MaterialBackground {
    @discardableResult
    public static func draw(_ kind: _MaterialKind, in rect: NSRect, of view: NSView) -> Bool {
        guard _LiquidGlass.isEnabled, rect.width > 0, rect.height > 0 else { return false }
        switch kind {
        case .toolbarBand:
            _GlassRenderer.draw(_GlassSpec.material(in: view), path: NSBezierPath(rect: rect), in: rect, of: view)
        case .sidebar:
            _GlassRenderer.draw(_GlassSpec.material(in: view), path: NSBezierPath(rect: rect), in: rect, of: view)
        case .toolbarItem(let highlighted):
            var spec = _GlassSpec.lens(clear: false, in: view)
            if highlighted { spec.tint = .labelColor; spec.tintAlpha = 0.14 }
            let r = min(rect.height, rect.width) / 2
            _GlassRenderer.draw(spec, path: NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r), in: rect, of: view)
        case .control(let prominent, let highlighted):
            var spec = _GlassSpec.lens(clear: false, in: view)
            if prominent { spec.tint = .controlAccentColor; spec.tintAlpha = highlighted ? 0.95 : 0.85 }
            else if highlighted { spec.tint = .labelColor; spec.tintAlpha = 0.14 }
            let r = min(rect.height, rect.width) / 2
            _GlassRenderer.draw(spec, path: NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r), in: rect, of: view)
        }
        return true
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsvisualeffectview
@MainActor open class NSVisualEffectView: NSView {
    private var _material: NSVisualEffectView.Material = .appearanceBased
    private var _blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    private var _state: NSVisualEffectView.State = .followsWindowActiveState
    private var _isEmphasized = false
    private var _maskImage: NSImage? = nil
    private var _interiorBackgroundStyle: NSView.BackgroundStyle = .normal

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsvisualeffectview/material
    open var material: NSVisualEffectView.Material {
        get { _material }
        set { _material = newValue; _applyMaterialAppearance(); _applyBackdrop(); needsDisplay = true }
    }

    /// HUD and dark materials carry the vibrant dark appearance so their content draws dark.
    private func _applyMaterialAppearance() {
        switch _material {
        case .hudWindow, .dark, .ultraDark: appearance = NSAppearance(named: .vibrantDark)
        case .light, .mediumLight: appearance = NSAppearance(named: .vibrantLight)
        default: break
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsvisualeffectview/blendingmode
    open var blendingMode: NSVisualEffectView.BlendingMode {
        get { _blendingMode }
        set { _blendingMode = newValue; _applyBackdrop(); needsDisplay = true }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsvisualeffectview/state
    open var state: NSVisualEffectView.State {
        get { _state }
        set { _state = newValue; needsDisplay = true }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsvisualeffectview/isemphasized
    open var isEmphasized: Bool {
        get { _isEmphasized }
        set { _isEmphasized = newValue; needsDisplay = true }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsvisualeffectview/maskimage
    open var maskImage: NSImage? {
        get { _maskImage }
        set { _maskImage = newValue; _applyBackdrop(); needsDisplay = true }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsvisualeffectview/interiorbackgroundstyle
    open var interiorBackgroundStyle: NSView.BackgroundStyle { _interiorBackgroundStyle }

    open override var isOpaque: Bool { false }

    /// The system backdrop a material maps to on Windows 11.
    internal var _backdrop: PlatformWindowChrome.Backdrop {
        guard _blendingMode == .behindWindow else { return .none }
        switch _material {
        case .hudWindow, .popover, .menu, .selection, .toolTip, .fullScreenUI, .dark, .mediumLight, .ultraDark: return .acrylic
        case .sidebar, .titlebar, .headerView, .underPageBackground, .windowBackground, .underWindowBackground, .contentBackground, .sheet, .light, .appearanceBased: return .mica
        @unknown default: return .mica
        }
    }

    /// The window whose backdrop this view last counted in (re-evaluated when it leaves).
    private weak var _backdropWindow: NSWindow?

    private func _applyBackdrop() {
        if let old = _backdropWindow, old !== window { old._updateBackdrop() }
        _backdropWindow = window
        guard let w = window else { return }
        w._hasEffectViews = true
        w._updateBackdrop()
    }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        _applyBackdrop()
        if _LiquidGlass.isEnabled { _GlassRegistry.observeKeyChanges(of: self) }
    }

    open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if window != nil, _backdrop != .none { _applyBackdrop() }
    }

    /// Draws the material as a translucent tint; the real blur comes from the window's
    /// backdrop (behind-window) or is approximated by the tint (within-window).
    open override func draw(_ dirtyRect: NSRect) {
        let active = _state == .active || (_state == .followsWindowActiveState && (window?.isKeyWindow ?? true))
        if _LiquidGlass.isEnabled, _blendingMode == .withinWindow, _maskImage == nil {
            // Liquid Glass: the material over the content beneath (ADR-0051). HUD and dark
            // materials keep their dark veil; a selection its colour.
            var spec = _GlassSpec.material(in: self)
            switch _material {
            case .hudWindow, .dark, .ultraDark: spec.veil = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1); spec.veilAlpha = active ? 0.6 : 0.75
            case .selection: spec.tint = _isEmphasized ? .controlAccentColor : .secondarySelectedControlColor; spec.tintAlpha = 0.6
            default: if !active { spec.veilAlpha = 0.7 }
            }
            let radius = (layer?.cornerRadius ?? 0)
            let path = radius > 0 ? NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius) : NSBezierPath(rect: bounds)
            _GlassRenderer.draw(spec, path: path, in: bounds, of: self)
            return
        }
        let alpha: CGFloat
        switch _material {
        case .hudWindow, .dark, .ultraDark: alpha = active ? 0.55 : 0.7
        case .popover, .menu, .toolTip, .selection: alpha = active ? 0.5 : 0.65
        case .sidebar, .titlebar, .headerView: alpha = active ? 0.35 : 0.5
        default: alpha = active ? 0.45 : 0.6
        }
        let base: NSColor
        switch _material {
        case .hudWindow, .dark, .ultraDark: base = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)
        case .selection: base = _isEmphasized ? .controlAccentColor : .secondarySelectedControlColor
        default: base = .windowBackgroundColor
        }
        base.withAlphaComponent(_blendingMode == .behindWindow ? alpha : min(1, alpha + 0.3)).setFill()
        NSBezierPath(rect: bounds).fill()
    }
}

extension NSWindow {
    /// Recomputes the system backdrop the window's visible behind-window effect views ask
    /// for (the strongest wins: acrylic over mica) and their shape: whether one covers the
    /// whole content area, and the corner radius layers clip them to. A backend whose
    /// backdrop fills the window rectangle (DWM) uses the shape to keep a non-opaque window
    /// transparent where its content leaves the rectangle uncovered.
    internal func _updateBackdrop() {
        var best = PlatformWindowChrome.Backdrop.none
        var covers = false
        var radius: CGFloat = 0
        guard let content = contentView else {
            _backdrop = .none; _backdropCoversWindow = true; _backdropCornerRadius = 0
            return
        }
        let bounds = content.bounds
        func clipRadius(_ v: NSView, own: Bool) -> CGFloat {
            guard let l = v.layer, l.cornerRadius > 0, own || l.masksToBounds else { return 0 }
            return l.cornerRadius
        }
        func visit(_ v: NSView, ancestorRadius: CGFloat) {
            guard !v.isHidden else { return }
            var inherited = ancestorRadius
            if let e = v as? NSVisualEffectView {
                let b = e._backdrop
                if b != .none {
                    if b == .acrylic || (b == .mica && best == .none) { best = b }
                    let r = max(inherited, clipRadius(e, own: true))
                    radius = max(radius, r)
                    // Allow a point of inset each side (a card's border stroke).
                    let rect = e.convert(e.bounds, to: content)
                    if e.maskImage == nil, rect.insetBy(dx: -2, dy: -2).contains(bounds) { covers = true }
                }
            }
            inherited = max(inherited, clipRadius(v, own: false))
            for s in v.subviews { visit(s, ancestorRadius: inherited) }
        }
        visit(content, ancestorRadius: 0)
        _backdrop = best
        _backdropCoversWindow = best == .none || covers
        _backdropCornerRadius = best == .none ? 0 : radius
    }
}
