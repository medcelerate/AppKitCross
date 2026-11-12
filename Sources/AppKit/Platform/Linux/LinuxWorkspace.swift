// The workspace on Linux desktops (ADR-0022): freedesktop.org's conventions behind
// `PlatformWorkspace`. Applications are desktop entries (`applications/*.desktop` in the
// XDG data directories), file associations come from `mimeapps.list` and the entries'
// `MimeType` lists with shared-mime-info's globs for the file type, launching expands the
// entry's `Exec` line and spawns it, icons come from the icon theme (`icons/<theme>/…`,
// PNG only, the core draws the rest), the trash is the XDG trash specification, the
// running applications are the X11 window list (`_NET_CLIENT_LIST`, LinuxWorkspaceX11.swift)
// and the processes launched here, and the session bus brings the file manager, the
// settings portal, power and session events and the launcher badge (LinuxWorkspaceBus.swift).
//
// Everything reads its directories from `LinuxWorkspaceEnvironment`, so tests point it at
// a temporary tree. `APPKITWIN_ICON_THEME` names the icon theme when the desktop's
// settings do not.

#if os(Linux)
import Foundation
import Glibc
import UniformTypeIdentifiers
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The directories the XDG base directory specification names.
struct LinuxWorkspaceEnvironment {
    var home: String
    var dataHome: String
    var dataDirs: [String]
    var configHome: String
    var configDirs: [String]
    var currentDesktop: [String]
    var path: [String]
    var iconTheme: String?

    static func current() -> LinuxWorkspaceEnvironment {
        let env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? NSHomeDirectory()
        func dirs(_ key: String, _ fallback: String) -> [String] { (env[key].flatMap { $0.isEmpty ? nil : $0 } ?? fallback).split(separator: ":").map(String.init) }
        return LinuxWorkspaceEnvironment(
            home: home,
            dataHome: env["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.local/share",
            dataDirs: dirs("XDG_DATA_DIRS", "/usr/local/share:/usr/share"),
            configHome: env["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.config",
            configDirs: dirs("XDG_CONFIG_DIRS", "/etc/xdg"),
            currentDesktop: (env["XDG_CURRENT_DESKTOP"] ?? "").split(separator: ":").map { String($0).lowercased() },
            path: dirs("PATH", "/usr/local/bin:/usr/bin:/bin"),
            iconTheme: env["APPKITWIN_ICON_THEME"])
    }
    /// Data directories, the user's first.
    var allDataDirs: [String] { [dataHome] + dataDirs }
    var applicationDirs: [String] { allDataDirs.map { $0 + "/applications" } }
}

/// One `.desktop` file.
struct LinuxDesktopEntry: Equatable {
    /// The desktop file id: the path below `applications/` with "/" as "-", without ".desktop".
    var id: String
    var url: URL
    var name: String
    var exec: String
    var icon: String?
    var tryExec: String?
    var mimeTypes: [String]
    var noDisplay: Bool
    var terminal: Bool
    var startupWMClass: String?

    static func parse(_ url: URL, id: String) -> LinuxDesktopEntry? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var inEntry = false
        var fields: [String: String] = [:]
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") || line.isEmpty { continue }
            if line.hasPrefix("[") { inEntry = line == "[Desktop Entry]"; continue }
            guard inEntry, let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if fields[key] == nil { fields[key] = value }
        }
        guard fields["Type"] == nil || fields["Type"] == "Application", let exec = fields["Exec"], !exec.isEmpty else { return nil }
        if fields["Hidden"] == "true" { return nil }
        // The localized name for the current language, else the plain one.
        var name = fields["Name"] ?? id
        if let lang = ProcessInfo.processInfo.environment["LANG"]?.split(separator: ".").first.map(String.init) {
            if let n = fields["Name[\(lang)]"] { name = n }
            else if let short = lang.split(separator: "_").first, let n = fields["Name[\(short)]"] { name = n }
        }
        return LinuxDesktopEntry(id: id, url: url, name: name, exec: exec, icon: fields["Icon"], tryExec: fields["TryExec"],
                                 mimeTypes: (fields["MimeType"] ?? "").split(separator: ";").map(String.init).filter { !$0.isEmpty },
                                 noDisplay: fields["NoDisplay"] == "true", terminal: fields["Terminal"] == "true", startupWMClass: fields["StartupWMClass"])
    }

    /// The command line for `urls` (and `files`): the field codes of the specification.
    /// `%f`/`%u` take the first item, `%F`/`%U` all of them; `%i`, `%c`, `%k` expand to the
    /// icon, name and file; the deprecated codes vanish.
    func commandLine(urls: [URL]) -> [String] {
        var args: [String] = []
        var multi = false
        for word in LinuxDesktopEntry.splitExec(exec) {
            if word == "%F" || word == "%U" {
                multi = true
                args += urls.map { word == "%F" ? $0.path : $0.absoluteString }
            } else if word == "%f" || word == "%u" {
                if let first = urls.first { args.append(word == "%f" ? first.path : first.absoluteString) }
            } else if word == "%i" {
                if let icon { args += ["--icon", icon] }
            } else if word == "%c" {
                args.append(name)
            } else if word == "%k" {
                args.append(url.path)
            } else if word.hasPrefix("%"), word.count == 2 {
                continue
            } else {
                var w = word
                for (code, value) in [("%f", urls.first?.path ?? ""), ("%u", urls.first?.absoluteString ?? ""), ("%c", name), ("%k", url.path)] { w = w.replacingOccurrences(of: code, with: value) }
                args.append(w.replacingOccurrences(of: "%%", with: "%"))
            }
        }
        _ = multi
        return args
    }

