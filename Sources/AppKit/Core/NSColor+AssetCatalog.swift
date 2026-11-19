// Colour sets from uncompiled asset catalogs, for NSColor(named:bundle:) (ADR-0038).
//
// On macOS actool compiles `*.xcassets` into Assets.car; SwiftPM on Windows and Linux copies
// the catalog as a resource directory instead. A colour set is `<name>.colorset/Contents.json`:
//
//   {"colors": [{"idiom": "universal", "color": {"color-space": "srgb",
//                 "components": {"red": "0.5", "green": "0x80", "blue": "128", "alpha": "1.000"}}},
//               {"idiom": "universal", "appearances": [{"appearance": "luminosity", "value": "dark"}],
//                "color": {...}}]}
//
// Components are floats ("0.500"), 8-bit integers ("128") or hex bytes ("0x80"); white-only
// spaces carry "white". Xcode's named system colours ("platform": "osx", "reference":
// "systemBlueColor") resolve to the port's system colours.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

enum _NSColorAssetCatalog {
    struct ColorSet { var light: NSColor; var dark: NSColor? }

    /// The colour set's light (any-appearance) colour and its dark variant, from the first
    /// catalog in the bundle's resources that has it.
    static func colorSet(named name: String, in bundle: Bundle) -> ColorSet? {
        guard let json = contents(of: name, in: bundle),
              let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let colors = root["colors"] as? [[String: Any]] else { return nil }
        var light: NSColor?, dark: NSColor?
        for entry in colors {
            guard let spec = entry["color"] as? [String: Any], let color = color(from: spec) else { continue }
            let appearances = (entry["appearances"] as? [[String: Any]]) ?? []
            let isDark = appearances.contains { ($0["appearance"] as? String) == "luminosity" && ($0["value"] as? String) == "dark" }
            let isOther = !appearances.isEmpty && !isDark   // high contrast and other variants
            if isDark { if dark == nil { dark = color } } else if !isOther, light == nil { light = color }
        }
        guard let light = light ?? dark else { return nil }
        return ColorSet(light: light, dark: dark === light ? nil : dark)
    }

    /// The colour set's Contents.json from the bundle's catalogs (the main bundle's search
    /// path of ADR-0045: Resources/, the executable target's SwiftPM bundle, its folder).
    private static func contents(of name: String, in bundle: Bundle) -> Data? {
        let roots = _AppBundle.forBundle(bundle).layout.resourceRoots
        guard let dir = _NSAssetCatalog.assetDirectory(named: name, kind: "colorset", roots: roots) else { return nil }
        return FileManager.default.contents(atPath: dir.appendingPathComponent("Contents.json").path)
    }

    private static func color(from spec: [String: Any]) -> NSColor? {
        if let reference = spec["reference"] as? String {
            return NSColor(catalogName: "System", colorName: reference) ?? NSColor(catalogName: "System", colorName: String(reference.dropLast(reference.hasSuffix("Color") ? 5 : 0)))
        }
        guard let comps = spec["components"] as? [String: Any] else { return nil }
        let alpha = component(comps["alpha"]) ?? 1
        if let white = component(comps["white"]) { return NSColor(white: white, alpha: alpha) }
        guard let r = component(comps["red"]), let g = component(comps["green"]), let b = component(comps["blue"]) else { return nil }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)
    }

    /// "0.5" → 0.5, "0x80" → 128/255, "128" → 128/255.
    static func component(_ value: Any?) -> CGFloat? {
        if let n = value as? NSNumber { return CGFloat(n.doubleValue) }
        guard let s = (value as? String)?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.lowercased().hasPrefix("0x") { return Int(s.dropFirst(2), radix: 16).map { CGFloat($0) / 255 } }
        if s.contains(".") { return Double(s).map { CGFloat($0) } }
        return Int(s).map { CGFloat($0) / 255 }
    }
}
