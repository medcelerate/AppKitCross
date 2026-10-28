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
        set { _maskImage = newValue; needsDisplay = true }
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

    private func _applyBackdrop() {
        guard let w = window else { return }
        // The strongest request among the window's effect views wins.
        var best = PlatformWindowChrome.Backdrop.none
        func visit(_ v: NSView) {
            if let e = v as? NSVisualEffectView {
                let b = e._backdrop
                if b == .acrylic || (b == .mica && best == .none) { best = b }
            }
            for s in v.subviews { visit(s) }
        }
        if let c = w.contentView { visit(c) }
        if w._backdrop != best { w._backdrop = best }
    }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        _applyBackdrop()
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
