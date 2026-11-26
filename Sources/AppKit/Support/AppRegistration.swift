// Registering the application's document types and URL schemes with the desktop (ADR-0045).
//
// macOS registers an app's `CFBundleDocumentTypes` and `CFBundleURLTypes` when LaunchServices
// first sees the bundle. Windows and Linux have no such scan, so the port writes the
// registration on request: per user, never at an ordinary launch.
//
//   Windows (HKCU\Software\Classes, no administrator rights): a ProgID per document type
//   (`<identity>.<Type>`: name, DefaultIcon, shell\open\command `"exe" "%1"`), the type's
//   extensions' OpenWithProgids (never the extension's default or its Content Type: those are
//   the user's and the system's), Applications\<exe> with SupportedTypes, a Capabilities
//   key listed under RegisteredApplications (what Settings > Default apps offers), and each URL
//   scheme's key when no other application owns it, every path with backslashes and every
//   DefaultIcon with its index (`"…\\AppIcon.ico",0`). Then SHChangeNotify(SHCNE_ASSOCCHANGED).
//   Windows 10 and later leave the default choice to the user (UserChoice): the app becomes a
//   listed handler, not silently the default.
//
//   Linux (XDG): `~/.local/share/applications/<identity>.desktop` with `MimeType=` the types'
//   MIME types and `x-scheme-handler/<scheme>`, `Exec` with `%F` (or `%U` with schemes),
//   `StartupWMClass` (the window's WM_CLASS) and the icon written as a PNG under
//   `~/.local/share/icons/hicolor/256x256/apps/<identity>.png`; a shared-mime-info package
//   `~/.local/share/mime/packages/<identity>.xml` for extensions no MIME type covers and the
//   exported/imported UTI declarations; then `update-mime-database`/`update-desktop-database`
//   when installed, and `xdg-mime default` for Owner types nothing else is the default for.
//
// Who asks: `NSWorkspace._registerApplication()` (port only), the command line
// (`MyApp --appkitcross-register`, `--appkitcross-unregister`: registers, prints what it did,
// exits; for installers and the app-folder layout tool), or the Info.plist
// (`AppKitCrossRegistersFileTypes` = YES: at each launch, when the registration is missing or
// names another executable).

import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// What to register, computed from the Info.plist (port only; the platforms apply it).
public struct _AppRegistration: Equatable, Sendable {
    public struct DocumentType: Equatable, Sendable {
        public var name: String
        public var role: String
        public var rank: String
        public var extensions: [String]
        public var mimeTypes: [String]
        /// The ProgID (Windows).
        public var progID: String
        /// The type's own icon file, when it names one that exists.
        public var iconPath: String?
    }
    public struct URLScheme: Equatable, Sendable {
        public var name: String
        public var schemes: [String]
    }
    /// A MIME type the port declares itself (shared-mime-info), for extensions nothing covers.
    public struct MIMEDeclaration: Equatable, Sendable {
        public var type: String
        public var comment: String
        public var globs: [String]
        public var parent: String?
    }

    public var identifier: String
    public var displayName: String
    public var executablePath: String
    /// The application icon file to point at (an .ico on Windows, a PNG on Linux), if any.
    public var iconPath: String?
    public var documentTypes: [DocumentType]
    public var urlSchemes: [URLScheme]
    public var mimeDeclarations: [MIMEDeclaration]
    /// The XDG category from `LSApplicationCategoryType`.
    public var category: String?

