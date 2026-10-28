import Foundation

/// The process-wide backend. Chosen at compile time; see `Package.swift` for how the
/// platform directories are selected.
@MainActor
public enum Platform {
    public static let backend: any PlatformBackend = makeBackend()

    private static func makeBackend() -> any PlatformBackend {
        #if os(Windows)
        // APPKITWIN_HOST_BACKEND=1 runs the headless host backend (unit tests), as on Linux.
        if ProcessInfo.processInfo.environment["APPKITWIN_HOST_BACKEND"] == "1" { return HostBackend() }
        return Win32Backend()
        #elseif os(Linux)
        // APPKITWIN_HOST_BACKEND=1 runs the headless host backend (unit tests, CI without X).
        let env = ProcessInfo.processInfo.environment
        if env["APPKITWIN_HOST_BACKEND"] == "1" { return HostBackend() }
        // APPKITWIN_LINUX_BACKEND=x11|wayland forces a window system; otherwise Wayland is
        // preferred when WAYLAND_DISPLAY is set and the connection succeeds, else X11.
        switch env["APPKITWIN_LINUX_BACKEND"]?.lowercased() {
        case "x11":
            return LinuxBackend()
        case "wayland":
            guard let wayland = WaylandBackend() else { fatalError("AppKitWin: cannot connect to the Wayland display (is WAYLAND_DISPLAY set?)") }
            return wayland
        default:
            if env["WAYLAND_DISPLAY"] != nil, let wayland = WaylandBackend() { return wayland }
            return LinuxBackend()
        }
        #else
        return HostBackend()
        #endif
    }
}
