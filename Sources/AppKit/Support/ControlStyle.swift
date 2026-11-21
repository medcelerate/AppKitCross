// The opt-in macOS control look (ADR-0051).
//
// The port draws its own controls on every platform. By default they take the flatter,
// Windows-flavoured look the earlier PRs settled on (flat push buttons with a hairline,
// a plain 1-point text-field border, legacy scroll bars, controls that keep their accent
// colour in an inactive window). With `APPKITWIN_MAC_CONTROLS=1` in the environment, or
// `AppKitCrossMacControls` = YES in the Info.plist, the cells draw the way macOS draws
// them: shaded push-button bezels with a shadow, inset text-field bezels with the soft
// focus ring, tick-marked slider combs with the pill knob, overlay scrollers, narrow
// centred alerts with the icon and stacked buttons over a dimmed window, and accent
// colours that grey out when the window is not key.
//
// Apple has no public API for this (NSAppearance names are light/dark variants), so the
// switch is the port's own, in the spirit of the other `APPKITWIN_*` switches.

import Foundation

enum _NSControlStyle {
    /// Set by tests to force the look either way; nil reads the environment and Info.plist.
    nonisolated(unsafe) static var _override: Bool? = nil

    nonisolated(unsafe) private static var _resolved: Bool? = nil

    /// True when controls draw the macOS look.
    static var macControls: Bool {
        if let o = _override { return o }
        if let r = _resolved { return r }
        let r = _resolve()
        _resolved = r
        return r
    }

    private static func _resolve() -> Bool {
        if let v = ProcessInfo.processInfo.environment["APPKITWIN_MAC_CONTROLS"], !v.isEmpty {
            return v != "0" && v.lowercased() != "no" && v.lowercased() != "false"
        }
        if let v = _AppBundle.main.infoDictionary["AppKitCrossMacControls"] {
            if let b = v as? Bool { return b }
            if let s = v as? String { return s == "1" || s.uppercased() == "YES" || s.lowercased() == "true" }
            if let n = v as? NSNumber { return n.boolValue }
        }
        return false
    }

    /// Whether a view's window is key (an accent colour greys out otherwise under the
    /// macOS look). A view without a window, or one that is a sheet's parent, counts as active.
    @MainActor static func isActive(_ view: NSView?) -> Bool {
        guard macControls, let w = view?.window else { return true }
        return w.isKeyWindow || w.attachedSheet != nil
    }

    /// The grey that replaces the accent colour in an inactive window under the macOS look.
    static let inactiveAccent = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 0.5, alpha: 1) : NSColor(white: 0.72, alpha: 1)
    }
}
