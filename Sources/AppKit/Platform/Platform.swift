import Foundation

/// The process-wide backend. Chosen at compile time; see `Package.swift` for how the
/// platform directories are selected.
@MainActor
public enum Platform {
    public static let backend: any PlatformBackend = makeBackend()

    private static func makeBackend() -> any PlatformBackend {
        #if os(Windows)
        return Win32Backend()
        #else
        return HostBackend()
        #endif
    }
}
