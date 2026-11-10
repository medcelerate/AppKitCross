// NSRunningApplication (hand-written; ADR-0022). One object per process the platform
// counts as an application (Platform/Workspace.swift); `NSWorkspace` owns the objects
// and refreshes them from the platform's process list and events, so the same instance
// answers for a process until it terminates. The current application is special: its
// activation and hidden state come from `NSApplication` itself.
//
// Key-value observing of these properties needs the Objective-C runtime; on Windows and
// Linux the `NSWorkspace` notifications (didActivate, didHide, didTerminate, ...) carry
// the same changes with the application under `applicationUserInfoKey`.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// `NSBundleExecutableArchitecture…` as Foundation declares them.
private let _archI386 = 0x00000007, _archX86_64 = 0x01000007, _archARM64 = 0x0100000c

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication
open class NSRunningApplication: NSObject, @unchecked Sendable {
    // The properties answer on any thread, as Apple's do: the state sits behind a lock and
    // the workspace (main actor) updates it; the current application's activation and
    // hidden state are read from NSApplication on the main thread.
    private let _lock = NSLock()
    nonisolated(unsafe) private var _storage: PlatformRunningApplication
    nonisolated(unsafe) private var _terminatedStorage = false
    internal var _info: PlatformRunningApplication {
        get { _lock.lock(); defer { _lock.unlock() }; return _storage }
        set { _lock.lock(); _storage = newValue; _lock.unlock() }
    }
    internal var _terminated: Bool {
        get { _lock.lock(); defer { _lock.unlock() }; return _terminatedStorage }
        set { _lock.lock(); _terminatedStorage = newValue; _lock.unlock() }
    }
    private var _isCurrent: Bool { _info.processIdentifier == ProcessInfo.processInfo.processIdentifier }
    /// Runs `body` on the main actor (synchronously from other threads).
    private func _main<T>(_ body: @MainActor () -> T) -> T { NSWorkspace.shared._onMain(body) }

