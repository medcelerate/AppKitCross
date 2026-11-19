// The application's bundle on Windows and Linux (ADR-0045).
//
// An app is a folder: the executable, its runtime libraries, and its resources beside it.
//
//     MyApp/
//       MyApp.exe (MyApp on Linux)
//       Info.plist                  optional here, in Resources/, or in the executable's
//                                   SwiftPM bundle (Resources/Info.plist or MyApp-Info.plist)
//       Resources/                  optional: what Contents/Resources holds on macOS
//         AppIcon.png / .ico, Assets.xcassets, en.lproj/Localizable.strings, ...
//       MyPkg_MyApp.resources/      SwiftPM's resource bundle of each target, as `swift build`
//                                   lays it out (Bundle.module finds them next to the exe)
//
// swift-corelibs-foundation already makes the executable's folder `Bundle.main` (a "flat"
// bundle: Info.plist and resources directly in it), which keeps working. What it lacks the
// port adds: `Resources/` and the executable target's own SwiftPM bundle are searched too
// (so `Bundle.main.url(forResource:)`, `NSImage(named:)` and `NSLocalizedString` find what
// SwiftPM copied, under `swift run` and in a shipped folder alike), the Info.plist can live
// in those places, localization follows the user's languages, and `.stringsdict` and String
// Catalogs work. `Bundle.main` stays corelibs' object; its members are routed to `_AppBundle`
// through Bundle's vtable (BundleHooks.swift).

import Foundation

/// Where a bundle's files are (port only).
public struct _BundleLayout: Sendable {
    /// `Bundle.bundleURL`: the executable's folder for the application.
    public let bundleURL: URL
    /// Searched in order for resources, `.lproj` folders and asset catalogs.
    public let resourceRoots: [URL]
    /// The Info.plist in use, if any.
    public let infoPlistURL: URL?
    /// The executable's name without `.exe`.
    public let executableName: String?

    /// The application's layout around its executable. `APPKITWIN_INFO_PLIST` names an
    /// Info.plist anywhere (a bare `swift run`).
    public init(executableURL: URL, environment: [String: String] = ProcessInfo.processInfo.environment) {
        let exe = executableURL.standardizedFileURL
        let dir = exe.deletingLastPathComponent()
        var name = exe.lastPathComponent
        if name.lowercased().hasSuffix(".exe") { name.removeLast(4) }
        executableName = name
        bundleURL = dir
        var roots: [URL] = []
        let resources = dir.appendingPathComponent("Resources", isDirectory: true)
        if _BundleLayout.isDirectory(resources) { roots.append(resources) }
        // The executable target's SwiftPM bundle (`<Package>_<Target>.resources`; Bundle.module
        // inside the app's own code), and a `.copy("Resources")` folder inside it.
        let items = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
        // (`.bundle` on macOS, where SwiftPM makes its resource bundles bundles.)
        for item in items where item.hasSuffix("_\(name).resources") || item == "\(name).resources" || item.hasSuffix("_\(name).bundle") {
            let module = dir.appendingPathComponent(item, isDirectory: true)
            let inner = module.appendingPathComponent("Resources", isDirectory: true)
            if _BundleLayout.isDirectory(inner) { roots.append(inner) }
            roots.append(module)
        }
        roots.append(dir)
        var plist: URL? = nil
        if let p = environment["APPKITWIN_INFO_PLIST"], !p.isEmpty, FileManager.default.fileExists(atPath: p) {
            plist = URL(fileURLWithPath: p)
            // The named Info.plist's folder holds the app's other files too (its icon).
            let folder = plist!.deletingLastPathComponent().standardizedFileURL
            if !roots.contains(where: { $0.standardizedFileURL == folder }) { roots.append(folder) }
        }
        if plist == nil {
            outer: for root in roots {
                for file in ["Info.plist", "\(name)-Info.plist"] where FileManager.default.fileExists(atPath: root.appendingPathComponent(file).path) {
                    plist = root.appendingPathComponent(file); break outer
                }
            }
        }
        infoPlistURL = plist
        resourceRoots = roots
    }

