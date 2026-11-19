// The application's icon from its Info.plist (ADR-0045).
//
// `CFBundleIconName` names an app icon set (or image set) in an asset catalog, as Xcode writes
// it; `CFBundleIconFile` names a file in the resources (`AppIcon` finds AppIcon.png, then
// AppIcon.ico; an `.icns` stays unread, so ship a PNG beside it), or an asset of that name.
// NSApplication shows it as the windows' icon (title bar, taskbar, Alt-Tab, `_NET_WM_ICON`),
// and the registration of AppRegistration.swift points the shell at it.

import Foundation

@MainActor
enum _AppIcon {
    private static var loaded = false
    private static var cached: NSImage?

    /// The icon the Info.plist declares, nil when it declares none that can be read.
    static func bundleIcon(_ app: _AppBundle = .main) -> NSImage? {
        if app === _AppBundle.main {
            if loaded { return cached }
            loaded = true
            cached = load(app)
            return cached
        }
        return load(app)
    }

    static func load(_ app: _AppBundle) -> NSImage? {
        let info = app.infoDictionary
        let roots = app.layout.resourceRoots
        if let name = info["CFBundleIconName"] as? String, let image = _NSAssetCatalog.image(named: name, roots: roots) { return image }
        guard let file = info["CFBundleIconFile"] as? String, !file.isEmpty else { return nil }
        let ns = file as NSString
        let base = ns.pathExtension.isEmpty ? file : ns.deletingPathExtension
        var exts = ["png", "ico", "bmp"]
        if !ns.pathExtension.isEmpty, ns.pathExtension.lowercased() != "icns" { exts.insert(ns.pathExtension, at: 0) }
        for ext in exts {
            if let url = app.url(forResource: base, withExtension: ext), let image = NSImage(contentsOf: url), image.isValid { return image }
        }
        return _NSAssetCatalog.image(named: base, roots: roots)
    }

    /// The icon file the shell can show itself: on Windows the `.ico` `CFBundleIconFile` names
    /// (else nil, and the registration uses the executable's own icon resource).
    static func iconFilePath(_ app: _AppBundle = .main) -> String? {
        #if os(Windows)
        guard let file = app.infoDictionary["CFBundleIconFile"] as? String, !file.isEmpty else { return nil }
        let base = ((file as NSString).pathExtension.isEmpty ? file : (file as NSString).deletingPathExtension)
        return app.url(forResource: base, withExtension: "ico")?.path
        #else
        return nil
        #endif
    }

    /// The icon as PNG data, from the representation closest to `size` pixels (at least it).
    static func pngData(size: Int) -> Data? {
        guard let image = NSApplication._shared?._applicationIconImageIfSet ?? bundleIcon() else { return nil }
        let bitmaps = image.representations.compactMap { $0 as? NSBitmapImageRep }
        let pick = bitmaps.filter { $0.pixelsWide >= size }.min { $0.pixelsWide < $1.pixelsWide } ?? bitmaps.max { $0.pixelsWide < $1.pixelsWide }
        if let pick, let png = pick.representation(using: .png, properties: [:]) { return png }
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}