    public init(app: _AppBundle = .main, executablePath: String) {
        let info = app.infoDictionary
        identifier = app.platformIdentifier
        displayName = app.displayName
        self.executablePath = executablePath
        let declarations = _AppRegistration.typeDeclarations(info)
        var docs: [DocumentType] = []
        var declaredMIME: [MIMEDeclaration] = []
        for (index, entry) in ((info["CFBundleDocumentTypes"] as? [[String: Any]]) ?? []).enumerated() {
            let role = (entry["CFBundleTypeRole"] as? String) ?? "Editor"
            if role == "None" { continue }
            let utis = (entry["LSItemContentTypes"] as? [String]) ?? []
            var exts = ((entry["CFBundleTypeExtensions"] as? [String]) ?? []).map { $0.lowercased() }.filter { $0 != "*" && !$0.isEmpty }
            var mimes = (entry["CFBundleTypeMIMETypes"] as? [String]) ?? []
            for uti in utis {
                if let d = declarations[uti] { exts += d.extensions; mimes += d.mimeTypes; continue }
                let (e, m) = _AppRegistration.systemTags(uti)
                exts += e; mimes += m
            }
            exts = _AppRegistration.unique(exts.map { $0.lowercased() })
            mimes = _AppRegistration.unique(mimes)
            let name = (entry["CFBundleTypeName"] as? String) ?? utis.first ?? exts.first ?? "Document"
            // Extensions without a MIME type get one of the app's own on Linux.
            if mimes.isEmpty, !exts.isEmpty {
                let t = "application/x-" + _AppRegistration.token(identifier) + "-" + _AppRegistration.token(name)
                declaredMIME.append(MIMEDeclaration(type: t, comment: name, globs: exts.map { "*." + $0 }, parent: nil))
                mimes = [t]
            }
            let icon = (entry["CFBundleTypeIconFile"] as? String).flatMap { _AppRegistration.iconFile($0, in: app) }
            var progID = identifier + "." + _AppRegistration.token(name, keepCase: true)
            if docs.contains(where: { $0.progID == progID }) { progID += "\(index + 1)" }
            docs.append(DocumentType(name: name, role: role, rank: (entry["LSHandlerRank"] as? String) ?? "Default", extensions: exts, mimeTypes: mimes,
                                     progID: progID, iconPath: icon))
        }
        // Declared UTIs with MIME types the shared database may not know (exported ones especially).
        for (uti, d) in declarations.sorted(by: { $0.key < $1.key }) where d.exported || !d.mimeTypes.isEmpty {
            guard let mime = d.mimeTypes.first, !d.extensions.isEmpty else { continue }
            if !declaredMIME.contains(where: { $0.type == mime }) {
                declaredMIME.append(MIMEDeclaration(type: mime, comment: d.description ?? uti, globs: d.extensions.map { "*." + $0 }, parent: d.parentMIME))
            }
        }
        documentTypes = docs
        mimeDeclarations = declaredMIME
        let id = identifier
        urlSchemes = ((info["CFBundleURLTypes"] as? [[String: Any]]) ?? []).compactMap { e in
            let schemes = ((e["CFBundleURLSchemes"] as? [String]) ?? []).map { $0.lowercased() }
            return schemes.isEmpty ? nil : URLScheme(name: (e["CFBundleURLName"] as? String) ?? id, schemes: schemes)
        }
        iconPath = nil
        category = (info["LSApplicationCategoryType"] as? String).flatMap(_AppRegistration.xdgCategory)
    }

    // MARK: Windows

    /// One registry value under HKEY_CURRENT_USER.
    public struct RegistryValue: Equatable, Sendable {
        public enum Condition: Equatable, Sendable {
            case always
            /// Only when the value does not exist yet (nothing else claims it).
            case ifAbsent
        }
        public var key: String
        /// nil: the key's default value.
        public var name: String?
        public var value: String
        public var condition: Condition = .always
    }