    /// Any other bundle (a SwiftPM `.resources` folder, a macOS-style `.bundle` or `.app`):
    /// `Contents/Resources` or `Resources` when present, then the folder itself.
    public init(bundleURL url: URL) {
        bundleURL = url
        executableName = nil
        var roots: [URL] = []
        for sub in ["Contents/Resources", "Resources"] {
            let r = url.appendingPathComponent(sub, isDirectory: true)
            if _BundleLayout.isDirectory(r) { roots.append(r) }
        }
        roots.append(url)
        resourceRoots = roots
        infoPlistURL = ["Contents/Info.plist", "Resources/Info.plist", "Info.plist"].map { url.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func isDirectory(_ url: URL) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue
    }
}

/// A bundle's resources, Info.plist and localizations, as the port answers them (port only;
/// apps use `Bundle`).
public final class _AppBundle: @unchecked Sendable {
    public let layout: _BundleLayout
    private let lock = NSRecursiveLock()
    private var _info: [String: Any]?
    private var _localizations: [String]?

    public init(layout: _BundleLayout) { self.layout = layout }

    /// The application's: laid out around the main executable.
    public static let main = _AppBundle(layout: _BundleLayout(executableURL: mainExecutableURL))

    /// The bundle at a URL (cached), or `main` for the main bundle's folder.
    public static func forBundle(_ bundle: Bundle) -> _AppBundle {
        let url = bundle.bundleURL.standardizedFileURL
        if bundle === Bundle.main || url == main.layout.bundleURL { return main }
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let hit = others[url.path] { return hit }
        let made = _AppBundle(layout: _BundleLayout(bundleURL: url))
        others[url.path] = made
        return made
    }
    nonisolated(unsafe) private static var others: [String: _AppBundle] = [:]
    private static let cacheLock = NSLock()

    /// The running executable (corelibs' `Bundle.main.executableURL`, else argv[0]).
    static var mainExecutableURL: URL {
        if let u = Bundle.main.executableURL { return u }
        let arg0 = CommandLine.arguments.first ?? ""
        return URL(fileURLWithPath: arg0).standardizedFileURL
    }

    // MARK: Info.plist

    /// The Info.plist with the keys a bare executable lacks filled in from its name:
    /// `CFBundleExecutable`, `CFBundleName`, `CFBundleDevelopmentRegion` (`en`),
    /// `CFBundleInfoDictionaryVersion`. No `CFBundleIdentifier` is made up (macOS has none
    /// for a bare executable either).
    public var infoDictionary: [String: Any] {
        lock.lock(); defer { lock.unlock() }
        if let _info { return _info }
        var info: [String: Any] = [:]
        if let url = layout.infoPlistURL, let data = FileManager.default.contents(atPath: url.path),
           let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] {
            info = plist
        }
        if let name = layout.executableName {
            if info["CFBundleExecutable"] == nil { info["CFBundleExecutable"] = name }
            if info["CFBundleName"] == nil { info["CFBundleName"] = name }
        }
        if info["CFBundleDevelopmentRegion"] == nil { info["CFBundleDevelopmentRegion"] = "en" }
        if info["CFBundleInfoDictionaryVersion"] == nil { info["CFBundleInfoDictionaryVersion"] = "6.0" }
        _info = info
        return info
    }

    public var bundleIdentifier: String? { infoDictionary["CFBundleIdentifier"] as? String }

    /// The Info.plist's values with `InfoPlist.strings` of the preferred localization over
    /// them (`localizedInfoDictionary` answers only the localized keys, as macOS).
    public var localizedInfoDictionary: [String: Any] {
        let table = localizedTable("InfoPlist")
        return table.mapValues { $0.unformatted }
    }

    public func object(forInfoDictionaryKey key: String) -> Any? {
        if let localized = localizedTable("InfoPlist")[key] { return localized.unformatted }
        return infoDictionary[key]
    }

