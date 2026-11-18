// ServiceManagement (ADR-0043): the Windows login item. The Run key value is the primary
// registration (what Task Manager's Startup apps lists); the Startup-folder shortcut is the
// fallback when policy keeps the Run key read-only. Both are per-user, no elevation.
// Task Manager and Settings record the user's on/off switch under
// HKCU\…\Explorer\StartupApproved\{Run,StartupFolder}; an entry switched off there reads
// back as `.requiresApproval`, which only the user can change.

#if os(Windows)
import Foundation
@_implementationOnly import CWinAppServices

final class WindowsLoginItemBackend: LoginItemBackend, @unchecked Sendable {
    let identity: LoginItemIdentity

    init(identity: LoginItemIdentity) { self.identity = identity }

    private var valueName: String { identity.fileSafeIdentifier }
    private var command: String { "\"\(identity.executablePath)\"" }

    private func runValue() -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard cwas_run_get(valueName, &buffer, Int32(buffer.count)) == 1 else { return nil }
        return String(cString: buffer)
    }

    func status() -> SMAppService.Status {
        if let value = runValue(), value.caseInsensitiveCompare(command) == .orderedSame {
            return cwas_startup_approved(0, valueName) == 0 ? .requiresApproval : .enabled
        }
        if cwas_shortcut_exists(valueName) == 1 {
            return cwas_startup_approved(1, valueName + ".lnk") == 0 ? .requiresApproval : .enabled
        }
        return .notRegistered
    }

    func register() throws {
        if cwas_run_set(valueName, command) == 0 { return }
        let hr = cwas_shortcut_create(valueName, identity.executablePath, identity.displayName)
        guard hr == 0 else {
            throw SMAppService.error(kSMErrorInternalFailure, "Neither the Run key nor the Startup folder could be written (HRESULT 0x\(String(UInt32(bitPattern: hr), radix: 16))).")
        }
    }

    func unregister() throws {
        let run = cwas_run_delete(valueName)
        let link = cwas_shortcut_delete(valueName)
        guard run == 0 && link == 0 else {
            throw SMAppService.error(kSMErrorInternalFailure, "The login item could not be removed.")
        }
    }

    func openSettings() {
        _ = cwas_open_uri("ms-settings:startupapps")
    }
}
#endif