    /// `"C:\path\App.exe" "%1"`.
    /// A path as the registry and the shell need it: backslashes (Foundation's URL paths on
    /// Windows use forward slashes, which `AssocQueryString` and ShellExecute reject).
    static func windowsPath(_ path: String) -> String {
        var p = path.replacingOccurrences(of: "/", with: "\\")
        // "/C:/x" (a URL path) → "C:\x"
        if p.hasPrefix("\\"), p.count > 2, Array(p)[2] == ":" { p.removeFirst() }
        return p
    }
    var windowsExecutablePath: String { _AppRegistration.windowsPath(executablePath) }
    public var windowsOpenCommand: String { "\"\(windowsExecutablePath)\" \"%1\"" }
    var windowsExecutableName: String { (executablePath.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent }
    /// A DefaultIcon value: the file and its icon index.
    static func windowsIconLocation(_ path: String) -> String { "\"\(windowsPath(path))\",0" }
    public var windowsCapabilitiesKey: String { "Software\\AppKitCross\\\(identifier)\\Capabilities" }
    var windowsIcon: String { _AppRegistration.windowsIconLocation(iconPath ?? executablePath) }

    /// Every value the registration writes, in order (keys are created as needed).
    public var windowsRegistryValues: [RegistryValue] {
        let classes = "Software\\Classes\\"
        var out: [RegistryValue] = []
        for t in documentTypes {
            let p = classes + t.progID
            out.append(RegistryValue(key: p, name: nil, value: t.name))
            out.append(RegistryValue(key: p, name: "FriendlyTypeName", value: t.name))
            out.append(RegistryValue(key: p + "\\DefaultIcon", name: nil, value: t.iconPath.map(_AppRegistration.windowsIconLocation) ?? windowsIcon))
            out.append(RegistryValue(key: p + "\\shell\\open\\command", name: nil, value: windowsOpenCommand))
            // Only offered (Open With, Default apps): the extension's default and its Content
            // Type are the user's and the system's to set.
            for ext in t.extensions {
                out.append(RegistryValue(key: classes + "." + ext + "\\OpenWithProgids", name: t.progID, value: ""))
            }
        }
        let app = classes + "Applications\\" + windowsExecutableName
        out.append(RegistryValue(key: app, name: "FriendlyAppName", value: displayName))
        out.append(RegistryValue(key: app + "\\DefaultIcon", name: nil, value: windowsIcon))
        out.append(RegistryValue(key: app + "\\shell\\open\\command", name: nil, value: windowsOpenCommand))
        for ext in documentTypes.flatMap(\.extensions) { out.append(RegistryValue(key: app + "\\SupportedTypes", name: "." + ext, value: "")) }
        for s in urlSchemes {
            for scheme in s.schemes {
                let k = classes + scheme
                out.append(RegistryValue(key: k, name: nil, value: "URL:\(s.name)"))
                out.append(RegistryValue(key: k, name: "URL Protocol", value: ""))
                out.append(RegistryValue(key: k + "\\DefaultIcon", name: nil, value: windowsIcon))
                out.append(RegistryValue(key: k + "\\shell\\open\\command", name: nil, value: windowsOpenCommand))
            }
        }
        let caps = windowsCapabilitiesKey
        out.append(RegistryValue(key: caps, name: "ApplicationName", value: displayName))
        out.append(RegistryValue(key: caps, name: "ApplicationDescription", value: displayName))
        out.append(RegistryValue(key: caps, name: "ApplicationIcon", value: windowsIcon))
        for t in documentTypes { for ext in t.extensions { out.append(RegistryValue(key: caps + "\\FileAssociations", name: "." + ext, value: t.progID)) } }
        for s in urlSchemes { for scheme in s.schemes { out.append(RegistryValue(key: caps + "\\URLAssociations", name: scheme, value: scheme)) } }
        out.append(RegistryValue(key: "Software\\RegisteredApplications", name: identifier, value: caps))
        return out
    }

    /// The keys the registration owns outright (removed on unregistering). URL scheme keys
    /// are removed only when their command is this executable's (checked by the platform).
    public var windowsOwnedKeys: [String] {
        documentTypes.map { "Software\\Classes\\" + $0.progID }
            + ["Software\\Classes\\Applications\\" + windowsExecutableName, "Software\\AppKitCross\\" + identifier]
    }
    public var windowsSchemeKeys: [String] { urlSchemes.flatMap(\.schemes).map { "Software\\Classes\\" + $0 } }

    // MARK: Linux

    public var desktopFileName: String { identifier + ".desktop" }

    /// The desktop entry (freedesktop Desktop Entry Specification 1.5).
    public func desktopEntry(iconPath: String?) -> String {
        var mime = documentTypes.flatMap(\.mimeTypes)
        mime += urlSchemes.flatMap(\.schemes).map { "x-scheme-handler/" + $0 }
        mime = _AppRegistration.unique(mime)
        let field = urlSchemes.isEmpty ? "%F" : "%U"
        var lines = [
            "[Desktop Entry]",
            "Type=Application",
            "Version=1.5",
            "Name=" + _AppRegistration.desktopEscape(displayName),
            "Exec=" + _AppRegistration.execQuote(executablePath) + " " + field,
            "TryExec=" + _AppRegistration.desktopEscape(executablePath),
            "Terminal=false",
            "StartupWMClass=" + identifier,
        ]
        if let iconPath { lines.append("Icon=" + _AppRegistration.desktopEscape(iconPath)) }
        if !mime.isEmpty { lines.append("MimeType=" + mime.joined(separator: ";") + ";") }
        lines.append("Categories=" + (category.map { $0 + ";" } ?? "") + (category == "Utility" ? "" : "Utility;"))
        lines.append("X-AppKitCross-Identifier=" + identifier)
        return lines.joined(separator: "\n") + "\n"
    }

    /// The shared-mime-info package, nil when there is nothing to declare.
    public var mimePackage: String? {
        guard !mimeDeclarations.isEmpty else { return nil }
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<mime-info xmlns=\"http://www.freedesktop.org/standards/shared-mime-info\">\n"
        for d in mimeDeclarations {
            xml += "  <mime-type type=\"\(_AppRegistration.xmlEscape(d.type))\">\n"
            xml += "    <comment>\(_AppRegistration.xmlEscape(d.comment))</comment>\n"
            if let parent = d.parent { xml += "    <sub-class-of type=\"\(_AppRegistration.xmlEscape(parent))\"/>\n" }
            for g in d.globs { xml += "    <glob pattern=\"\(_AppRegistration.xmlEscape(g))\"/>\n" }
            xml += "  </mime-type>\n"
        }
        return xml + "</mime-info>\n"
    }

    /// MIME types whose default handler the app should become when none is set (Owner rank).
    public var ownedMIMETypes: [String] {
        _AppRegistration.unique(documentTypes.filter { $0.rank == "Owner" }.flatMap(\.mimeTypes) + urlSchemes.flatMap(\.schemes).map { "x-scheme-handler/" + $0 })
    }

    // MARK: Helpers

    struct Declaration { var extensions: [String]; var mimeTypes: [String]; var description: String?; var exported: Bool; var parentMIME: String? }

    static func typeDeclarations(_ info: [String: Any]) -> [String: Declaration] {
        var out: [String: Declaration] = [:]
        for key in ["UTImportedTypeDeclarations", "UTExportedTypeDeclarations"] {
            for decl in (info[key] as? [[String: Any]]) ?? [] {
                guard let id = decl["UTTypeIdentifier"] as? String else { continue }
                let tags = decl["UTTypeTagSpecification"] as? [String: Any]
                func list(_ k: String) -> [String] { (tags?[k] as? [String]) ?? (tags?[k] as? String).map { [$0] } ?? [] }
                let parents = (decl["UTTypeConformsTo"] as? [String]) ?? []
                let parentMIME = parents.lazy.compactMap { systemTags($0).1.first }.first
                out[id] = Declaration(extensions: list("public.filename-extension").map { $0.lowercased() }, mimeTypes: list("public.mime-type"),
                                      description: decl["UTTypeDescription"] as? String, exported: key == "UTExportedTypeDeclarations", parentMIME: parentMIME)
            }
        }
        return out
    }

    /// A system UTI's extensions and MIME types (UTType's own tables).
    static func systemTags(_ uti: String) -> ([String], [String]) {
        #if canImport(UniformTypeIdentifiers)
        guard let t = UTType(uti), !t.isDynamic else { return ([], []) }
        let exts = t.tags[.filenameExtension] ?? []
        let mimes = t.tags[.mimeType] ?? []
        return (exts, mimes)
        #else
        return ([], [])
        #endif
    }

    static func iconFile(_ name: String, in app: _AppBundle) -> String? {
        let ns = name as NSString
        if !ns.pathExtension.isEmpty, let u = app.url(forResource: ns.deletingPathExtension, withExtension: ns.pathExtension) { return u.path }
        #if os(Windows)
        let exts = ["ico", "png"]
        #else
        let exts = ["png", "svg", "ico"]
        #endif
        for ext in exts { if let u = app.url(forResource: name, withExtension: ext) { return u.path } }
        return nil
    }

    static func unique(_ a: [String]) -> [String] { var seen = Set<String>(); return a.filter { seen.insert($0).inserted } }

    /// Letters and digits only (`Markdown Document` → `markdown-document`, or `MarkdownDocument`).
    static func token(_ s: String, keepCase: Bool = false) -> String {
        var out = ""
        var dash = false
        for c in s.unicodeScalars {
            if c.isASCII, CharacterSet.alphanumerics.contains(c) || c == "." {
                out.unicodeScalars.append(keepCase ? c : Unicode.Scalar(String(c).lowercased())!)
                dash = false
            } else if !dash, !out.isEmpty, !keepCase { out += "-"; dash = true }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "document" : out
    }

    static func desktopEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t")
    }
    /// An Exec argument: quoted, with `"`, `` ` ``, `$` and `\` escaped, then the value escaped.
    static func execQuote(_ s: String) -> String {
        var q = ""
        for c in s {
            if c == "\"" || c == "`" || c == "$" || c == "\\" { q.append("\\") }
            q.append(c)
        }
        return desktopEscape("\"" + q + "\"")
    }
    static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// `public.app-category.productivity` → `Office`, and the other XDG main categories.
    static func xdgCategory(_ apple: String) -> String? {
        let map: [String: String] = [
            "productivity": "Office", "business": "Office", "finance": "Office", "developer-tools": "Development",
            "graphics-design": "Graphics", "photography": "Graphics", "music": "AudioVideo", "video": "AudioVideo",
            "entertainment": "AudioVideo", "education": "Education", "games": "Game", "utilities": "Utility",
            "social-networking": "Network", "news": "Network", "reference": "Education", "medical": "Science",
            "healthcare-fitness": "Utility", "lifestyle": "Utility", "travel": "Utility", "weather": "Utility", "sports": "Utility",
        ]
        let last = apple.replacingOccurrences(of: "public.app-category.", with: "")
        if let m = map[last] { return m }
        if last.hasSuffix("-games") { return "Game" }
        return nil
    }
}

/// Writes the XDG side of a registration under a data home (`~/.local/share`): the desktop
/// entry, the icon and the MIME package. Portable so the tests can run it anywhere; the Linux
/// platform code adds the database updates.
public enum _XDGRegistrar {
    public struct Written: Equatable, Sendable {
        public var desktopFile: URL
        public var iconFile: URL?
        public var mimePackage: URL?
    }