    /// Splits an Exec value the way the specification quotes it: whitespace separates,
    /// double quotes group, backslash escapes inside quotes.
    static func splitExec(_ exec: String) -> [String] {
        var words: [String] = []
        var current = ""
        var inQuotes = false
        var escaped = false
        var hasWord = false
        for ch in exec {
            if escaped { current.append(ch); escaped = false; continue }
            if inQuotes {
                if ch == "\\" { escaped = true } else if ch == "\"" { inQuotes = false } else { current.append(ch) }
                continue
            }
            if ch == "\"" { inQuotes = true; hasWord = true; continue }
            if ch == " " || ch == "\t" {
                if hasWord { words.append(current); current = ""; hasWord = false }
                continue
            }
            current.append(ch)
            hasWord = true
        }
        if hasWord { words.append(current) }
        return words
    }
}

/// The desktop entries, MIME types and associations of the XDG data directories.
final class LinuxDesktopDatabase {
    let environment: LinuxWorkspaceEnvironment
    private var entriesCache: [String: LinuxDesktopEntry]? = nil

    init(environment: LinuxWorkspaceEnvironment) { self.environment = environment }

    /// Every desktop entry by id; the first directory that holds an id wins.
    var entries: [String: LinuxDesktopEntry] {
        if let c = entriesCache { return c }
        var result: [String: LinuxDesktopEntry] = [:]
        let fm = FileManager.default
        for dir in environment.applicationDirs {
            guard let items = fm.enumerator(atPath: dir) else { continue }
            while let rel = items.nextObject() as? String {
                guard rel.hasSuffix(".desktop") else { continue }
                let id = String(rel.dropLast(".desktop".count)).replacingOccurrences(of: "/", with: "-")
                guard result[id] == nil, let entry = LinuxDesktopEntry.parse(URL(fileURLWithPath: dir + "/" + rel), id: id) else { continue }
                result[id] = entry
            }
        }
        entriesCache = result
        return result
    }
    func invalidate() { entriesCache = nil }

    func entry(id: String) -> LinuxDesktopEntry? {
        let key = id.hasSuffix(".desktop") ? String(id.dropLast(".desktop".count)) : id
        if let e = entries[key] { return e }
        return entries.values.first { $0.id.caseInsensitiveCompare(key) == .orderedSame }
    }
    func entry(at url: URL) -> LinuxDesktopEntry? {
        let path = url.standardizedFileURL.path
        if let e = entries.values.first(where: { $0.url.standardizedFileURL.path == path }) { return e }
        return LinuxDesktopEntry.parse(url, id: url.deletingPathExtension().lastPathComponent)
    }
    /// The entry a window class (`WM_CLASS`) belongs to.
    func entry(wmClass: String) -> LinuxDesktopEntry? {
        if let e = entries.values.first(where: { $0.startupWMClass?.caseInsensitiveCompare(wmClass) == .orderedSame }) { return e }
        if let e = entry(id: wmClass) { return e }
        let lower = wmClass.lowercased()
        return entries.values.first { $0.id.lowercased() == lower || $0.id.lowercased().hasSuffix("." + lower) }
    }
    /// The entry whose Exec runs the executable at `path` (for the process list).
    func entry(executable path: String) -> LinuxDesktopEntry? {
        let name = (path as NSString).lastPathComponent
        return entries.values.first { entry in
            guard let first = LinuxDesktopEntry.splitExec(entry.exec).first else { return false }
            return first == path || (first as NSString).lastPathComponent == name || entry.tryExec == path
        }
    }

    // MARK: MIME types

    /// The MIME type for a file: the UTI table's answer, else shared-mime-info's globs.
    func mimeType(forExtension ext: String) -> String? {
        let lower = ext.lowercased()
        guard !lower.isEmpty else { return nil }
        if let t = UTType(filenameExtension: lower)?.preferredMIMEType { return t }
        for dir in environment.allDataDirs {
            guard let text = try? String(contentsOfFile: dir + "/mime/globs2", encoding: .utf8) else { continue }
            var best: (Int, String)? = nil
            for line in text.split(separator: "\n") where !line.hasPrefix("#") {
                let parts = line.split(separator: ":", maxSplits: 2).map(String.init)
                guard parts.count == 3, let weight = Int(parts[0]) else { continue }
                let pattern = parts[2].lowercased()
                if pattern == "*." + lower, best == nil || weight > best!.0 { best = (weight, parts[1]) }
            }
            if let best { return best.1 }
        }
        return nil
    }
    func mimeType(for url: URL) -> String {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue { return "inode/directory" }
        return mimeType(forExtension: url.pathExtension) ?? "application/octet-stream"
    }
    /// The icon name shared-mime-info gives a MIME type's family (`mime/generic-icons`).
    func genericIcon(forMIMEType mime: String) -> String? {
        for dir in environment.allDataDirs {
            guard let text = try? String(contentsOfFile: dir + "/mime/generic-icons", encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                if parts.count == 2, parts[0] == mime { return parts[1] }
            }
        }
        return nil
    }

