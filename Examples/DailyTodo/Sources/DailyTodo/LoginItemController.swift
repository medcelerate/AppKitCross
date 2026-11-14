import Foundation
import ServiceManagement

enum LoginItemError: LocalizedError {
    case notRunningFromAppBundle
    case requiresApproval

    var errorDescription: String? {
        switch self {
        case .notRunningFromAppBundle:
            return "Install and open the app bundle before enabling login items."
        case .requiresApproval:
            return "Enable Daily To Do in System Settings under General > Login Items."
        }
    }
}

struct LoginItemController {
    func install() throws {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            throw LoginItemError.notRunningFromAppBundle
        }

        let service = SMAppService.mainApp
        if service.status == .requiresApproval {
            throw LoginItemError.requiresApproval
        }
        guard service.status != .enabled else { return }
        try service.register()

        if service.status == .requiresApproval {
            throw LoginItemError.requiresApproval
        }
    }

    func uninstall() throws {
        let service = SMAppService.mainApp
        guard service.status != .notRegistered else { return }
        try service.unregister()
    }
}