    internal init(_info: PlatformRunningApplication) {
        self._storage = _info
        super.init()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/init(processidentifier:)
    public convenience init?(processIdentifier pid: pid_t) {
        // Apple answers with the shared object for the process; a Swift initializer cannot,
        // so this is a copy of the workspace's object (`NSWorkspace.runningApplications`
        // and the notifications carry the shared ones).
        guard let state = NSWorkspace.shared._onMain({ () -> (PlatformRunningApplication, Bool)? in
            guard let app = NSWorkspace.shared._application(withProcessIdentifier: Int32(pid)) else { return nil }
            return (app._info, app._terminated)
        }) else { return nil }
        self.init(_info: state.0)
        _terminated = state.1
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/current
    class public var current: NSRunningApplication {
        NSWorkspace.shared._onMain {
            if let c = NSWorkspace.shared._currentApplication { return c }
            var info = Platform.backend.workspace.runningApplication(withProcessIdentifier: ProcessInfo.processInfo.processIdentifier)
                ?? PlatformRunningApplication(processIdentifier: ProcessInfo.processInfo.processIdentifier)
            if info.localizedName == nil {
                info.localizedName = (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? ProcessInfo.processInfo.processName
            }
            if info.bundleIdentifier == nil { info.bundleIdentifier = Bundle.main.bundleIdentifier }
            if info.executableURL == nil, let path = CommandLine.arguments.first { info.executableURL = URL(fileURLWithPath: path) }
            info.launchDate = Date(timeIntervalSinceNow: -ProcessInfo.processInfo.systemUptime + _processStartUptime)
            let app = NSRunningApplication(_info: info)
            NSWorkspace.shared._currentApplication = app
            return app
        }
    }
    /// The system uptime when the process started (its launch date relative to now).
    nonisolated(unsafe) private static let _processStartUptime = ProcessInfo.processInfo.systemUptime

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/runningapplications(withbundleidentifier:)
    public class func runningApplications(withBundleIdentifier bundleIdentifier: String) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleIdentifier }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/terminateautomaticallyterminableapplications()
    public class func terminateAutomaticallyTerminableApplications() { unimplemented() }

    // MARK: Identity

    @MainActor private var _app: NSApplication? { _isCurrent ? NSApplication._shared : nil }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/processidentifier
    open var processIdentifier: pid_t { pid_t(_info.processIdentifier) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/bundleidentifier
    open var bundleIdentifier: String? { _info.bundleIdentifier }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/bundleurl
    open var bundleURL: URL? { _info.applicationURL ?? _info.executableURL }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/executableurl
    open var executableURL: URL? { _info.executableURL }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/localizedname
    open var localizedName: String? { _info.localizedName }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/launchdate
    open var launchDate: Date? { _info.launchDate }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/executablearchitecture
    open var executableArchitecture: Int {
        _main {
            if _isCurrent {
                #if arch(arm64)
                return _archARM64
                #elseif arch(x86_64)
                return _archX86_64
                #elseif arch(i386)
                return _archI386
                #else
                return 0
                #endif
            }
            guard let arch = Platform.backend.workspace.executableArchitecture(processIdentifier: _info.processIdentifier) else { unimplemented() }
            return arch
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/icon
    open var icon: NSImage? {
        _main {
            if let app = _app, let image = app._applicationIconImageIfSet { return image }
            let target: PlatformIconTarget = _info.applicationURL.map { .application($0) } ?? .process(_info.processIdentifier)
            return NSWorkspace.shared._icon(for: target, size: 128)
        }
    }

    // MARK: State

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/activationpolicy
    open var activationPolicy: NSApplication.ActivationPolicy {
        guard _isCurrent else { return _info.hasWindows ? .regular : .prohibited }
        return _main { _app?.activationPolicy() ?? .regular }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/isactive
    open var isActive: Bool {
        guard _isCurrent else { return _info.isActive && !_terminated }
        return _main { _app?.isActive ?? _info.isActive }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/isfinishedlaunching
    open var isFinishedLaunching: Bool {
        guard _isCurrent else { return !_terminated }
        return _main { _app?._isFinishedLaunching ?? true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/ishidden
    open var isHidden: Bool {
        guard _isCurrent else { return _info.isHidden }
        return _main { _app?.isHidden ?? _info.isHidden }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/isterminated
    open var isTerminated: Bool { _terminated }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/ownsmenubar
    open var ownsMenuBar: Bool { isActive }

    // MARK: Actions

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/activate(options:)
    open func activate(options: NSApplication.ActivationOptions = []) -> Bool {
        NSWorkspace.shared._onMain {
            guard !_terminated else { return false }
            if let app = _app { app.activate(ignoringOtherApps: options.contains(.activateIgnoringOtherApps)); return true }
            if options.contains(.activateAllWindows) || _info.isHidden { _ = Platform.backend.workspace.unhide(processIdentifier: _info.processIdentifier) }
            return Platform.backend.workspace.activate(processIdentifier: _info.processIdentifier)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/activate(from:options:)
    @available(macOS 14.0, *)
    open func activate(from application: NSRunningApplication, options: NSApplication.ActivationOptions = []) -> Bool { activate(options: options) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/hide()
    open func hide() -> Bool {
        NSWorkspace.shared._onMain {
            guard !_terminated else { return false }
            if let app = _app { app.hide(nil); return true }
            guard Platform.backend.workspace.hide(processIdentifier: _info.processIdentifier) else { return false }
            _info.isHidden = true
            return true
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/unhide()
    open func unhide() -> Bool {
        NSWorkspace.shared._onMain {
            guard !_terminated else { return false }
            if let app = _app { app.unhideWithoutActivation(); return true }
            guard Platform.backend.workspace.unhide(processIdentifier: _info.processIdentifier) else { return false }
            _info.isHidden = false
            return true
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/terminate()
    open func terminate() -> Bool {
        NSWorkspace.shared._onMain {
            guard !_terminated else { return false }
            if let app = _app { app.terminate(nil); return true }
            return Platform.backend.workspace.terminate(processIdentifier: _info.processIdentifier, force: false)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrunningapplication/forceterminate()
    open func forceTerminate() -> Bool {
        NSWorkspace.shared._onMain {
            guard !_terminated else { return false }
            if _isCurrent { exit(0) }
            return Platform.backend.workspace.terminate(processIdentifier: _info.processIdentifier, force: true)
        }
    }

    // MARK: Updates from the workspace

    @MainActor internal func _update(_ info: PlatformRunningApplication, workspace: NSWorkspace, posting: Bool) {
        let wasHidden = _info.isHidden
        _info = info
        if posting, wasHidden != info.isHidden {
            workspace._notificationCenterForPosting.post(name: info.isHidden ? NSWorkspace.didHideApplicationNotification : NSWorkspace.didUnhideApplicationNotification,
                                                         object: workspace, userInfo: [NSWorkspace.applicationUserInfoKey: self])
        }
    }
    @MainActor internal func _setActive(_ active: Bool) { _info.isActive = active }
    @MainActor internal func _setHidden(_ hidden: Bool) { _info.isHidden = hidden }
    @MainActor internal func _markTerminated() { _terminated = true; _info.isActive = false }

    open override var description: String {
        "<NSRunningApplication pid=\(_info.processIdentifier) \(_info.bundleIdentifier ?? _info.localizedName ?? "?")\(_terminated ? " terminated" : "")>"
    }
    open override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? NSRunningApplication else { return false }
        return other === self || other.processIdentifier == processIdentifier
    }
    open override var hash: Int { Int(processIdentifier) }
}