    // MARK: Associations

    /// The `mimeapps.list` files in precedence order (desktop-specific ones first).
    private var mimeappsFiles: [String] {
        var files: [String] = []
        let dirs = [environment.configHome] + environment.configDirs + environment.applicationDirs
        for dir in dirs {
            for desktop in environment.currentDesktop { files.append(dir + "/\(desktop)-mimeapps.list") }
            files.append(dir + "/mimeapps.list")
        }
        return files
    }

    private struct MimeApps {
        var defaults: [String: [String]] = [:]
        var added: [String: [String]] = [:]
        var removed: [String: Set<String>] = [:]
    }
    private func parseMimeApps(_ path: String) -> MimeApps? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var result = MimeApps()
        var section = ""
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { section = line; continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let apps = line[line.index(after: eq)...].split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            switch section {
            case "[Default Applications]": result.defaults[key, default: []] += apps
            case "[Added Associations]": result.added[key, default: []] += apps
            case "[Removed Associations]": result.removed[key, default: []].formUnion(apps)
            default: break
            }
        }
        return result
    }

    /// The desktop entries for a MIME type, the default first, as the association
    /// specification resolves them.
    func handlers(forMIMEType mime: String) -> [LinuxDesktopEntry] {
        var ordered: [String] = []
        var removed: Set<String> = []
        func normalized(_ id: String) -> String { id.hasSuffix(".desktop") ? String(id.dropLast(".desktop".count)) : id }
        func add(_ ids: [String]) { for id in ids.map(normalized) where !removed.contains(id) && !ordered.contains(id) { ordered.append(id) } }
        let lists = mimeappsFiles.compactMap(parseMimeApps)
        for list in lists { add(list.defaults[mime] ?? []) ; removed.formUnion((list.removed[mime] ?? []).map(normalized)) }
        for list in lists { add(list.added[mime] ?? []) }
        // mimeinfo.cache, then the entries themselves.
        for dir in environment.applicationDirs {
            guard let text = try? String(contentsOfFile: dir + "/mimeinfo.cache", encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where line.hasPrefix(mime + "=") {
                add(line.dropFirst(mime.count + 1).split(separator: ";").map(String.init))
            }
        }
        add(entries.values.filter { $0.mimeTypes.contains(mime) }.map(\.id).sorted())
        return ordered.compactMap { entry(id: $0) }.filter { !$0.noDisplay || ordered.count == 1 }
    }

    /// Writes the user's `mimeapps.list` default for a MIME type.
    func setDefault(_ entryID: String, forMIMEType mime: String) throws {
        let path = environment.configHome + "/mimeapps.list"
        var text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let section = lines.firstIndex(of: "[Default Applications]") {
            var i = section + 1
            while i < lines.count, !lines[i].hasPrefix("[") {
                if lines[i].hasPrefix(mime + "=") { lines.remove(at: i) } else { i += 1 }
            }
            lines.insert("\(mime)=\(entryID).desktop", at: section + 1)
        } else {
            if !lines.isEmpty, lines.last != "" { lines.append("") }
            lines += ["[Default Applications]", "\(mime)=\(entryID).desktop"]
        }
        text = lines.joined(separator: "\n")
        try FileManager.default.createDirectory(atPath: environment.configHome, withIntermediateDirectories: true)
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

/// A PNG from the icon theme for an icon name (freedesktop icon theme specification,
/// simplified: the theme's size directories and its parents, hicolor last).
final class LinuxIconTheme {
    let environment: LinuxWorkspaceEnvironment
    private var themeName: String?
    private var inheritanceCache: [String: [String]] = [:]
    private var cache: [String: URL?] = [:]

    init(environment: LinuxWorkspaceEnvironment, themeName: String?) {
        self.environment = environment
        self.themeName = themeName ?? environment.iconTheme
    }

    /// The theme to search, from the environment, the GTK settings file or KDE's globals.
    var theme: String {
        if let t = themeName { return t }
        for file in ["/gtk-4.0/settings.ini", "/gtk-3.0/settings.ini"] {
            if let text = try? String(contentsOfFile: environment.configHome + file, encoding: .utf8) {
                for line in text.split(separator: "\n") where line.hasPrefix("gtk-icon-theme-name") {
                    if let eq = line.firstIndex(of: "=") { themeName = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces); return themeName! }
                }
            }
        }
        if let text = try? String(contentsOfFile: environment.configHome + "/kdeglobals", encoding: .utf8) {
            var inIcons = false
            for line in text.split(separator: "\n") {
                if line.hasPrefix("[") { inIcons = line == "[Icons]"; continue }
                if inIcons, line.hasPrefix("Theme="), line.count > 6 { themeName = String(line.dropFirst(6)); return themeName! }
            }
        }
        themeName = "hicolor"
        return "hicolor"
    }
    func setTheme(_ name: String) { themeName = name; cache.removeAll() }

    private func themeDirs(_ theme: String) -> [String] { environment.allDataDirs.map { $0 + "/icons/" + theme } + [environment.home + "/.icons/" + theme] }

    /// The theme and its parents, breadth first, hicolor last.
    private func inheritance(_ theme: String) -> [String] {
        if let c = inheritanceCache[theme] { return c }
        var order: [String] = []
        var queue = [theme]
        while let t = queue.first {
            queue.removeFirst()
            guard !order.contains(t) else { continue }
            order.append(t)
            for dir in themeDirs(t) {
                guard let text = try? String(contentsOfFile: dir + "/index.theme", encoding: .utf8) else { continue }
                for line in text.split(separator: "\n") where line.hasPrefix("Inherits=") {
                    queue += line.dropFirst("Inherits=".count).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                }
                break
            }
        }
        if !order.contains("hicolor") { order.append("hicolor") }
        inheritanceCache[theme] = order
        return order
    }

    /// The PNG for the first of `names` the theme has, closest to `size` pixels.
    func lookup(_ names: [String], size: Int, contexts: [String]) -> URL? {
        let key = names.joined(separator: "|") + "@\(size)"
        if let c = cache[key] { return c }
        var found: URL? = nil
        search: for name in names where !name.isEmpty {
            if name.hasPrefix("/") {
                if name.hasSuffix(".png"), FileManager.default.fileExists(atPath: name) { found = URL(fileURLWithPath: name); break }
                continue
            }
            for theme in inheritance(self.theme) {
                var best: (Int, URL)? = nil
                for dir in themeDirs(theme) {
                    guard let sizes = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
                    for sizeDir in sizes {
                        let px: Int
                        if sizeDir == "scalable" { continue }
                        else if let x = sizeDir.firstIndex(of: "x"), let n = Int(sizeDir[..<x]) { px = n }
                        else if let n = Int(sizeDir) { px = n }
                        else { continue }
                        for context in contexts {
                            let path = "\(dir)/\(sizeDir)/\(context)/\(name).png"
                            guard FileManager.default.fileExists(atPath: path) else { continue }
                            // Prefer the smallest size at or above the request, else the largest below.
                            let distance = px >= size ? px - size : 1000 + (size - px)
                            if best == nil || distance < best!.0 { best = (distance, URL(fileURLWithPath: path)) }
                        }
                    }
                }
                if let best { found = best.1; break search }
            }
            for dir in environment.allDataDirs {
                let path = dir + "/pixmaps/\(name).png"
                if FileManager.default.fileExists(atPath: path) { found = URL(fileURLWithPath: path); break search }
            }
        }
        cache[key] = found
        return found
    }
}

/// The XDG trash: `$XDG_DATA_HOME/Trash/files` with a `.trashinfo` per item.
enum LinuxTrash {
    static func recycle(_ url: URL, environment: LinuxWorkspaceEnvironment) throws -> URL {
        let fm = FileManager.default
        let trash = URL(fileURLWithPath: environment.dataHome + "/Trash", isDirectory: true)
        let files = trash.appendingPathComponent("files", isDirectory: true), info = trash.appendingPathComponent("info", isDirectory: true)
        try fm.createDirectory(at: files, withIntermediateDirectories: true)
        try fm.createDirectory(at: info, withIntermediateDirectories: true)
        var name = url.lastPathComponent
        var n = 1
        while fm.fileExists(atPath: files.appendingPathComponent(name).path) || fm.fileExists(atPath: info.appendingPathComponent(name + ".trashinfo").path) {
            n += 1
            let ext = url.pathExtension
            name = url.deletingPathExtension().lastPathComponent + ".\(n)" + (ext.isEmpty ? "" : "." + ext)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let encodedPath = url.standardizedFileURL.path.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "%"))) ?? url.path
        let record = "[Trash Info]\nPath=\(encodedPath)\nDeletionDate=\(formatter.string(from: Date()))\n"
        try record.write(to: info.appendingPathComponent(name + ".trashinfo"), atomically: true, encoding: .utf8)
        let destination = files.appendingPathComponent(name)
        do {
            try fm.moveItem(at: url, to: destination)
        } catch {
            try? fm.removeItem(at: info.appendingPathComponent(name + ".trashinfo"))
            throw PlatformWorkspaceError.fileOperationFailed("\(url.path): \(error)")
        }
        return destination
    }
}

