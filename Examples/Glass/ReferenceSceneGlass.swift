// The glass half of the reference scenes (ReferenceScene.swift): real NSGlassEffectViews on
// macOS 26 (tools/glass/reference builds it with a macOS 26 deployment target), the port's
// in Examples/Glass.

import AppKit

extension GlassReferenceScene {
    /// The scene's content view: the backdrop and the glass over it.
    @MainActor func makeContent() -> NSView {
        let root = NSView(frame: NSRect(origin: .zero, size: Self.size))
        root.addSubview(GlassReferenceBackdrop(frame: root.bounds, dark: self == .overDark))
        for s in Self.surfaces {
            let g = NSGlassEffectView(frame: s.frame)
            g.cornerRadius = s.radius
            g.style = s.clear ? .clear : .regular
            if s.tinted { g.tintColor = NSColor(srgbRed: 0, green: 0.48, blue: 1, alpha: 1) }
            root.addSubview(g)
        }
        return root
    }
}
