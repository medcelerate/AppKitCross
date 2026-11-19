// Uncompiled asset catalogs (ADR-0045): image sets, app icon sets and data sets for
// NSImage(named:), NSApplication's icon and NSDataAsset (colour sets: NSColor+AssetCatalog,
// ADR-0038).
//
// On macOS actool compiles `*.xcassets` into Assets.car. SwiftPM on Windows and Linux copies
// the catalog folder as it is (`.copy("Assets.xcassets")`, or `.process` of a folder), and the
// port reads it at run time: `<name>.imageset/Contents.json` lists one file per scale
// (`"scale": "2x"`), an `.appiconset` one file per point size and scale, a `.dataset` one data
// file with its UTI. Folders with `"provides-namespace": true` prefix their assets' names
// (`Icons/star`). Dark-appearance and idiom variants other than universal/mac are skipped.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

enum _NSAssetCatalog {
    /// The asset folder `<name>.<kind>` in the first catalog under the roots that has it.
    static func assetDirectory(named name: String, kind: String, roots: [URL]) -> URL? {
        let parts = name.split(separator: "/").map(String.init)
        guard let leaf = parts.last, !leaf.isEmpty else { return nil }
        let namespace = Array(parts.dropLast())
        for catalog in catalogs(in: roots) {
            if let hit = find(leaf + "." + kind, namespace: namespace, in: catalog) { return hit }
        }
        return nil
    }

    /// The image set (or app icon set) as an image with one representation per file.
    static func image(named name: String, roots: [URL]) -> NSImage? {
        if let dir = assetDirectory(named: name, kind: "imageset", roots: roots) { return imageSet(at: dir) }
        if let dir = assetDirectory(named: name, kind: "appiconset", roots: roots) { return appIconSet(at: dir) }
        return nil
    }

    /// The data set's file and its type identifier.
    static func data(named name: String, roots: [URL]) -> (data: Data, typeIdentifier: String)? {
        guard let dir = assetDirectory(named: name, kind: "dataset", roots: roots),
              let entries = contents(dir)?["data"] as? [[String: Any]] else { return nil }
        let pick = entries.first { ($0["idiom"] as? String).map { $0 == "universal" || $0 == "mac" } ?? true } ?? entries.first
        guard let file = pick?["filename"] as? String, let data = FileManager.default.contents(atPath: dir.appendingPathComponent(file).path) else { return nil }
        return (data, (pick?["universal-type-identifier"] as? String) ?? "public.data")
    }

    // MARK: Sets

    static func imageSet(at dir: URL) -> NSImage? {
        guard let root = contents(dir), let entries = root["images"] as? [[String: Any]] else { return nil }
        let usable = entries.filter { e in
            e["filename"] != nil && (e["appearances"] == nil) && ((e["idiom"] as? String).map { $0 == "universal" || $0 == "mac" } ?? true)
        }
        var reps: [(NSImageRep, CGFloat)] = []
        var vector: NSImage? = nil
        for e in usable {
            guard let file = e["filename"] as? String else { continue }
            let url = dir.appendingPathComponent(file)
            let ext = url.pathExtension.lowercased()
            if ext == "pdf" || ext == "svg" { if vector == nil { vector = NSImage(contentsOf: url) }; continue }
            guard let data = FileManager.default.contents(atPath: url.path), let rep = NSBitmapImageRep(data: data) else { continue }
            let scale = scaleValue(e["scale"] as? String) ?? 1
            rep.size = NSSize(width: CGFloat(rep.pixelsWide) / scale, height: CGFloat(rep.pixelsHigh) / scale)
            reps.append((rep, scale))
        }
        let image: NSImage
        if let vector, reps.isEmpty { image = vector }
        else {
            guard !reps.isEmpty else { return nil }
            let base = reps.min { $0.1 < $1.1 }!.0
            image = NSImage(size: base.size)
            for (rep, _) in reps.sorted(by: { $0.1 < $1.1 }) { image.addRepresentation(rep) }
        }
        if let props = root["properties"] as? [String: Any], (props["template-rendering-intent"] as? String) == "template" { image.isTemplate = true }
        return image
    }

