// The crash report seam (ADR-0046). NSApplication installs the CCrashReport shim's handler
// when it is created, on Windows and Linux: an unhandled-exception filter that writes a
// minidump and a text report under %LOCALAPPDATA%\<bundle id>\Crashes, or a signal handler
// that writes a backtrace report under ~/.local/share/<bundle id>/Crashes
// ($XDG_DATA_HOME when set). On the macOS host build Apple's crash reporter owns crashes
// and nothing is installed; the tests drive the shim directly.
//
// Environment:
//   APPKITWIN_CRASH_REPORTER=0   do not install the handler (a debugger, another reporter)
//   APPKITWIN_CRASH_DIR=<dir>    write reports there instead
//   APPKITWIN_CRASH_TEST=1       crash on purpose about a second after launch, to check the
//                                path end to end; `trap` (what fatalError executes), `abort`
//                                and `segv` (the default) pick how

import Foundation
// Implementation-only: no client of AppKit needs the shim's module map (on macOS the XCTest
// interface build loads this AppKit and would otherwise fail to find it).
@_implementationOnly import CCrashReport

public enum PlatformCrashReporting {
    /// Where this application's reports go: `APPKITWIN_CRASH_DIR`, else the per-user data
    /// directory of the platform under the bundle identifier.
    public static func reportsDirectory(bundleIdentifier: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let dir = environment["APPKITWIN_CRASH_DIR"], !dir.isEmpty { return URL(fileURLWithPath: dir, isDirectory: true) }
        #if os(Windows)
        let base = environment["LOCALAPPDATA"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        #else
        let base: URL
        if let xdg = environment["XDG_DATA_HOME"], xdg.hasPrefix("/") {
            base = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            let home = environment["HOME"] ?? NSHomeDirectory()
            base = URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent(".local/share", isDirectory: true)
        }
        #endif
        return base.appendingPathComponent(bundleIdentifier, isDirectory: true).appendingPathComponent("Crashes", isDirectory: true)
    }

    /// The identifier reports are filed under: the Info.plist's `CFBundleIdentifier`, else
    /// the executable's name.
    public static var applicationIdentifier: String {
        if let id = Bundle.main.bundleIdentifier, !id.isEmpty { return id }
        var name = ProcessInfo.processInfo.processName
        if name.lowercased().hasSuffix(".exe") { name = String(name.dropLast(4)) }
        return name.isEmpty ? "app" : name
    }

    static var applicationName: String {
        var name = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? ProcessInfo.processInfo.processName
        if name.lowercased().hasSuffix(".exe") { name = String(name.dropLast(4)) }
        return name.isEmpty ? "app" : name
    }

    /// Installs the handler into `directory` (default: `reportsDirectory`), which is created
    /// when the first report is written. Returns false for an unusable path.
    @discardableResult
    public static func install(directory: URL? = nil) -> Bool {
        let identifier = applicationIdentifier
        let dir = directory ?? reportsDirectory(bundleIdentifier: identifier)
        return ccrash_install(dir.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? dir.path,
                              applicationName, identifier) == 1
    }

    /// Points `writeReport` at `directory` without installing a handler (tests, tools).
    @discardableResult
    public static func configure(directory: URL) -> Bool {
        ccrash_configure(directory.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? directory.path,
                         applicationName, applicationIdentifier) == 1
    }

    /// Whether a handler is installed in this process.
    public static var isInstalled: Bool { ccrash_installed() == 1 }

    /// The last report this process wrote, if any.
    public static var lastReport: URL? {
        let path = String(cString: ccrash_last_report())
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }

    /// Writes a report for the calling thread without crashing (diagnostics, tests).
    @discardableResult
    public static func writeReport(reason: String) -> Bool { ccrash_write_report(reason) == 1 }

    nonisolated(unsafe) private static var launchHandled = false

    /// Called from `NSApplication.init`: installs the handler on Windows and Linux unless
    /// `APPKITWIN_CRASH_REPORTER=0`, and nowhere under XCTest (the test runner reports its
    /// own crashes).
    static func installAtLaunch() {
        #if os(Windows) || os(Linux)
        guard !launchHandled else { return }
        launchHandled = true
        let env = ProcessInfo.processInfo.environment
        if env["APPKITWIN_CRASH_REPORTER"] == "0" { return }
        if env["XCTestConfigurationFilePath"] != nil || ProcessInfo.processInfo.arguments.contains(where: { $0.hasSuffix(".xctest") || $0.contains("PackageTests") }) { return }
        if !install() {
            FileHandle.standardError.write(Data("AppKitCross: cannot use the crash report directory \(reportsDirectory(bundleIdentifier: applicationIdentifier).path); crash reports are off\n".utf8))
        }
        #endif
    }

    /// `APPKITWIN_CRASH_TEST`: the kind of crash asked for, or nil.
    static func requestedCrashTest(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Int32? {
        guard let value = environment["APPKITWIN_CRASH_TEST"]?.lowercased(), !value.isEmpty, value != "0" else { return nil }
        switch value {
        case "trap", "fatalerror": return 1
        case "abort": return 2
        default: return 0
        }
    }

    /// Called at the end of `finishLaunching`: with `APPKITWIN_CRASH_TEST` set, crashes about
    /// a second later, once the first window has had time to appear.
    @MainActor static func scheduleCrashTestIfRequested() {
        guard let kind = requestedCrashTest() else { return }
        FileHandle.standardError.write(Data("AppKitCross: APPKITWIN_CRASH_TEST is set; crashing in one second\n".utf8))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            ccrash_crash_now(kind)
        }
    }
}
