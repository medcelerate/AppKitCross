// The registration of ADR-0045 on Linux: the XDG files (Support/AppRegistration.swift's
// `_XDGRegistrar`) under `$XDG_DATA_HOME` (`~/.local/share`), then the desktop's caches:
// `update-mime-database` for the MIME package, `update-desktop-database` for the MimeType
// index, and `xdg-mime default` for the Owner types that have no default handler yet.

#if os(Linux)
import Foundation

private var dataHome: URL {
    let env = ProcessInfo.processInfo.environment
    if let d = env["XDG_DATA_HOME"], !d.isEmpty { return URL(fileURLWithPath: d, isDirectory: true) }
    return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent(".local/share", isDirectory: true)
}

/// Runs a tool from PATH; its standard output, nil when it is missing or fails.
@discardableResult
private func runTool(_ name: String, _ arguments: [String]) -> String? {
    let path = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin").split(separator: ":")
        .map { String($0) + "/" + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
    guard let path else { return nil }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = arguments
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
}

func _platformRegisterApplication(_ plan: _AppRegistration, iconPNG: Data?) throws {
    let home = dataHome
    let written = try _XDGRegistrar.write(plan, dataHome: home, iconPNG: iconPNG)
    if written.mimePackage != nil { runTool("update-mime-database", [home.appendingPathComponent("mime").path]) }
    runTool("update-desktop-database", [home.appendingPathComponent("applications").path])
    for mime in plan.ownedMIMETypes {
        let current = runTool("xdg-mime", ["query", "default", mime])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if current.isEmpty { runTool("xdg-mime", ["default", plan.desktopFileName, mime]) }
    }
}

func _platformUnregisterApplication(_ plan: _AppRegistration) throws {
    let home = dataHome
    _XDGRegistrar.remove(plan, dataHome: home)
    runTool("update-mime-database", [home.appendingPathComponent("mime").path])
    runTool("update-desktop-database", [home.appendingPathComponent("applications").path])
}

func _platformIsApplicationRegistered(_ plan: _AppRegistration) -> Bool {
    _XDGRegistrar.isRegistered(plan, dataHome: dataHome)
}
#endif
