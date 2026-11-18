// One running instance per application (ADR-0045).
//
// On macOS LaunchServices sends a document or URL opened from the Finder, or a second launch,
// to the running application. On Windows Explorer and on Linux the desktop start a new process
// with the path or URL as its argument instead, so the port does the hand-off itself: when
// `NSApplication.shared` is first made, an application with a `CFBundleIdentifier` connects to
// the per-user channel of that identity (PlatformInstanceChannel); if an instance listens, this
// launch sends its arguments and working directory and exits; otherwise it becomes the instance
// others hand to. The running instance opens what it is given as it opens command-line
// arguments at launch (files through the delegate and the document controller, URLs through
// `application(_:open:)`); with nothing to open it reopens (`applicationShouldHandleReopen`)
// and comes to the front.
//
// Off: the host backend (tests), an Info.plist without `CFBundleIdentifier`,
// `AppKitCrossAllowsMultipleInstances` = YES in the Info.plist, `APPKITWIN_MULTIPLE_INSTANCES=1`,
// and the registration switches (`--appkitcross-register`, `--appkitcross-unregister`).

import Foundation

@MainActor
public enum _AppInstance {
    /// What a later launch hands over.
    struct Message: Codable, Equatable {
        var arguments: [String]
        var workingDirectory: String
    }

    nonisolated(unsafe) private static var channel: (any PlatformInstanceChannel)?
    private static var pending: [Message] = []
    private static var claimed = false

    /// Whether this launch takes part in the hand-off.
    static var isEnabled: Bool {
        let env = ProcessInfo.processInfo.environment
        #if os(Windows) || os(Linux)
        if env["APPKITWIN_HOST_BACKEND"] == "1" { return false }
        #else
        if env["APPKITWIN_SINGLE_INSTANCE_TEST"] != "1" { return false }
        #endif
        if env["APPKITWIN_MULTIPLE_INSTANCES"] == "1" { return false }
        if CommandLine.arguments.contains(where: { $0.hasPrefix("--appkitcross-") }) { return false }
        let info = _AppBundle.main.infoDictionary
        if (info["AppKitCrossAllowsMultipleInstances"] as? Bool) == true { return false }
        return (info["CFBundleIdentifier"] as? String).map { !$0.isEmpty } ?? false
    }

    /// Hands this launch to the running instance and exits, or starts listening.
    static func claim() {
        guard !claimed else { return }
        claimed = true
        guard isEnabled else { return }
        let ch = PlatformInstanceChannels.make(identifier: _AppBundle.main.platformIdentifier)
        let message = Message(arguments: Array(CommandLine.arguments.dropFirst()), workingDirectory: FileManager.default.currentDirectoryPath)
        guard let data = try? JSONEncoder().encode(message) else { return }
        // Two launches at once (a multi-file open from Explorer): the one that loses the race
        // to listen sends instead.
        for _ in 0..<5 {
            if ch.send(data) { exit(0) }
            if ch.listen({ data in DispatchQueue.main.async { MainActor.assumeIsolated { _AppInstance.receive(data) } } }) {
                channel = ch
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    static func receive(_ data: Data) {
        guard let message = try? JSONDecoder().decode(Message.self, from: data) else { return }
        if NSApplication.shared._isFinishedLaunching { deliver(message) } else { pending.append(message) }
    }

    /// Delivers what arrived while the application was launching.
    static func deliverPending() {
        let queued = pending
        pending = []
        for m in queued { deliver(m) }
    }

    static func deliver(_ message: Message) {
        let app = NSApplication.shared
        let items = launchItems(message.arguments, workingDirectory: message.workingDirectory)
        if !items.files.isEmpty || !items.urls.isEmpty {
            _ = app._openLaunchItems(files: items.files, urls: items.urls)
        } else {
            app._reopen()
        }
        app.activate(ignoringOtherApps: true)
        (app.mainWindow ?? app.keyWindow ?? app.windows.first { $0.isVisible })?.makeKeyAndOrderFront(nil)
    }

    /// The documents and URLs among command-line arguments: `-Key value` pairs (the
    /// argument domain, as `-AppleLanguages (de)`) and `--switches` are skipped, `file:` URLs
    /// become paths, a URL whose scheme the Info.plist declares (`CFBundleURLTypes`) or that
    /// has `://` is a URL, and anything else that exists relative to the working directory is
    /// a file.
    static func launchItems(_ arguments: [String], workingDirectory: String, schemes: Set<String>? = nil) -> (files: [String], urls: [URL]) {
        let declared = schemes ?? declaredSchemes
        var files: [String] = []
        var urls: [URL] = []
        var i = 0
        while i < arguments.count {
            let arg = arguments[i]
            i += 1
            if arg.hasPrefix("--") { continue }
            if arg.hasPrefix("-"), arg.count > 1 {
                if i < arguments.count, !arguments[i].hasPrefix("-") { i += 1 }
                continue
            }
            if let url = URL(string: arg), let scheme = url.scheme?.lowercased(), scheme.count > 1 {
                if scheme == "file" { files.append(url.path); continue }
                if declared.contains(scheme) || arg.contains("://") { urls.append(url); continue }
            }
            let path = (arg as NSString).isAbsolutePath || arg.hasPrefix("\\\\") || (arg.count > 2 && arg.dropFirst().hasPrefix(":"))
                ? arg : (workingDirectory as NSString).appendingPathComponent(arg)
            if FileManager.default.fileExists(atPath: path) { files.append((path as NSString).standardizingPath) }
        }
        return (files, urls)
    }

    /// The URL schemes the Info.plist's `CFBundleURLTypes` declare, lower-cased.
    static var declaredSchemes: Set<String> {
        let types = (_AppBundle.main.infoDictionary["CFBundleURLTypes"] as? [[String: Any]]) ?? []
        return Set(types.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }.map { $0.lowercased() })
    }

    /// Stops listening (tests).
    static func _resetForTesting() {
        channel?.close()
        channel = nil
        pending = []
        claimed = false
    }
}
