import Foundation

/// The process-wide backend. Chosen at compile time; see `Package.swift` for how the
/// platform directories are selected.
@MainActor
public enum Platform {
    public static let backend: any PlatformBackend = makeBackend()

    private static func makeBackend() -> any PlatformBackend {
        #if os(Windows)
        return Win32Backend()
        #elseif os(Linux)
        // APPKITWIN_HOST_BACKEND=1 runs the headless host backend (unit tests, CI without X).
        if ProcessInfo.processInfo.environment["APPKITWIN_HOST_BACKEND"] == "1" { return HostBackend() }
        return LinuxBackend()
        #else
        return HostBackend()
        #endif
    }
}
