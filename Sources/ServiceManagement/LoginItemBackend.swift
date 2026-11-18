// ServiceManagement (ADR-0043): the platform seam behind SMAppService and the XDG autostart
// backend (pure Foundation, so it compiles and is tested everywhere).

import Foundation

protocol LoginItemBackend: AnyObject, Sendable {
    func status() -> SMAppService.Status
    func register() throws
    func unregister() throws
    func openSettings()
}

/// The running app as a login item: a stable identifier, the name the desktop shows, and
/// the executable to start.
struct LoginItemIdentity: Sendable, Equatable {
    var identifier: String
    var displayName: String
    /// The native path of the executable (backslashes on Windows).
    var executablePath: String

    static var current: LoginItemIdentity {
        let bundle = Bundle.main
        let url = bundle.executableURL ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "app")
        let path = url.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? url.path
        let stem = (url.lastPathComponent as NSString).deletingPathExtension
        let identifier = bundle.bundleIdentifier ?? "AppKitCross.\(stem)"
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? stem
        return LoginItemIdentity(identifier: identifier, displayName: name, executablePath: path)
    }

    /// The identifier restricted to what file names and registry value names accept.
    var fileSafeIdentifier: String {
        String(identifier.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" ? $0 : "_" })
    }
}

func makeDefaultLoginItemBackend() -> LoginItemBackend {
    #if os(Windows)
    return WindowsLoginItemBackend(identity: .current)
    #else
    return XDGAutostartBackend(directory: XDGAutostartBackend.defaultDirectory(), identity: .current)
    #endif
}

/// The XDG autostart entry: $XDG_CONFIG_HOME/autostart/<id>.desktop (Desktop Application
/// Autostart Specification 0.5, Desktop Entry Specification 1.5).
final class XDGAutostartBackend: LoginItemBackend, @unchecked Sendable {
    let directory: URL
    let identity: LoginItemIdentity
    /// Starts a settings program; replaced by the tests.
    var launcher: (String, [String]) -> Bool = XDGAutostartBackend.launch

    init(directory: URL, identity: LoginItemIdentity) {
        self.directory = directory
        self.identity = identity
    }

    static func defaultDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let config = environment["XDG_CONFIG_HOME"], config.hasPrefix("/") {
            return URL(fileURLWithPath: config, isDirectory: true).appendingPathComponent("autostart", isDirectory: true)
        }
        let home = environment["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent(".config/autostart", isDirectory: true)
    }

    var entryURL: URL { directory.appendingPathComponent("\(identity.fileSafeIdentifier).desktop") }

    func status() -> SMAppService.Status {
        guard let text = try? String(contentsOf: entryURL, encoding: .utf8) else { return .notRegistered }
        let entry = XDGAutostartBackend.parse(text)
        guard let exec = entry["Exec"], XDGAutostartBackend.program(ofExec: exec) == identity.executablePath else {
            return .notRegistered   // someone else's entry under our name, or the app moved: register rewrites it
        }
        if entry["Hidden"]?.lowercased() == "true" || entry["X-GNOME-Autostart-enabled"]?.lowercased() == "false" {
            return .requiresApproval
        }
        return .enabled
    }

    func register() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try entryText().write(to: entryURL, atomically: true, encoding: .utf8)
    }

    func unregister() throws {
        try FileManager.default.removeItem(at: entryURL)
    }

    func entryText() -> String {
        """
        [Desktop Entry]
        Type=Application
        Version=1.5
        Name=\(XDGAutostartBackend.escapeString(identity.displayName))
        Exec=\(XDGAutostartBackend.quoteExecArgument(identity.executablePath))
        Terminal=false
        X-GNOME-Autostart-enabled=true
        X-AppKitCross-LoginItem=\(XDGAutostartBackend.escapeString(identity.identifier))

        """
    }

    func openSettings() {
        let env = ProcessInfo.processInfo.environment
        let desktop = (env["XDG_CURRENT_DESKTOP"] ?? "").uppercased()
        if desktop.contains("KDE") {
            if launcher("systemsettings", ["kcm_autostart"]) || launcher("kcmshell6", ["kcm_autostart"]) || launcher("kcmshell5", ["autostart"]) { return }
        }
        if desktop.contains("GNOME") || desktop.contains("UNITY") {
            if launcher("gnome-tweaks", []) || launcher("gnome-session-properties", []) { return }
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = launcher("xdg-open", [directory.path])
    }

    /// Starts `program` from PATH without waiting for it; false when it is not installed.
    static func launch(_ program: String, _ arguments: [String]) -> Bool {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin"
        for dir in path.split(separator: ":") {
            let candidate = "\(dir)/\(program)"
            guard FileManager.default.isExecutableFile(atPath: candidate) else { continue }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: candidate)
            process.arguments = arguments
            return (try? process.run()) != nil
        }
        return false
    }

    // MARK: Desktop entry syntax

    /// Key/value pairs of the [Desktop Entry] group, string escapes resolved.
    static func parse(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        var inEntry = false
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { inEntry = line == "[Desktop Entry]"; continue }
            guard inEntry, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard !key.contains("[") else { continue }   // localized keys
            values[key] = unescapeString(line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces))
        }
        return values
    }

    static func escapeString(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t").replacingOccurrences(of: "\r", with: "\\r")
    }

    static func unescapeString(_ s: String) -> String {
        var out = ""
        var escaping = false
        for c in s {
            if escaping {
                switch c {
                case "s": out.append(" ")
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                default: out.append(c)
                }
                escaping = false
            } else if c == "\\" {
                escaping = true
            } else {
                out.append(c)
            }
        }
        return out
    }

    private static let reserved: Set<Character> = [" ", "\t", "\n", "\"", "'", "\\", ">", "<", "~", "|", "&", ";", "$", "*", "?", "#", "(", ")", "`"]

    /// One Exec argument, quoted when it has reserved characters, with field codes escaped,
    /// and string-escaped for the desktop file.
    static func quoteExecArgument(_ argument: String) -> String {
        var arg = argument.replacingOccurrences(of: "%", with: "%%")
        if arg.contains(where: { reserved.contains($0) }) {
            var quoted = "\""
            for c in arg {
                if c == "\"" || c == "`" || c == "$" || c == "\\" { quoted.append("\\") }
                quoted.append(c)
            }
            quoted.append("\"")
            arg = quoted
        }
        return escapeString(arg)
    }

    /// The program (first argument) of an Exec value whose string escapes are resolved.
    static func program(ofExec exec: String) -> String {
        var out = ""
        var chars = exec.trimmingCharacters(in: .whitespaces)[...]
        if chars.first == "\"" {
            chars = chars.dropFirst()
            var escaping = false
            for c in chars {
                if escaping { out.append(c); escaping = false; continue }
                if c == "\\" { escaping = true; continue }
                if c == "\"" { break }
                out.append(c)
            }
        } else {
            out = String(chars.prefix { $0 != " " && $0 != "\t" })
        }
        return out.replacingOccurrences(of: "%%", with: "%")
    }
}
