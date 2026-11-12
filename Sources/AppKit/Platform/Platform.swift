import Foundation

/// The process-wide backend. Chosen at compile time; see `Package.swift` for how the
/// platform directories are selected.
@MainActor
public enum Platform {
    public static let backend: any PlatformBackend = makeBackend()

    private static func makeBackend() -> any PlatformBackend {
        #if os(Windows)
        // APPKITWIN_HOST_BACKEND=1 runs the headless host backend (unit tests), as on Linux.
        if ProcessInfo.processInfo.environment["APPKITWIN_HOST_BACKEND"] == "1" { return headlessHostBackend() }
        return Win32Backend()
        #elseif os(Linux)
        // APPKITWIN_HOST_BACKEND=1 runs the headless host backend (unit tests, CI without X).
        let env = ProcessInfo.processInfo.environment
        if env["APPKITWIN_HOST_BACKEND"] == "1" { return headlessHostBackend() }
        // APPKITWIN_LINUX_BACKEND=x11|wayland forces a window system; otherwise Wayland is
        // preferred when WAYLAND_DISPLAY is set and the connection succeeds, else X11.
        switch env["APPKITWIN_LINUX_BACKEND"]?.lowercased() {
        case "x11":
            return LinuxBackend()
        case "wayland":
            guard let wayland = WaylandBackend() else { fatalError("AppKitCross: cannot connect to the Wayland display (is WAYLAND_DISPLAY set?)") }
            return wayland
        default:
            if env["WAYLAND_DISPLAY"] != nil, let wayland = WaylandBackend() { return wayland }
            return LinuxBackend()
        }
        #else
        return HostBackend()
        #endif
    }

    #if os(Windows) || os(Linux)
    /// The headless backend outside the test runner: say so once, since the process then
    /// runs its whole life without a native window (a shell that still has the variable set
    /// from running the tests makes an example look as if it never created its window).
    private static func headlessHostBackend() -> any PlatformBackend {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil, !ProcessInfo.processInfo.arguments.contains(where: { $0.hasSuffix(".xctest") || $0.contains("PackageTests") }) {
            FileHandle.standardError.write(Data("AppKitCross: APPKITWIN_HOST_BACKEND=1 selects the headless host backend: no native window will appear (unset it to use the platform backend)\n".utf8))
        }
        return HostBackend()
    }
    #endif
}