    public static func write(_ plan: _AppRegistration, dataHome: URL, iconPNG: Data?) throws -> Written {
        let fm = FileManager.default
        let apps = dataHome.appendingPathComponent("applications", isDirectory: true)
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
        var icon: URL? = nil
        if let iconPNG {
            let dir = dataHome.appendingPathComponent("icons/hicolor/256x256/apps", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            icon = dir.appendingPathComponent(plan.identifier + ".png")
            try iconPNG.write(to: icon!)
        }
        let desktop = apps.appendingPathComponent(plan.desktopFileName)
        try Data(plan.desktopEntry(iconPath: icon?.path ?? plan.iconPath).utf8).write(to: desktop)
        var mime: URL? = nil
        if let package = plan.mimePackage {
            let dir = dataHome.appendingPathComponent("mime/packages", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            mime = dir.appendingPathComponent(plan.identifier + ".xml")
            try Data(package.utf8).write(to: mime!)
        }
        return Written(desktopFile: desktop, iconFile: icon, mimePackage: mime)
    }

    public static func remove(_ plan: _AppRegistration, dataHome: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: dataHome.appendingPathComponent("applications/" + plan.desktopFileName))
        try? fm.removeItem(at: dataHome.appendingPathComponent("icons/hicolor/256x256/apps/" + plan.identifier + ".png"))
        try? fm.removeItem(at: dataHome.appendingPathComponent("mime/packages/" + plan.identifier + ".xml"))
    }

    /// Whether the desktop entry exists and names this executable.
    public static func isRegistered(_ plan: _AppRegistration, dataHome: URL) -> Bool {
        guard let data = FileManager.default.contents(atPath: dataHome.appendingPathComponent("applications/" + plan.desktopFileName).path) else { return false }
        return String(decoding: data, as: UTF8.self).contains("TryExec=" + _AppRegistration.desktopEscape(plan.executablePath) + "\n")
    }
}

extension NSWorkspace {
    /// Registers the running application's document types and URL schemes with the desktop
    /// for the current user (port only; ADR-0045). Idempotent.
    @MainActor @discardableResult public func _registerApplication() throws -> _AppRegistration {
        try _AppRegistration._registerCurrent()
    }