/// What /proc says about a process.
struct LinuxProcessInfo {
    var pid: Int32
    var name: String
    var executable: URL?
    var launchDate: Date?

    static func read(_ pid: Int32) -> LinuxProcessInfo? {
        let base = "/proc/\(pid)"
        guard FileManager.default.fileExists(atPath: base) else { return nil }
        var name = (try? String(contentsOfFile: base + "/comm", encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let exe = (try? FileManager.default.destinationOfSymbolicLink(atPath: base + "/exe")).map { $0.replacingOccurrences(of: " (deleted)", with: "") }
        if name.isEmpty, let exe { name = (exe as NSString).lastPathComponent }
        var launch: Date? = nil
        if let stat = try? String(contentsOfFile: base + "/stat", encoding: .utf8), let close = stat.lastIndex(of: ")") {
            let fields = stat[stat.index(after: close)...].split(separator: " ")
            // Field 22 of stat is the start time in clock ticks after boot; the first two
            // fields (pid and comm) precede the ")" we skipped.
            if fields.count > 20, let ticks = Double(fields[19]), let boot = bootDate {
                launch = boot.addingTimeInterval(ticks / Double(sysconf(Int32(_SC_CLK_TCK))))
            }
        }
        return LinuxProcessInfo(pid: pid, name: name, executable: exe.map { URL(fileURLWithPath: $0) }, launchDate: launch)
    }

    static let bootDate: Date? = {
        guard let stat = try? String(contentsOfFile: "/proc/stat", encoding: .utf8) else { return nil }
        for line in stat.split(separator: "\n") where line.hasPrefix("btime ") {
            if let t = TimeInterval(line.dropFirst(6).trimmingCharacters(in: .whitespaces)) { return Date(timeIntervalSince1970: t) }
        }
        return nil
    }()

    /// The ELF machine of the executable as `NSBundleExecutableArchitecture…` values.
    static func architecture(_ pid: Int32) -> Int? {
        guard let handle = FileHandle(forReadingAtPath: "/proc/\(pid)/exe") else { return nil }
        defer { handle.closeFile() }
        let header = handle.readData(ofLength: 20)
        guard header.count == 20, header[0] == 0x7f, header[1] == 0x45, header[2] == 0x4c, header[3] == 0x46 else { return nil }
        let machine = UInt16(header[18]) | (UInt16(header[19]) << 8)
        switch machine {
        case 0x3e: return 0x01000007   // x86_64
        case 0xb7: return 0x0100000c   // arm64
        case 0x03: return 0x00000007   // i386
        default: return nil
        }
    }
}

/// A window the window system lists (X11), as the workspace wants it.
struct LinuxWindowRecord {
    var pid: Int32
    var wmClass: String?
    var title: String?
    var isActive: Bool
    var isHidden: Bool
    var windowID: UInt
}

/// What the window-system backend offers the workspace (X11 has a window list; Wayland none).
@MainActor
protocol LinuxWorkspaceWindowSystem: AnyObject {
    /// The managed top-level windows, or nil when the window system cannot list them.
    func windowList() -> [LinuxWindowRecord]?
    func activate(_ window: LinuxWindowRecord) -> Bool
    func minimize(_ window: LinuxWindowRecord) -> Bool
    func restore(_ window: LinuxWindowRecord) -> Bool
    func requestClose(_ window: LinuxWindowRecord) -> Bool
    /// Sets the icon of this application's own windows (`_NET_WM_ICON`); false when the
    /// window system has no such thing (Wayland).
    func setApplicationIcon(_ image: CGImage?) -> Bool
}

@MainActor
final class LinuxWorkspace: PlatformWorkspace {
    let environment: LinuxWorkspaceEnvironment
    let database: LinuxDesktopDatabase
    let iconTheme: LinuxIconTheme
    /// The session and system buses (nil without a session bus); see LinuxWorkspaceBus.swift.
    private(set) var bus: LinuxWorkspaceBus?
    weak var windowSystem: (any LinuxWorkspaceWindowSystem)?
    weak var observer: (any PlatformWorkspaceObserver)?
    private var monitoring = false
    /// Processes launched here, by pid, with their Process so the exit is reaped.
    private var launched: [Int32: (process: Process, info: PlatformRunningApplication)] = [:]
    /// The last window list seen, to diff launches, terminations and activation.
    private var lastWindowPIDs: Set<Int32> = []
    private var lastActivePID: Int32? = nil
    private var trace: Bool { NSView._traceInvalidation }

    init(environment: LinuxWorkspaceEnvironment = .current(), connectsToBus: Bool = true, windowSystem: (any LinuxWorkspaceWindowSystem)? = nil) {
        self.environment = environment
        self.database = LinuxDesktopDatabase(environment: environment)
        self.iconTheme = LinuxIconTheme(environment: environment, themeName: nil)
        self.windowSystem = windowSystem
        if connectsToBus { bus = LinuxWorkspaceBus.connect(environment: environment) }
        if let name = bus?.iconThemeName() { iconTheme.setTheme(name) }
    }

    func startMonitoring() {
        guard !monitoring else { return }
        monitoring = true
        bus?.startSignals { [weak self] event in self?.observer?.platformWorkspaceDidObserve(event) }
        if let list = windowSystem?.windowList() {
            lastWindowPIDs = Set(list.map(\.pid))
            lastActivePID = list.first { $0.isActive }?.pid
        }
    }

    /// The backend's poll loop: the bus descriptor, and the dispatch after it.
    var fileDescriptors: [Int32] { bus?.fileDescriptors ?? [] }
    func dispatch() { bus?.dispatch() }

    /// The X11 backend saw the root window's `_NET_CLIENT_LIST` or `_NET_ACTIVE_WINDOW` change.
    func windowListDidChange() {
        guard monitoring, let list = windowSystem?.windowList() else { return }
        let pids = Set(list.map(\.pid))
        for pid in pids.subtracting(lastWindowPIDs) where pid != getpid() {
            if let app = runningApplication(withProcessIdentifier: pid) { observer?.platformWorkspaceDidObserve(.applicationDidLaunch(app)) }
        }
        for pid in lastWindowPIDs.subtracting(pids) where launched[pid] == nil && pid != getpid() {
            observer?.platformWorkspaceDidObserve(.applicationDidTerminate(processIdentifier: pid))
        }
        lastWindowPIDs = pids
        let active = list.first { $0.isActive }?.pid
        if active != lastActivePID {
            lastActivePID = active
            if let active { observer?.platformWorkspaceDidObserve(.applicationDidActivate(processIdentifier: active)) }
        }
    }

    // MARK: Opening

    func open(_ url: URL) -> Bool {
        if url.isFileURL {
            if let entry = database.handlers(forMIMEType: database.mimeType(for: url)).first {
                return (try? launch(entry, urls: [url], options: PlatformLaunchOptions())) != nil
            }
        } else if let scheme = url.scheme, let entry = database.handlers(forMIMEType: "x-scheme-handler/" + scheme.lowercased()).first {
            return (try? launch(entry, urls: [url], options: PlatformLaunchOptions())) != nil
        }
        if let portal = bus, portal.openURI(url) { return true }
        return xdgOpen(url)
    }

    private func xdgOpen(_ url: URL) -> Bool {
        guard let xdg = executable(named: "xdg-open") else { return false }
        return (try? spawn([xdg, url.isFileURL ? url.path : url.absoluteString], name: "xdg-open", entry: nil, options: PlatformLaunchOptions())) != nil
    }

    func open(_ urls: [URL], withApplicationAt applicationURL: URL?, options: PlatformLaunchOptions) throws -> PlatformRunningApplication {
        if let applicationURL {
            if applicationURL.pathExtension == "desktop", let entry = database.entry(at: applicationURL) {
                return try launch(entry, urls: urls, options: options)
            }
            guard FileManager.default.isExecutableFile(atPath: applicationURL.path) else { throw PlatformWorkspaceError.noApplication(applicationURL.path) }
            let entry = database.entry(executable: applicationURL.path)
            return try spawn([applicationURL.path] + options.arguments + urls.map { $0.isFileURL ? $0.path : $0.absoluteString },
                             name: entry?.name ?? applicationURL.lastPathComponent, entry: entry, options: options)
        }
        guard let first = urls.first else { throw PlatformWorkspaceError.noApplication("nothing") }
        let mime = first.isFileURL ? database.mimeType(for: first) : "x-scheme-handler/" + (first.scheme ?? "").lowercased()
        guard let entry = database.handlers(forMIMEType: mime).first else { throw PlatformWorkspaceError.noApplication("\(first.absoluteString) (\(mime))") }
        return try launch(entry, urls: urls, options: options)
    }

    private func launch(_ entry: LinuxDesktopEntry, urls: [URL], options: PlatformLaunchOptions) throws -> PlatformRunningApplication {
        var argv = entry.commandLine(urls: urls)
        if !options.arguments.isEmpty { argv.insert(contentsOf: options.arguments, at: min(1, argv.count)) }
        guard let first = argv.first, let exe = executable(named: first) else { throw PlatformWorkspaceError.launchFailed(entry.exec) }
        argv[0] = exe
        return try spawn(argv, name: entry.name, entry: entry, options: options)
    }

    /// The absolute path of a command: as given when absolute, else the first PATH hit.
    func executable(named name: String) -> String? {
        if name.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: name) ? name : nil }
        for dir in environment.path {
            let candidate = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    private func spawn(_ argv: [String], name: String, entry: LinuxDesktopEntry?, options: PlatformLaunchOptions) throws -> PlatformRunningApplication {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: argv[0])
        process.arguments = Array(argv.dropFirst())
        if !options.environment.isEmpty { process.environment = ProcessInfo.processInfo.environment.merging(options.environment) { $1 } }
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { throw PlatformWorkspaceError.launchFailed("\(argv[0]): \(error)") }
        let pid = process.processIdentifier
        let info = PlatformRunningApplication(processIdentifier: pid, localizedName: name, bundleIdentifier: entry?.id ?? (argv[0] as NSString).lastPathComponent,
                                              executableURL: URL(fileURLWithPath: argv[0]), applicationURL: entry?.url ?? URL(fileURLWithPath: argv[0]),
                                              launchDate: Date(), isActive: false, isHidden: false, hasWindows: true)
        launched[pid] = (process, info)
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.launched[pid] != nil else { return }
                    self.launched[pid] = nil
                    if self.monitoring, !self.lastWindowPIDs.contains(pid) { self.observer?.platformWorkspaceDidObserve(.applicationDidTerminate(processIdentifier: pid)) }
                }
            }
        }
        if trace { NSView._trace("workspace: launched \(argv) as pid \(pid)") }
        return info
    }

    func revealFiles(_ urls: [URL], selecting: Bool) -> Bool {
        if let bus, bus.showItems(urls, selecting: selecting) { return true }
        // No file manager service: open the folders with the directory handler.
        var ok = false
        for folder in Set(urls.map { selecting ? $0.deletingLastPathComponent() : $0 }) { if open(folder) { ok = true } }
        return ok
    }

    // MARK: Associations

    func applicationURLs(toOpen target: PlatformOpenTarget) -> [URL] {
        let mime: String
        switch target {
        case .file(let url): mime = database.mimeType(for: url)
        case .fileExtension(let ext): guard let m = database.mimeType(forExtension: ext) else { return [] }; mime = m
        case .scheme(let scheme): mime = "x-scheme-handler/" + scheme.lowercased()
        }
        return database.handlers(forMIMEType: mime).map(\.url)
    }

    func applicationURL(withBundleIdentifier identifier: String) -> URL? {
        if let e = database.entry(id: identifier) { return e.url }
        if let exe = executable(named: identifier) { return URL(fileURLWithPath: exe) }
        return nil
    }

    func setDefaultApplication(at applicationURL: URL, toOpen target: PlatformOpenTarget) throws {
        guard let entry = database.entry(at: applicationURL) else { throw PlatformWorkspaceError.noApplication(applicationURL.path) }
        let mime: String
        switch target {
        case .file(let url): mime = database.mimeType(for: url)
        case .fileExtension(let ext): guard let m = database.mimeType(forExtension: ext) else { throw PlatformWorkspaceError.unsupported("no MIME type for .\(ext)") }; mime = m
        case .scheme(let scheme): mime = "x-scheme-handler/" + scheme.lowercased()
        }
        try database.setDefault(entry.id, forMIMEType: mime)
    }

    // MARK: Icons

    func icon(for target: PlatformIconTarget, size: CGFloat, scale: CGFloat) -> CGImage? {
        let px = Int((size * scale).rounded())
        var names: [String] = []
        var contexts = ["mimetypes", "places", "apps", "categories", "status", "devices", "actions", "emblems"]
        switch target {
        case .folder:
            names = ["folder", "inode-directory"]
            contexts = ["places", "mimetypes"] + contexts
        case .file(let path):
            let url = URL(fileURLWithPath: path)
            if url.pathExtension == "desktop", let entry = database.entry(at: url) { return iconData(names: [entry.icon ?? "application-x-executable"], size: px, contexts: ["apps"] + contexts) }
            names = iconNames(forMIMEType: database.mimeType(for: url))
        case .fileExtension(let ext):
            guard let mime = database.mimeType(forExtension: ext) else { return nil }
            names = iconNames(forMIMEType: mime)
        case .application(let url):
            if let entry = database.entry(at: url) ?? database.entry(executable: url.path) { names = [entry.icon ?? "", "application-x-executable"] }
            else { names = ["application-x-executable"] }
            contexts = ["apps"] + contexts
        case .process(let pid):
            let proc = LinuxProcessInfo.read(pid)
            let entry = launched[pid].flatMap { database.entry(at: $0.info.applicationURL ?? $0.info.executableURL!) }
                ?? proc?.executable.flatMap { database.entry(executable: $0.path) }
                ?? windowSystem?.windowList()?.first { $0.pid == pid }?.wmClass.flatMap { database.entry(wmClass: $0) }
            names = [entry?.icon ?? "", "application-x-executable"]
            contexts = ["apps"] + contexts
        }
        return iconData(names: names, size: px, contexts: contexts)
    }

    private func iconNames(forMIMEType mime: String) -> [String] {
        var names = [mime.replacingOccurrences(of: "/", with: "-")]
        if let generic = database.genericIcon(forMIMEType: mime) { names.append(generic) }
        if let media = mime.split(separator: "/").first { names.append("\(media)-x-generic") }
        names.append("unknown")
        return names
    }

    private func iconData(names: [String], size: Int, contexts: [String]) -> CGImage? {
        guard let url = iconTheme.lookup(names, size: size, contexts: contexts), let data = try? Data(contentsOf: url) else { return nil }
        return Platform.imageCodec.decode(data)
    }

    // MARK: Files

    func recycle(_ url: URL) throws -> URL? {
        if let bus, bus.trashFile(url) { return nil }
        return try LinuxTrash.recycle(url, environment: environment)
    }

    /// Nothing caches file metadata outside the file manager here; nothing to tell.
    func noteFileSystemChanged(_ path: String) {}

    // MARK: Running applications

    var runningApplications: [PlatformRunningApplication] {
        var result: [Int32: PlatformRunningApplication] = [:]
        let me = getpid()
        let active = windowSystem?.windowList()
        if let windows = active {
            for w in windows where w.pid > 0 && w.pid != me {
                if var existing = result[w.pid] {
                    existing.isActive = existing.isActive || w.isActive
                    existing.isHidden = existing.isHidden && w.isHidden
                    result[w.pid] = existing
                } else if let app = application(for: w) {
                    result[w.pid] = app
                }
            }
        }
        for (pid, launch) in launched where result[pid] == nil && pid != me {
            var info = launch.info
            info.isActive = false
            result[pid] = info
        }
        return result.values.sorted { $0.processIdentifier < $1.processIdentifier }
    }

    private func application(for w: LinuxWindowRecord) -> PlatformRunningApplication? {
        guard let proc = LinuxProcessInfo.read(w.pid) else { return nil }
        let entry = w.wmClass.flatMap { database.entry(wmClass: $0) } ?? proc.executable.flatMap { database.entry(executable: $0.path) }
        return PlatformRunningApplication(processIdentifier: w.pid, localizedName: entry?.name ?? w.wmClass ?? proc.name,
                                          bundleIdentifier: entry?.id ?? w.wmClass?.lowercased() ?? proc.name, executableURL: proc.executable,
                                          applicationURL: entry?.url ?? proc.executable, launchDate: proc.launchDate, isActive: w.isActive, isHidden: w.isHidden, hasWindows: true)
    }

    var frontmostProcessIdentifier: Int32? {
        if let list = windowSystem?.windowList() { return list.first { $0.isActive }?.pid }
        return nil
    }

    func runningApplication(withProcessIdentifier pid: Int32) -> PlatformRunningApplication? {
        if let w = windowSystem?.windowList()?.filter({ $0.pid == pid }), !w.isEmpty, var app = application(for: w[0]) {
            app.isActive = w.contains { $0.isActive }
            app.isHidden = w.allSatisfy { $0.isHidden }
            return app
        }
        if let l = launched[pid] { return l.info }
        guard let proc = LinuxProcessInfo.read(pid) else { return nil }
        let entry = proc.executable.flatMap { database.entry(executable: $0.path) }
        return PlatformRunningApplication(processIdentifier: pid, localizedName: entry?.name ?? proc.name, bundleIdentifier: entry?.id ?? proc.name,
                                          executableURL: proc.executable, applicationURL: entry?.url ?? proc.executable, launchDate: proc.launchDate,
                                          isActive: false, isHidden: false, hasWindows: false)
    }

    private func windows(of pid: Int32) -> [LinuxWindowRecord] { windowSystem?.windowList()?.filter { $0.pid == pid } ?? [] }

    func activate(processIdentifier pid: Int32) -> Bool {
        guard let ws = windowSystem else { return false }
        let ws_ = windows(of: pid)
        guard let main = ws_.first(where: { !$0.isHidden }) ?? ws_.first else { return false }
        return ws.activate(main)
    }
    func hide(processIdentifier pid: Int32) -> Bool {
        guard let ws = windowSystem else { return false }
        var ok = false
        for w in windows(of: pid) where !w.isHidden { if ws.minimize(w) { ok = true } }
        return ok
    }
    func unhide(processIdentifier pid: Int32) -> Bool {
        guard let ws = windowSystem else { return false }
        var ok = false
        for w in windows(of: pid) where w.isHidden { if ws.restore(w) { ok = true } }
        return ok
    }
    func terminate(processIdentifier pid: Int32, force: Bool) -> Bool {
        guard pid > 1, pid != getpid() else { return false }
        if force { return kill(pid, SIGKILL) == 0 }
        let ws_ = windows(of: pid)
        if let ws = windowSystem, !ws_.isEmpty {
            var ok = false
            for w in ws_ { if ws.requestClose(w) { ok = true } }
            if ok { return true }
        }
        return kill(pid, SIGTERM) == 0
    }
    func executableArchitecture(processIdentifier pid: Int32) -> Int? { LinuxProcessInfo.architecture(pid) }

    // MARK: Settings

    var accessibilityDisplayOptions: PlatformAccessibilityDisplayOptions { bus?.accessibilityDisplayOptions() ?? PlatformAccessibilityDisplayOptions() }

    func desktopImageURL(forDisplay index: Int) -> URL? {
        if let s = gsettings(["get", "org.gnome.desktop.background", "picture-uri"]) {
            let trimmed = s.trimmingCharacters(in: CharacterSet(charactersIn: "'\" \n"))
            if let url = URL(string: trimmed) { return url.isFileURL ? URL(fileURLWithPath: url.path) : url }
        }
        if let s = bus?.readSetting(namespace: "org.gnome.desktop.background", key: "picture-uri"), let url = URL(string: s) {
            return url.isFileURL ? URL(fileURLWithPath: url.path) : url
        }
        return nil
    }
    func setDesktopImageURL(_ url: URL, forDisplay index: Int) throws {
        guard executable(named: "gsettings") != nil else { throw PlatformWorkspaceError.unsupported("setting the desktop picture needs gsettings (GNOME)") }
        let uri = url.isFileURL ? "file://" + url.path : url.absoluteString
        for key in ["picture-uri", "picture-uri-dark"] {
            guard gsettings(["set", "org.gnome.desktop.background", key, "'\(uri)'"]) != nil else { throw PlatformWorkspaceError.fileOperationFailed("gsettings set \(key)") }
        }
    }
    private func gsettings(_ arguments: [String]) -> String? {
        guard let exe = executable(named: "gsettings") else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = arguments
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Dock tile

    func setDockTile(_ tile: PlatformDockTile) {
        let id = NSRunningApplication.current.bundleIdentifier ?? ProcessInfo.processInfo.processName
        bus?.updateLauncherEntry(desktopID: id, badgeLabel: tile.badgeLabel)
        var icon = tile.icon
        if icon == nil, let overlay = tile.badgeOverlay,
           let base = self.icon(for: .process(getpid()), size: 128, scale: tile.scale) {
            icon = _NSWorkspaceIcons.compose(icon: NSImage(cgImage: base, size: NSSize(width: 128, height: 128)), size: NSSize(width: 128, height: 128), badge: overlay, scale: tile.scale)
        }
        if windowSystem?.setApplicationIcon(icon) != true, trace { NSView._trace("workspace: no window icon on this window system") }
    }
}
#endif
