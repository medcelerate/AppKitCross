// ServiceManagement (ADR-0043): SMAppService for the app's own login item on Windows and
// Linux.
//
// `SMAppService.mainApp` registers the running executable to start at login:
//   Windows  a value named after the app under HKCU\Software\Microsoft\Windows\CurrentVersion\
//            Run holding the quoted executable path; when the Run key cannot be written
//            (policy), a shortcut in the user's Startup folder instead. Turning the app off in
//            Task Manager's Startup apps (or Settings › Apps › Startup) is the user's approval
//            switch: `status` reads it back as `.requiresApproval`.
//   Linux    an XDG autostart entry, $XDG_CONFIG_HOME/autostart/<app id>.desktop (default
//            ~/.config/autostart). An entry the user turned off in their desktop's startup
//            settings (Hidden=true or X-GNOME-Autostart-enabled=false) reads back as
//            `.requiresApproval`.
// `status` reads back what is registered each time, so changes made outside the app show.
// Helper services (`loginItem(identifier:)`, launch agents and daemons) need bundle
// layouts the port's apps do not have and are not provided.
//
// On macOS the package does not build this module for apps (they get Apple's); the tests
// compile it there as `ServiceManagementPortable`.

import Foundation

/// The error domain SMAppService's errors carry on macOS (not exported by Apple's headers).
let SMAppServiceErrorDomain = "SMAppServiceErrorDomain"

public var kSMErrorInternalFailure: Int { 2 }
public var kSMErrorInvalidSignature: Int { 3 }
public var kSMErrorAuthorizationFailure: Int { 4 }
public var kSMErrorToolNotValid: Int { 5 }
public var kSMErrorJobNotFound: Int { 6 }
public var kSMErrorServiceUnavailable: Int { 7 }
public var kSMErrorJobPlistNotFound: Int { 8 }
public var kSMErrorJobMustBeEnabled: Int { 9 }
public var kSMErrorInvalidPlist: Int { 10 }
public var kSMErrorLaunchDeniedByUser: Int { 11 }
public var kSMErrorAlreadyRegistered: Int { 12 }

/// - SeeAlso: https://developer.apple.com/documentation/servicemanagement/smappservice
open class SMAppService: NSObject, @unchecked Sendable {
    /// - SeeAlso: https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum
    public enum Status: Int, Sendable {
        case notRegistered = 0
        case enabled = 1
        case requiresApproval = 2
        case notFound = 3
    }

    let backend: LoginItemBackend

    init(backend: LoginItemBackend) {
        self.backend = backend
        super.init()
    }

    private static let _mainApp = SMAppService(backend: makeDefaultLoginItemBackend())

    /// - SeeAlso: https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp
    open class var mainApp: SMAppService { _mainApp }

    /// - SeeAlso: https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.property
    open var status: SMAppService.Status { backend.status() }

    /// - SeeAlso: https://developer.apple.com/documentation/servicemanagement/smappservice/register()
    open func register() throws {
        do {
            try backend.register()
        } catch let error as NSError where error.domain == SMAppServiceErrorDomain {
            throw error
        } catch {
            throw SMAppService.error(kSMErrorInternalFailure, "Could not register the login item: \(error.localizedDescription)", underlying: error)
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/servicemanagement/smappservice/unregister()
    open func unregister() throws {
        guard backend.status() != .notRegistered else {
            throw SMAppService.error(kSMErrorJobNotFound, "The login item is not registered.")
        }
        do {
            try backend.unregister()
        } catch let error as NSError where error.domain == SMAppServiceErrorDomain {
            throw error
        } catch {
            throw SMAppService.error(kSMErrorInternalFailure, "Could not unregister the login item: \(error.localizedDescription)", underlying: error)
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/servicemanagement/smappservice/unregister(completionhandler:)
    open func unregister(completionHandler: @escaping @Sendable ((any Error)?) -> Void) {
        let result: (any Error)?
        do { try unregister(); result = nil } catch { result = error }
        DispatchQueue.global().async { completionHandler(result) }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/servicemanagement/smappservice/unregister(completionhandler:)
    open func unregister() async throws {
        let unregisterNow: () throws -> Void = unregister
        try unregisterNow()
    }

    /// Opens the platform's startup-apps settings: Settings › Apps › Startup on Windows; the
    /// desktop's autostart settings on Linux (KDE's Autostart module, GNOME Tweaks), or the
    /// autostart folder in the file manager when neither is installed.
    /// - SeeAlso: https://developer.apple.com/documentation/servicemanagement/smappservice/opensystemsettingsloginitems()
    open class func openSystemSettingsLoginItems() {
        _mainApp.backend.openSettings()
    }

    static func error(_ code: Int, _ description: String, underlying: (any Error)? = nil) -> NSError {
        var info: [String: Any] = [NSLocalizedDescriptionKey: description]
        if let underlying { info[NSUnderlyingErrorKey] = underlying as NSError }
        return NSError(domain: SMAppServiceErrorDomain, code: code, userInfo: info)
    }
}