    /// Removes what `_registerApplication` wrote (port only).
    @MainActor public func _unregisterApplication() throws {
        try _AppRegistration._unregisterCurrent()
    }
}

extension _AppRegistration {
    /// The running application's registration, with its icon resolved for the platform.
    @MainActor static func current() -> _AppRegistration {
        _AppBundle.installMainBundle()
        var plan = _AppRegistration(executablePath: _AppBundle.mainExecutableURL.path)
        plan.iconPath = _AppIcon.iconFilePath()
        return plan
    }
    @MainActor @discardableResult static func _registerCurrent() throws -> _AppRegistration {
        let plan = current()
        try _platformRegisterApplication(plan, iconPNG: _AppIcon.pngData(size: 256))
        return plan
    }
    @MainActor static func _unregisterCurrent() throws {
        try _platformUnregisterApplication(current())
    }

    /// `--appkitcross-register` / `--appkitcross-unregister` on the command line: does it,
    /// says so on stdout (errors on stderr, exit status 1) and exits. Also registers at launch
    /// when the Info.plist sets `AppKitCrossRegistersFileTypes` and the registration is
    /// missing or names another executable.
    @MainActor static func handleLaunchSwitches() {
        let args = CommandLine.arguments
        let register = args.contains("--appkitcross-register"), unregister = args.contains("--appkitcross-unregister")
        if register || unregister {
            do {
                if register {
                    let plan = try _registerCurrent()
                    let exts = plan.documentTypes.flatMap(\.extensions).map { "." + $0 }.joined(separator: " ")
                    let schemes = plan.urlSchemes.flatMap(\.schemes).map { $0 + ":" }.joined(separator: " ")
                    print("AppKitCross: registered \(plan.identifier) for \(exts.isEmpty ? "no document types" : exts)\(schemes.isEmpty ? "" : " and " + schemes)")
                } else {
                    try _unregisterCurrent()
                    print("AppKitCross: unregistered \(_AppBundle.main.platformIdentifier)")
                }
                exit(0)
            } catch {
                fputs("AppKitCross: registration failed: \(error)\n", stderr)
                exit(1)
            }
        }
        #if os(Windows) || os(Linux)
        if ProcessInfo.processInfo.environment["APPKITWIN_HOST_BACKEND"] != "1",
           (_AppBundle.main.infoDictionary["AppKitCrossRegistersFileTypes"] as? Bool) == true {
            let plan = current()
            if !_platformIsApplicationRegistered(plan) { _ = try? _registerCurrent() }
        }
        #endif
    }
}