    /// An app icon set: every file, each sized by its `size` (points); the image is the
    /// largest point size.
    static func appIconSet(at dir: URL) -> NSImage? {
        guard let entries = contents(dir)?["images"] as? [[String: Any]] else { return nil }
        var reps: [NSBitmapImageRep] = []
        for e in entries {
            guard let file = e["filename"] as? String, let data = FileManager.default.contents(atPath: dir.appendingPathComponent(file).path),
                  let rep = NSBitmapImageRep(data: data) else { continue }
            let scale = scaleValue(e["scale"] as? String) ?? 1
            let points = (e["size"] as? String).flatMap { Double($0.split(separator: "x").first ?? "") }.map { CGFloat($0) } ?? CGFloat(rep.pixelsWide) / scale
            rep.size = NSSize(width: points, height: points)
            if !reps.contains(where: { $0.pixelsWide == rep.pixelsWide && $0.size == rep.size }) { reps.append(rep) }
        }
        guard let largest = reps.max(by: { $0.size.width < $1.size.width }) else { return nil }
        let image = NSImage(size: largest.size)
        for rep in reps.sorted(by: { $0.pixelsWide < $1.pixelsWide }) { image.addRepresentation(rep) }
        return image
    }

    // MARK: Files

    private static func scaleValue(_ s: String?) -> CGFloat? {
        guard let s, let v = Double(s.trimmingCharacters(in: CharacterSet(charactersIn: "xX"))) else { return nil }
        return CGFloat(v)
    }

    private static func contents(_ dir: URL) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: dir.appendingPathComponent("Contents.json").path) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    nonisolated(unsafe) private static var catalogCache: [String: [URL]] = [:]
    private static let lock = NSLock()

    /// The `*.xcassets` folders under the roots, at most two folders down (an executable's
    /// folder under `swift build` holds thousands of build products; other roots and `.lproj`
    /// folders are not entered).
    static func catalogs(in roots: [URL]) -> [URL] {
        var out: [URL] = []
        let rootPaths = Set(roots.map { $0.standardizedFileURL.path })
        for root in roots {
            lock.lock()
            if let hit = catalogCache[root.path] { lock.unlock(); out += hit; continue }
            lock.unlock()
            var found: [URL] = []
            func walk(_ dir: URL, depth: Int) {
                for item in ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() {
                    let url = dir.appendingPathComponent(item, isDirectory: true)
                    if item.hasSuffix(".xcassets") { found.append(url); continue }
                    guard depth < 2, !item.hasPrefix("."), !item.hasSuffix(".lproj"), !item.hasSuffix(".build"), !item.hasSuffix(".swiftmodule"),
                          !item.hasSuffix(".dSYM"), item != "ModuleCache", !rootPaths.contains(url.standardizedFileURL.path),
                          _BundleLayout.isDirectory(url) else { continue }
                    walk(url, depth: depth + 1)
                }
            }
            walk(root, depth: 0)
            lock.lock(); catalogCache[root.path] = found; lock.unlock()
            out += found
        }
        return out
    }

    /// Searches a catalog folder for `target`, honouring namespaces: a folder whose
    /// Contents.json says `"provides-namespace": true` must be named in `namespace`.
    private static func find(_ target: String, namespace: [String], in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: dir.path) else { return nil }
        if namespace.isEmpty, items.contains(target) { return dir.appendingPathComponent(target, isDirectory: true) }
        for item in items.sorted() where !item.contains(".") || item.hasSuffix(".folder") {
            let sub = dir.appendingPathComponent(item, isDirectory: true)
            guard _BundleLayout.isDirectory(sub) else { continue }
            let providesNamespace = ((contents(sub)?["properties"] as? [String: Any])?["provides-namespace"] as? Bool) ?? false
            if providesNamespace {
                guard let first = namespace.first, first == item else { continue }
                if let hit = find(target, namespace: Array(namespace.dropFirst()), in: sub) { return hit }
            } else if let hit = find(target, namespace: namespace, in: sub) { return hit }
        }
        return nil
    }
}
