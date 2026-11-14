// Shim for Apple's ServiceManagement framework (Windows and Linux only; the macOS host build
// uses the real one). Port gap: AppKitCross has no ServiceManagement module, and the upstream
// app (LoginItemController.swift) registers itself as a login item through `SMAppService`.
// The shim keeps the API the app uses — `SMAppService.mainApp`, `status`, `register()` and
// `unregister()` — and reports the service as not found, so the app's "Open at login" button
// shows an error instead of crashing. Follow-up for the port: a real login item over the
// Run registry key / Startup folder on Windows and an XDG autostart desktop entry on Linux.
import Foundation

public final class SMAppService: NSObject, @unchecked Sendable {
    public enum Status: Int, Sendable {
        case notRegistered = 0, enabled, requiresApproval, notFound
    }

    public struct Error: LocalizedError {
        public var errorDescription: String? { "Login items are not available on this platform yet." }
    }

    public static let mainApp = SMAppService()
    override private init() { super.init() }

    public var status: Status { .notFound }
    public func register() throws { throw Error() }
    public func unregister() throws { throw Error() }
}
