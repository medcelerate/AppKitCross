// NSVisualEffectView (hand-written; seeded from the generated stub, see tools/apigen)
// A translucent material. Blending behind the window asks the window for a system
// backdrop (Mica/Acrylic on Windows 11); within the window it is a tinted fill.

import Foundation

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
    }

    open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if window != nil, _backdrop != .none { _applyBackdrop() }
    }

    /// Draws the material as a translucent tint; the real blur comes from the window's
    /// backdrop (behind-window) or is approximated by the tint (within-window).
    open override func draw(_ dirtyRect: NSRect) {
        let active = _state == .active || (_state == .followsWindowActiveState && (window?.isKeyWindow ?? true))
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