    /// The name to show for the application: `CFBundleDisplayName`, `CFBundleName`, else the
    /// executable's name (localized when `InfoPlist.strings` has them).
    public var displayName: String {
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let s = object(forInfoDictionaryKey: key) as? String, !s.isEmpty { return s }
        }
        return layout.executableName ?? ProcessInfo.processInfo.processName
    }

    /// The application's identity on the platform: `CFBundleIdentifier`, else
    /// `AppKitCross.<executable>` (as UserNotifications names the AUMID). The Wayland app id,
    /// the X11 `WM_CLASS`, the desktop entry, the ProgIDs and the single-instance channel are
    /// keyed by it.
    public var platformIdentifier: String {
        if let id = bundleIdentifier, !id.isEmpty { return id }
        return "AppKitCross." + (layout.executableName ?? ProcessInfo.processInfo.processName)
    }

    // MARK: Localizations

    public var developmentLocalization: String { (infoDictionary["CFBundleDevelopmentRegion"] as? String) ?? "en" }

    /// The `.lproj` folders' names across the roots (plus String Catalog languages), sorted.
    public var localizations: [String] {
        lock.lock(); defer { lock.unlock() }
        if let _localizations { return _localizations }
        var found = Set<String>()
        for root in layout.resourceRoots {
            for item in (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [] {
                if item.hasSuffix(".lproj") { found.insert(String(item.dropLast(6))) }
                if item.hasSuffix(".xcstrings"), let data = FileManager.default.contents(atPath: root.appendingPathComponent(item).path),
                   let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    if let source = json["sourceLanguage"] as? String { found.insert(source) }
                    for case let entry as [String: Any] in ((json["strings"] as? [String: Any]) ?? [:]).values {
                        for loc in ((entry["localizations"] as? [String: Any]) ?? [:]).keys { found.insert(loc) }
                    }
                }
            }
        }
        if let declared = infoDictionary["CFBundleLocalizations"] as? [String] { found.formUnion(declared) }
        let list = found.sorted()
        _localizations = list
        return list
    }

    /// The localization the user's languages pick among this bundle's.
    public var preferredLocalizations: [String] {
        _LocalizationMatching.preferred(from: localizations, preferences: _PreferredLanguages.current, development: developmentLocalization)
    }

    /// The localizations a lookup tries in order: the preferred one, the development one, Base.
    var lookupLocalizations: [String] {
        var out: [String] = []
        for l in preferredLocalizations + [developmentLocalization, "Base"] where !out.contains(l) { out.append(l) }
        return out
    }

    /// The table's entries for the preferred localization, with the fallbacks' entries under them.
    func localizedTable(_ name: String) -> [String: _LocalizedEntry] {
        var merged: [String: _LocalizedEntry] = [:]
        for loc in lookupLocalizations.reversed() {
            for (k, v) in _LocalizationTables.table(name, localization: loc, roots: layout.resourceRoots, sourceLanguage: developmentLocalization) { merged[k] = v }
        }
        return merged
    }

    /// The table entry for `key`: the preferred localization's, falling back to the
    /// development localization's and Base's.
    public func localizedEntry(forKey key: String, table: String?) -> _LocalizedEntry? {
        let name = (table?.isEmpty == false ? table! : "Localizable")
        for loc in lookupLocalizations {
            if let hit = _LocalizationTables.table(name, localization: loc, roots: layout.resourceRoots, sourceLanguage: developmentLocalization)[key] { return hit }
        }
        return nil
    }

    /// `Bundle.localizedString(forKey:value:table:)`: the entry (a `.stringsdict` entry's
    /// variables in their `other` form, positions made explicit), else `value`, else the key.
    public func localizedString(forKey key: String, value: String?, table: String?) -> String {
        if let entry = localizedEntry(forKey: key, table: table) { return entry.unformatted }
        if let value, !value.isEmpty { return value }
        return key
    }

    /// The entry formatted with arguments, plural variables chosen by their values.
    public func localizedString(forKey key: String, defaultValue: String?, table: String?, locale: Locale?, arguments: [CVarArg]) -> String {
        let language = preferredLocalizations.first ?? developmentLocalization
        let entry = localizedEntry(forKey: key, table: table) ?? .string(defaultValue ?? key)
        return _PluralFormat.format(entry, language: language, locale: locale, arguments: arguments)
    }

    // MARK: Resources

    /// `Bundle.url(forResource:withExtension:subdirectory:localization:)`: each root's
    /// unlocalized resources first, then its `.lproj` folders in preference order.
    public func url(forResource name: String?, withExtension ext: String?, subdirectory: String? = nil, localization: String? = nil) -> URL? {
        guard let name, !name.isEmpty else { return urls(forResourcesWithExtension: ext, subdirectory: subdirectory, localization: localization).first }
        let file = (ext?.isEmpty == false) ? name + "." + ext!.trimmingCharacters(in: CharacterSet(charactersIn: ".")) : name
        let fm = FileManager.default
        let lprojs = localization.map { [$0] } ?? lookupLocalizations
        for root in layout.resourceRoots {
            var dir = root
            if let subdirectory, !subdirectory.isEmpty { dir = dir.appendingPathComponent(subdirectory, isDirectory: true) }
            if localization == nil {
                let u = dir.appendingPathComponent(file)
                if fm.fileExists(atPath: u.path) { return u }
            }
            for loc in lprojs {
                var u = root.appendingPathComponent(loc + ".lproj", isDirectory: true)
                if let subdirectory, !subdirectory.isEmpty { u = u.appendingPathComponent(subdirectory, isDirectory: true) }
                u = u.appendingPathComponent(file)
                if fm.fileExists(atPath: u.path) { return u }
            }
        }
        return nil
    }

    public func urls(forResourcesWithExtension ext: String?, subdirectory: String? = nil, localization: String? = nil) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        var seen = Set<String>()
        let wanted = ext.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() }
        func collect(_ dir: URL) {
            for item in ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() {
                if item.hasSuffix(".lproj") { continue }
                if let wanted, !wanted.isEmpty, (item as NSString).pathExtension.lowercased() != wanted { continue }
                if seen.insert(item).inserted { out.append(dir.appendingPathComponent(item)) }
            }
        }
        let lprojs = localization.map { [$0] } ?? lookupLocalizations
        for root in layout.resourceRoots {
            if localization == nil { collect(subdirectory.map { root.appendingPathComponent($0, isDirectory: true) } ?? root) }
            for loc in lprojs {
                let l = root.appendingPathComponent(loc + ".lproj", isDirectory: true)
                collect(subdirectory.map { l.appendingPathComponent($0, isDirectory: true) } ?? l)
            }
        }
        return out
    }

    /// `Bundle.resourceURL`: `Resources/` when the app has one, else the executable target's
    /// SwiftPM bundle, else the bundle folder.
    public var resourceURL: URL { layout.resourceRoots.first ?? layout.bundleURL }

    // MARK: Bundle.main

    /// Makes corelibs' `Bundle` answer through the port (Windows and Linux; a no-op on
    /// macOS): see `BundleHooks.swift`. Called when `NSApplication.shared` is first made and
    /// before the port's own lookups; code that runs before then gets corelibs' answers.
    public static func installMainBundle() {
        #if os(Windows) || os(Linux)
        installLock.lock(); defer { installLock.unlock() }
        guard !installTried else { return }
        installTried = true
        if !_BundleHooks.install(), ProcessInfo.processInfo.environment["APPKITWIN_CORELIBS_BUNDLE"] != "1" {
            FileHandle.standardError.write(Data("AppKitCross: Bundle stays corelibs' (\(_BundleHooks.installFailure ?? "unknown")); NSLocalizedString answers in the development language\n".utf8))
        }
        #endif
    }
    nonisolated(unsafe) private static var installTried = false
    private static let installLock = NSLock()

    /// Whether `Bundle` answers through the port.
    public static var isMainBundleInstalled: Bool {
        #if os(Windows) || os(Linux)
        return _BundleHooks.isInstalled
        #else
        return false
        #endif
    }
}
