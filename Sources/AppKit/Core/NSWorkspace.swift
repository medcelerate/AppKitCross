// NSWorkspace (hand-written; ADR-0022). The shell's services behind Apple's API: opening
// URLs and files with their registered applications, revealing files in the file
// manager, file and application icons, file associations, the trash, the running
// applications with their activation and lifetime notifications, power, session and
// accessibility-settings notifications, the desktop picture, and file types through
// UniformTypeIdentifiers. The platform half is `PlatformWorkspace` (Platform/Workspace.swift).
//
// Members marked unimplemented() have no counterpart on Windows or Linux; the ADR lists them.

import Foundation
import UniformTypeIdentifiers
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace
open class NSWorkspace: NSObject {
    // MARK: Storage
    nonisolated(unsafe) private static var _shared: NSWorkspace?
    private let _notificationCenter = NotificationCenter()
    internal var _notificationCenterForPosting: NotificationCenter { _notificationCenter }
    /// The running applications by process id: one object per process, kept until it is
    /// seen terminated, as Apple's workspace does.
    @MainActor private var _applications: [Int32: NSRunningApplication] = [:]
    @MainActor private var _applicationsRefreshed = false
    @MainActor private var _monitoring = false
    @MainActor private var _lastActivePID: Int32? = nil
    /// A refresh in progress, and the list it last produced: an observer of a notification
    /// posted mid-refresh that asks for the applications gets that list, not a nested refresh.
    @MainActor private var _refreshing = false
    @MainActor private var _liveApplications: [NSRunningApplication] = []
    @MainActor private var _iconCache: [PlatformIconTarget: NSImage] = [:]
    @MainActor internal var _currentApplication: NSRunningApplication?

    public override init() { super.init() }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/shared
    class public var shared: NSWorkspace {
        if let s = _shared { return s }
        let s = NSWorkspace()
        _shared = s
        return s
    }

    /// Runs `body` on the main actor: the platform's services are main-actor bound.
    internal func _onMain<T>(_ body: @MainActor () throws -> T) rethrows -> T {
        if Thread.isMainThread { return try MainActor.assumeIsolated { try body() } }
        return try DispatchQueue.main.sync { try MainActor.assumeIsolated { try body() } }
    }
    @MainActor internal var _platform: any PlatformWorkspace { Platform.backend.workspace }

    @MainActor internal func _startMonitoringIfNeeded() {
        guard !_monitoring else { return }
        _monitoring = true
        _platform.observer = self
        _platform.startMonitoring()
        _refreshApplications(postingChanges: false)
    }

    // MARK: Notifications

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/notificationcenter
    open var notificationCenter: NotificationCenter {
        _onMain { _startMonitoringIfNeeded() }
        return _notificationCenter
    }
    @MainActor private func _post(_ name: NSNotification.Name, application: NSRunningApplication? = nil) {
        var info: [AnyHashable: Any] = [:]
        if let application { info[NSWorkspace.applicationUserInfoKey] = application }
        _notificationCenter.post(name: name, object: self, userInfo: info.isEmpty ? nil : info)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayoptionsdidchangenotification
    @available(macOS 10.10, *)
    static public var accessibilityDisplayOptionsDidChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification
    static public var activeSpaceDidChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWorkspaceActiveSpaceDidChangeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification
    static public var didActivateApplicationNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWorkspaceDidActivateApplicationNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/didchangefilelabelsnotification
    static public var didChangeFileLabelsNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWorkspaceDidChangeFileLabelsNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/diddeactivateapplicationnotification
    static public var didDeactivateApplicationNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWorkspaceDidDeactivateApplicationNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/didhideapplicationnotification
    static public var didHideApplicationNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWorkspaceDidHideApplicationNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/didlaunchapplicationnotification
    static public var didLaunchApplicationNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWorkspaceDidLaunchApplicationNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/didmountnotification
    static public var didMountNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWorkspaceDidMountNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/didperformfileoperationnotification
    static public var didPerformFileOperationNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWorkspaceDidPerformFileOperationNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/didrenamevolumenotification
    static public var didRenameVolumeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWorkspaceDidRenameVolumeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/didterminateapplicationnotification
    static public var didTerminateApplicationNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWorkspaceDidTerminateApplicationNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/didunhideapplicationnotification
    static public var didUnhideApplicationNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWorkspaceDidUnhideApplicationNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/didunmountnotification
    static public var didUnmountNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWorkspaceDidUnmountNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification
    static public var didWakeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWorkspaceDidWakeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/screensdidsleepnotification
    static public var screensDidSleepNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWorkspaceScreensDidSleepNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/screensdidwakenotification
    static public var screensDidWakeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWorkspaceScreensDidWakeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/sessiondidbecomeactivenotification
    static public var sessionDidBecomeActiveNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWorkspaceSessionDidBecomeActiveNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/sessiondidresignactivenotification
    static public var sessionDidResignActiveNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWorkspaceSessionDidResignActiveNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/willlaunchapplicationnotification
    static public var willLaunchApplicationNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWorkspaceWillLaunchApplicationNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/willpoweroffnotification
    static public var willPowerOffNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWorkspaceWillPowerOffNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification
    static public var willSleepNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWorkspaceWillSleepNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/willunmountnotification
    static public var willUnmountNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWorkspaceWillUnmountNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/applicationuserinfokey
    static public var applicationUserInfoKey: String { "NSWorkspaceApplicationKey" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/localizedvolumenameuserinfokey
    static public var localizedVolumeNameUserInfoKey: String { "NSWorkspaceVolumeLocalizedNameKey" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/oldlocalizedvolumenameuserinfokey
    static public var oldLocalizedVolumeNameUserInfoKey: String { "NSWorkspaceVolumeOldLocalizedNameKey" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/oldvolumeurluserinfokey
    static public var oldVolumeURLUserInfoKey: String { "NSWorkspaceVolumeOldURLKey" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/volumeurluserinfokey
    static public var volumeURLUserInfoKey: String { "NSWorkspaceVolumeURLKey" }

    // MARK: Opening URLs and applications

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/open(_:)
    open func open(_ url: URL) -> Bool { _onMain { _platform.open(url) } }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/open(_:configuration:)
    @available(macOS 10.15, *)
    open func open(_ url: URL, configuration: NSWorkspace.OpenConfiguration) async throws -> NSRunningApplication {
        try await MainActor.run { try _launch(urls: [url], application: nil, configuration: configuration) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/open(_:configuration:completionhandler:)
    @available(macOS 10.15, *)
    open func open(_ url: URL, configuration: NSWorkspace.OpenConfiguration, completionHandler: (@Sendable (NSRunningApplication?, (any Error)?) -> Void)? = nil) {
        _complete(completionHandler) { try self._launch(urls: [url], application: nil, configuration: configuration) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/open(_:withapplicationat:configuration:)
    @available(macOS 10.15, *)
    open func open(_ urls: [URL], withApplicationAt applicationURL: URL, configuration: NSWorkspace.OpenConfiguration) async throws -> NSRunningApplication {
        try await MainActor.run { try _launch(urls: urls, application: applicationURL, configuration: configuration) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/open(_:withapplicationat:configuration:completionhandler:)
    @available(macOS 10.15, *)
    open func open(_ urls: [URL], withApplicationAt applicationURL: URL, configuration: NSWorkspace.OpenConfiguration, completionHandler: (@Sendable (NSRunningApplication?, (any Error)?) -> Void)? = nil) {
        _complete(completionHandler) { try self._launch(urls: urls, application: applicationURL, configuration: configuration) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/openapplication(at:configuration:)
    @available(macOS 10.15, *)
    open func openApplication(at applicationURL: URL, configuration: NSWorkspace.OpenConfiguration) async throws -> NSRunningApplication {
        try await MainActor.run { try _launch(urls: [], application: applicationURL, configuration: configuration) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/openapplication(at:configuration:completionhandler:)
    @available(macOS 10.15, *)
    open func openApplication(at applicationURL: URL, configuration: NSWorkspace.OpenConfiguration, completionHandler: (@Sendable (NSRunningApplication?, (any Error)?) -> Void)? = nil) {
        _complete(completionHandler) { try self._launch(urls: [], application: applicationURL, configuration: configuration) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/open(_:options:configuration:)
    @available(macOS 10.10, *)
    open func open(_ url: URL, options: NSWorkspace.LaunchOptions = [], configuration: [NSWorkspace.LaunchConfigurationKey : Any]) throws -> NSRunningApplication {
        try _onMain { try _launch(urls: [url], application: nil, configuration: OpenConfiguration(launchOptions: options, configuration: configuration)) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/open(_:withapplicationat:options:configuration:)
    @available(macOS 10.10, *)
    open func open(_ urls: [URL], withApplicationAt applicationURL: URL, options: NSWorkspace.LaunchOptions = [], configuration: [NSWorkspace.LaunchConfigurationKey : Any]) throws -> NSRunningApplication {
        try _onMain { try _launch(urls: urls, application: applicationURL, configuration: OpenConfiguration(launchOptions: options, configuration: configuration)) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/launchapplication(at:options:configuration:)
    open func launchApplication(at url: URL, options: NSWorkspace.LaunchOptions = [], configuration: [NSWorkspace.LaunchConfigurationKey : Any]) throws -> NSRunningApplication {
        try _onMain { try _launch(urls: [], application: url, configuration: OpenConfiguration(launchOptions: options, configuration: configuration)) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/launchapplication(_:)
    open func launchApplication(_ appName: String) -> Bool { launchApplication(appName, showIcon: true, autolaunch: false) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/launchapplication(_:showicon:autolaunch:)
    open func launchApplication(_ appName: String, showIcon: Bool, autolaunch: Bool) -> Bool {
        guard let path = fullPath(forApplication: appName) else { return false }
        return (try? launchApplication(at: URL(fileURLWithPath: path), configuration: [:])) != nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/openfile(_:)
    open func openFile(_ fullPath: String) -> Bool { open(URL(fileURLWithPath: fullPath)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/openfile(_:from:at:in:)
    open func openFile(_ fullPath: String, from image: NSImage?, at point: NSPoint, in view: NSView?) -> Bool { openFile(fullPath) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/openfile(_:withapplication:)
    open func openFile(_ fullPath: String, withApplication appName: String?) -> Bool { openFile(fullPath, withApplication: appName, andDeactivate: true) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/openfile(_:withapplication:anddeactivate:)
    open func openFile(_ fullPath: String, withApplication appName: String?, andDeactivate flag: Bool) -> Bool {
        guard let appName else { return openFile(fullPath) }
        guard let app = self.fullPath(forApplication: appName) else { return false }
        let configuration = OpenConfiguration()
        configuration.activates = flag
        return (try? _onMain { try _launch(urls: [URL(fileURLWithPath: fullPath)], application: URL(fileURLWithPath: app), configuration: configuration) }) != nil
    }

    @MainActor internal func _launch(urls: [URL], application: URL?, configuration: OpenConfiguration) throws -> NSRunningApplication {
        var options = PlatformLaunchOptions()
        options.arguments = configuration.arguments
        options.environment = configuration.environment
        options.activates = configuration.activates
        options.hides = configuration.hides
        options.createsNewApplicationInstance = configuration.createsNewApplicationInstance
        if configuration.isForPrinting { unimplemented("NSWorkspace.OpenConfiguration.isForPrinting") }
        if configuration.requiresUniversalLinks { throw PlatformWorkspaceError.unsupported("universal links") }
        if !configuration.createsNewApplicationInstance && configuration.allowsRunningApplicationSubstitution, urls.isEmpty, let application,
           let running = _refreshApplications(postingChanges: _monitoring).first(where: { $0.executableURL == application || $0._info.applicationURL == application }) {
            if configuration.activates { _ = running.activate(options: []) }
            return running
        }
        let process = try _platform.open(urls, withApplicationAt: application, options: options)
        let app = _application(for: process, isNew: true)
        if configuration.hidesOthers { hideOtherApplications() }
        return app
    }

    private func _complete(_ handler: (@Sendable (NSRunningApplication?, (any Error)?) -> Void)?, _ body: @escaping @MainActor () throws -> NSRunningApplication) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                do { let app = try body(); handler?(app, nil) }
                catch { handler?(nil, error) }
            }
        }
    }

    // MARK: The file manager

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/activatefileviewerselecting(_:)
    open func activateFileViewerSelecting(_ fileURLs: [URL]) { _ = _onMain { _platform.revealFiles(fileURLs, selecting: true) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/selectfile(_:infileviewerrootedatpath:)
    open func selectFile(_ fullPath: String?, inFileViewerRootedAtPath rootFullPath: String) -> Bool {
        _onMain {
            if let fullPath { return _platform.revealFiles([URL(fileURLWithPath: fullPath)], selecting: true) }
            return _platform.revealFiles([URL(fileURLWithPath: rootFullPath, isDirectory: true)], selecting: false)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/notefilesystemchanged(_:)
    open func noteFileSystemChanged(_ path: String) { _onMain { _platform.noteFileSystemChanged(path) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/showsearchresults(forquerystring:)
    open func showSearchResults(forQueryString queryString: String) -> Bool { unimplemented() }

    // MARK: Icons

    /// Default icon size in points, as the shell's large icons.
    static let _iconSize: CGFloat = 32

    @MainActor internal func _icon(for target: PlatformIconTarget, size: CGFloat = NSWorkspace._iconSize) -> NSImage {
        if let cached = _iconCache[target] { return cached }
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        let image: NSImage
        if let pixels = _platform.icon(for: target, size: size, scale: scale) {
            image = NSImage(cgImage: pixels, size: NSSize(width: size, height: size))
        } else {
            image = _NSWorkspaceIcons.drawn(for: target, size: size)
        }
        _iconCache[target] = image
        return image
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/icon(forfile:)
    open func icon(forFile fullPath: String) -> NSImage {
        _onMain {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory) {
                if isDirectory.boolValue && !isFilePackage(atPath: fullPath) && !_isApplication(atPath: fullPath) { return _icon(for: .folder) }
                return _icon(for: .file(path: fullPath))
            }
            let ext = (fullPath as NSString).pathExtension
            return ext.isEmpty ? _icon(for: .fileExtension("")) : _icon(for: .fileExtension(ext.lowercased()))
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/icon(forfiles:)
    open func icon(forFiles fullPaths: [String]) -> NSImage? {
        guard let first = fullPaths.first else { return nil }
        if fullPaths.count == 1 { return icon(forFile: first) }
        return _onMain { _NSWorkspaceIcons.stack(of: fullPaths.prefix(3).map { icon(forFile: $0) }) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/icon(forfiletype:)
    open func icon(forFileType fileType: String) -> NSImage {
        // A filename extension, a UTI, or a four-character HFS type in quotes.
        if fileType.hasPrefix("'") { return _onMain { _icon(for: .fileExtension("")) } }
        if fileType.contains("."), let type = UTType(fileType) { return icon(for: type) }
        return _onMain { _icon(for: .fileExtension(fileType.lowercased())) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/icon(for:)
    @available(macOS 11.0, *)
    open func icon(for contentType: UTType) -> NSImage {
        _onMain {
            if contentType == .folder || contentType == .directory { return _icon(for: .folder) }
            if contentType.conforms(to: .application) { return _icon(for: .fileExtension("exe")) }
            return _icon(for: .fileExtension(contentType.preferredFilenameExtension ?? ""))
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/seticon(_:forfile:options:)
    open func setIcon(_ image: NSImage?, forFile fullPath: String, options: NSWorkspace.IconCreationOptions = []) -> Bool { unimplemented() }

    // MARK: Applications for files

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/urlforapplication(toopen:)
    open func urlForApplication(toOpen url: URL) -> URL? { urlsForApplications(toOpen: url).first }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/urlsforapplications(toopen:)
    @available(macOS 12.0, *)
    open func urlsForApplications(toOpen url: URL) -> [URL] {
        _onMain {
            if url.isFileURL { return _platform.applicationURLs(toOpen: .file(url)) }
            return _platform.applicationURLs(toOpen: .scheme(url.scheme?.lowercased() ?? ""))
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/urlforapplication(toopen:)
    @available(macOS 12.0, *)
    open func urlForApplication(toOpen contentType: UTType) -> URL? { urlsForApplications(toOpen: contentType).first }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/urlsforapplications(toopen:)
    @available(macOS 12.0, *)
    open func urlsForApplications(toOpen contentType: UTType) -> [URL] {
        guard let ext = contentType.preferredFilenameExtension else { return [] }
        return _onMain { _platform.applicationURLs(toOpen: .fileExtension(ext)) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/urlforapplication(withbundleidentifier:)
    open func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? { urlsForApplications(withBundleIdentifier: bundleIdentifier).first }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/urlsforapplications(withbundleidentifier:)
    @available(macOS 12.0, *)
    open func urlsForApplications(withBundleIdentifier bundleIdentifier: String) -> [URL] {
        _onMain {
            if bundleIdentifier == NSRunningApplication.current.bundleIdentifier, let url = NSRunningApplication.current._info.applicationURL { return [url] }
            return _platform.applicationURL(withBundleIdentifier: bundleIdentifier).map { [$0] } ?? []
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/absolutepathforapplication(withbundleidentifier:)
    open func absolutePathForApplication(withBundleIdentifier bundleIdentifier: String) -> String? { urlForApplication(withBundleIdentifier: bundleIdentifier)?.path }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/fullpath(forapplication:)
    open func fullPath(forApplication appName: String) -> String? {
        // An absolute path (POSIX, or a Windows drive path with either separator) names the application itself.
        if appName.hasPrefix("/") || appName.dropFirst().hasPrefix(":") { return FileManager.default.fileExists(atPath: appName) ? appName : nil }
        return urlForApplication(withBundleIdentifier: appName)?.path
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopen:)
    @available(macOS 12.0, *)
    open func setDefaultApplication(at applicationURL: URL, toOpen contentType: UTType) async throws {
        guard let ext = contentType.preferredFilenameExtension else { throw PlatformWorkspaceError.unsupported("no filename extension for \(contentType.identifier)") }
        try await MainActor.run { try _platform.setDefaultApplication(at: applicationURL, toOpen: .fileExtension(ext)) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopen:completionhandler:)
    @available(macOS 12.0, *)
    open func setDefaultApplication(at applicationURL: URL, toOpen contentType: UTType, completionHandler: (@Sendable ((any Error)?) -> Void)? = nil) {
        _completeVoid(completionHandler) { try self._platform.setDefaultApplication(at: applicationURL, toOpen: .fileExtension(contentType.preferredFilenameExtension ?? "")) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopencontenttypeoffileat:)
    @available(macOS 12.0, *)
    open func setDefaultApplication(at applicationURL: URL, toOpenContentTypeOfFileAt url: URL) async throws {
        try await MainActor.run { try _platform.setDefaultApplication(at: applicationURL, toOpen: .fileExtension(url.pathExtension.lowercased())) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopencontenttypeoffileat:completionhandler:)
    @available(macOS 12.0, *)
    open func setDefaultApplication(at applicationURL: URL, toOpenContentTypeOfFileAt url: URL, completionHandler: (@Sendable ((any Error)?) -> Void)? = nil) {
        _completeVoid(completionHandler) { try self._platform.setDefaultApplication(at: applicationURL, toOpen: .fileExtension(url.pathExtension.lowercased())) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopenfileat:)
    @available(macOS 12.0, *)
    open func setDefaultApplication(at applicationURL: URL, toOpenFileAt url: URL) async throws {
        try await MainActor.run { try _platform.setDefaultApplication(at: applicationURL, toOpen: .file(url)) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopenfileat:completionhandler:)
    @available(macOS 12.0, *)
    open func setDefaultApplication(at applicationURL: URL, toOpenFileAt url: URL, completionHandler: (@Sendable ((any Error)?) -> Void)? = nil) {
        _completeVoid(completionHandler) { try self._platform.setDefaultApplication(at: applicationURL, toOpen: .file(url)) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopenurlswithscheme:)
    @available(macOS 12.0, *)
    open func setDefaultApplication(at applicationURL: URL, toOpenURLsWithScheme urlScheme: String) async throws {
        try await MainActor.run { try _platform.setDefaultApplication(at: applicationURL, toOpen: .scheme(urlScheme.lowercased())) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopenurlswithscheme:completionhandler:)
    @available(macOS 12.0, *)
    open func setDefaultApplication(at applicationURL: URL, toOpenURLsWithScheme urlScheme: String, completionHandler: (@Sendable ((any Error)?) -> Void)? = nil) {
        _completeVoid(completionHandler) { try self._platform.setDefaultApplication(at: applicationURL, toOpen: .scheme(urlScheme.lowercased())) }
    }
    private func _completeVoid(_ handler: (@Sendable ((any Error)?) -> Void)?, _ body: @escaping @MainActor () throws -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                do { try body(); handler?(nil) }
                catch { handler?(error) }
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/getinfoforfile(_:application:type:)
    open func getInfoForFile(_ fullPath: String, application appName: AutoreleasingUnsafeMutablePointer<NSString?>?, type: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        guard FileManager.default.fileExists(atPath: fullPath) else { return false }
        appName?.pointee = urlForApplication(toOpen: URL(fileURLWithPath: fullPath))?.path as NSString?
        type?.pointee = (fullPath as NSString).pathExtension as NSString
        return true
    }

    // MARK: File operations

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/recycle(_:)
    open func recycle(_ URLs: [URL]) async throws -> [URL : URL] { try await MainActor.run { try _recycle(URLs) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/recycle(_:completionhandler:)
    open func recycle(_ URLs: [URL], completionHandler handler: (@Sendable ([URL : URL], (any Error)?) -> Void)? = nil) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                do { handler?(try self._recycle(URLs), nil) } catch { handler?([:], error) }
            }
        }
    }
    @MainActor private func _recycle(_ urls: [URL]) throws -> [URL: URL] {
        var result: [URL: URL] = [:]
        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: [NSFilePathErrorKey: url.path])
            }
            if let destination = try _platform.recycle(url) { result[url] = destination }
        }
        _notificationCenter.post(name: NSWorkspace.didPerformFileOperationNotification, object: self, userInfo: ["NSOperationNumber": NSWorkspace.FileOperationName.recycleOperation.rawValue])
        return result
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/duplicate(_:)
    open func duplicate(_ URLs: [URL]) async throws -> [URL : URL] { try await MainActor.run { try _duplicate(URLs) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/duplicate(_:completionhandler:)
    open func duplicate(_ URLs: [URL], completionHandler handler: (@Sendable ([URL : URL], (any Error)?) -> Void)? = nil) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                do { handler?(try self._duplicate(URLs), nil) } catch { handler?([:], error) }
            }
        }
    }
    /// Copies each item next to itself as "name copy.ext", "name copy 2.ext", ... (Finder's naming).
    @MainActor private func _duplicate(_ urls: [URL]) throws -> [URL: URL] {
        let fm = FileManager.default
        var result: [URL: URL] = [:]
        for url in urls {
            let directory = url.deletingLastPathComponent()
            let ext = url.pathExtension
            let base = url.deletingPathExtension().lastPathComponent
            var n = 1
            var destination: URL
            repeat {
                let name = n == 1 ? "\(base) copy" : "\(base) copy \(n)"
                destination = directory.appendingPathComponent(name)
                if !ext.isEmpty { destination = destination.appendingPathExtension(ext) }
                n += 1
            } while fm.fileExists(atPath: destination.path)
            try fm.copyItem(at: url, to: destination)
            result[url] = destination
        }
        _notificationCenter.post(name: NSWorkspace.didPerformFileOperationNotification, object: self, userInfo: ["NSOperationNumber": NSWorkspace.FileOperationName.duplicateOperation.rawValue])
        return result
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/performfileoperation(_:source:destination:files:tag:)
    open func performFileOperation(_ operation: NSWorkspace.FileOperationName, source: String, destination: String, files: [Any], tag: UnsafeMutablePointer<Int>?) -> Bool {
        let fm = FileManager.default
        let names = files.compactMap { $0 as? String }
        let sourceURL = URL(fileURLWithPath: source, isDirectory: true), destinationURL = URL(fileURLWithPath: destination, isDirectory: true)
        do {
            switch operation {
            case .moveOperation:
                for n in names { try fm.moveItem(at: sourceURL.appendingPathComponent(n), to: destinationURL.appendingPathComponent(n)) }
            case .copyOperation:
                for n in names { try fm.copyItem(at: sourceURL.appendingPathComponent(n), to: destinationURL.appendingPathComponent(n)) }
            case .linkOperation:
                for n in names { try fm.createSymbolicLink(at: destinationURL.appendingPathComponent(n), withDestinationURL: sourceURL.appendingPathComponent(n)) }
            case .destroyOperation:
                for n in names { try fm.removeItem(at: sourceURL.appendingPathComponent(n)) }
            case .recycleOperation:
                _ = try _onMain { try _recycle(names.map { sourceURL.appendingPathComponent($0) }) }
            case .duplicateOperation:
                _ = try _onMain { try _duplicate(names.map { sourceURL.appendingPathComponent($0) }) }
            default:
                return false
            }
        } catch {
            return false
        }
        tag?.pointee = 0
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/isfilepackage(atpath:)
    open func isFilePackage(atPath fullPath: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
        let ext = (fullPath as NSString).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext, conformingTo: .directory) else { return false }
        return type.conforms(to: .package)
    }
    private func _isApplication(atPath path: String) -> Bool {
        let ext = (path as NSString).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .application)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/requestauthorization(to:)
    @available(macOS 10.14, *)
    open func requestAuthorization(to type: NSWorkspace.AuthorizationType) async throws -> NSWorkspace.Authorization { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/requestauthorization(to:completionhandler:)
    @available(macOS 10.14, *)
    open func requestAuthorization(to type: NSWorkspace.AuthorizationType, completionHandler: @escaping @Sendable (NSWorkspace.Authorization?, (any Error)?) -> Void) { unimplemented() }

    // MARK: Volumes (no counterpart for removable media and ejecting; see the ADR)

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/mountedlocalvolumepaths()
    open func mountedLocalVolumePaths() -> [Any]? {
        FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes])?.map { $0.path }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/mountedremovablemedia()
    open func mountedRemovableMedia() -> [Any]? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/unmountandejectdevice(at:)
    open func unmountAndEjectDevice(at url: URL) throws { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/unmountandejectdevice(atpath:)
    open func unmountAndEjectDevice(atPath path: String) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/getfilesysteminfo(forpath:isremovable:iswritable:isunmountable:description:type:)
    open func getFileSystemInfo(forPath fullPath: String, isRemovable removableFlag: UnsafeMutablePointer<ObjCBool>?, isWritable writableFlag: UnsafeMutablePointer<ObjCBool>?, isUnmountable unmountableFlag: UnsafeMutablePointer<ObjCBool>?, description: AutoreleasingUnsafeMutablePointer<NSString?>?, type fileSystemType: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/extendpoweroff(by:)
    open func extendPowerOff(by requested: Int) -> Int { unimplemented() }

    // MARK: Running applications

    /// Re-reads the platform's process list; posts launch/terminate notifications for the
    /// differences when asked. Returns the live applications.
    @MainActor @discardableResult internal func _refreshApplications(postingChanges: Bool) -> [NSRunningApplication] {
        guard !_refreshing else { return _liveApplications }
        _refreshing = true
        defer { _refreshing = false }
        let current = NSRunningApplication.current
        var live: [NSRunningApplication] = [current]
        var seen: Set<Int32> = [current.processIdentifier]
        let selfActive = NSApplication._shared?.isActive ?? false
        for var info in _platform.runningApplications where info.processIdentifier != current.processIdentifier {
            seen.insert(info.processIdentifier)
            if selfActive { info.isActive = false }
            if let app = _applications[info.processIdentifier] {
                app._update(info, workspace: self, posting: postingChanges && _applicationsRefreshed)
                live.append(app)
            } else {
                live.append(_application(for: info, isNew: postingChanges && _applicationsRefreshed))
            }
        }
        for (pid, app) in _applications where !seen.contains(pid) && !app.isTerminated {
            _applicationDidTerminate(app, posting: postingChanges && _applicationsRefreshed)
        }
        // The frontmost application, from the platform unless this one knows it is active.
        let frontmost: Int32? = selfActive ? current.processIdentifier : _platform.frontmostProcessIdentifier
        _applicationsRefreshed = true
        _liveApplications = live
        if frontmost != _lastActivePID {
            _activeApplicationDidChange(to: frontmost.flatMap { pid in live.first { $0.processIdentifier == pid } })
        }
        return live
    }

    /// The object for a process the platform reported (new ones post `didLaunch`).
    @MainActor internal func _application(for info: PlatformRunningApplication, isNew: Bool) -> NSRunningApplication {
        if let app = _applications[info.processIdentifier], !app.isTerminated {
            app._update(info, workspace: self, posting: false)
            return app
        }
        let app = NSRunningApplication(_info: info)
        _applications[info.processIdentifier] = app
        if isNew { _post(NSWorkspace.didLaunchApplicationNotification, application: app) }
        if info.isActive { _activeApplicationDidChange(to: app) }
        return app
    }

    @MainActor private func _applicationDidTerminate(_ app: NSRunningApplication, posting: Bool) {
        app._markTerminated()
        _applications[app.processIdentifier] = nil
        if _lastActivePID == app.processIdentifier { _lastActivePID = nil }
        if posting { _post(NSWorkspace.didTerminateApplicationNotification, application: app) }
    }

    @MainActor private func _activeApplicationDidChange(to app: NSRunningApplication?) {
        let newPID = app?.processIdentifier
        guard newPID != _lastActivePID else { return }
        let previous = _lastActivePID.flatMap { old in _applications[old] ?? (old == NSRunningApplication.current.processIdentifier ? NSRunningApplication.current : nil) }
        // The state first, the notifications after: an observer that asks for the frontmost
        // application from didDeactivate must see the change made, or the refresh it
        // triggers finds the old pid and posts the same change again without end
        // (a stack overflow on Windows, inside the foreground hook's callback).
        _lastActivePID = newPID
        previous?._setActive(false)
        app?._setActive(true)
        if let previous { _post(NSWorkspace.didDeactivateApplicationNotification, application: previous) }
        if let app { _post(NSWorkspace.didActivateApplicationNotification, application: app) }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/runningapplications
    open var runningApplications: [NSRunningApplication] {
        _onMain {
            _startMonitoringIfNeeded()
            return _refreshApplications(postingChanges: true)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication
    open var frontmostApplication: NSRunningApplication? {
        _onMain {
            _startMonitoringIfNeeded()
            let apps = _refreshApplications(postingChanges: true)
            if let pid = _lastActivePID { return apps.first { $0.processIdentifier == pid } }
            return apps.first { $0.isActive }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/menubarowningapplication
    open var menuBarOwningApplication: NSRunningApplication? { frontmostApplication }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/activeapplication()
    open func activeApplication() -> [AnyHashable : Any]? {
        guard let app = frontmostApplication else { return nil }
        var d: [AnyHashable: Any] = ["NSApplicationProcessIdentifier": Int(app.processIdentifier)]
        if let n = app.localizedName { d["NSApplicationName"] = n }
        if let p = app.executableURL?.path { d["NSApplicationPath"] = p }
        if let b = app.bundleIdentifier { d["NSApplicationBundleIdentifier"] = b }
        return d
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/hideotherapplications()
    open func hideOtherApplications() {
        _onMain {
            for app in _refreshApplications(postingChanges: true) where app !== NSRunningApplication.current && !app.isHidden { _ = app.hide() }
        }
    }
    @MainActor internal func _unhideAllApplications() {
        for app in _refreshApplications(postingChanges: true) where app.isHidden { _ = app.unhide() }
    }
    @MainActor internal func _application(withProcessIdentifier pid: Int32) -> NSRunningApplication? {
        if pid == NSRunningApplication.current.processIdentifier { return NSRunningApplication.current }
        _startMonitoringIfNeeded()
        if let app = _applications[pid], !app.isTerminated { return app }
        guard let info = _platform.runningApplication(withProcessIdentifier: pid) else { return nil }
        return _application(for: info, isNew: false)
    }

    // MARK: Accessibility settings

    @MainActor private var _accessibility: PlatformAccessibilityDisplayOptions { _startMonitoringIfNeeded(); return _platform.accessibilityDisplayOptions }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshoulddifferentiatewithoutcolor
    @available(macOS 10.10, *)
    open var accessibilityDisplayShouldDifferentiateWithoutColor: Bool { _onMain { _accessibility.differentiateWithoutColor } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldincreasecontrast
    @available(macOS 10.10, *)
    open var accessibilityDisplayShouldIncreaseContrast: Bool { _onMain { _accessibility.increaseContrast } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldinvertcolors
    @available(macOS 10.12, *)
    open var accessibilityDisplayShouldInvertColors: Bool { _onMain { _accessibility.invertColors } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion
    @available(macOS 10.12, *)
    open var accessibilityDisplayShouldReduceMotion: Bool { _onMain { _accessibility.reduceMotion } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducetransparency
    @available(macOS 10.10, *)
    open var accessibilityDisplayShouldReduceTransparency: Bool { _onMain { _accessibility.reduceTransparency } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/isswitchcontrolenabled
    @available(macOS 10.13, *)
    open var isSwitchControlEnabled: Bool { _onMain { _accessibility.switchControlEnabled } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/isvoiceoverenabled
    @available(macOS 10.13, *)
    open var isVoiceOverEnabled: Bool { _onMain { _accessibility.voiceOverEnabled } }

    // MARK: Desktop picture

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/desktopimageurl(for:)
    open func desktopImageURL(for screen: NSScreen) -> URL? { _onMain { _platform.desktopImageURL(forDisplay: _displayIndex(of: screen)) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/setdesktopimageurl(_:for:options:)
    open func setDesktopImageURL(_ url: URL, for screen: NSScreen, options: [NSWorkspace.DesktopImageOptionKey : Any] = [:]) throws {
        try _onMain { try _platform.setDesktopImageURL(url, forDisplay: _displayIndex(of: screen)) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/desktopimageoptions(for:)
    open func desktopImageOptions(for screen: NSScreen) -> [NSWorkspace.DesktopImageOptionKey : Any]? { unimplemented() }
    @MainActor private func _displayIndex(of screen: NSScreen) -> Int { NSScreen.screens.firstIndex { $0 === screen || $0.frame == screen.frame } ?? 0 }

    // MARK: File types (UniformTypeIdentifiers)

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/type(offile:)
    open func type(ofFile absoluteFilePath: String) throws -> String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: absoluteFilePath, isDirectory: &isDirectory) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: [NSFilePathErrorKey: absoluteFilePath])
        }
        let ext = (absoluteFilePath as NSString).pathExtension
        if isDirectory.boolValue {
            if !ext.isEmpty, let t = UTType(filenameExtension: ext, conformingTo: .directory) { return t.identifier }
            return UTType.folder.identifier
        }
        if !ext.isEmpty, let t = UTType(filenameExtension: ext) { return t.identifier }
        return UTType.data.identifier
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/type(_:conformstotype:)
    open func type(_ firstTypeName: String, conformsToType secondTypeName: String) -> Bool {
        guard let a = UTType(firstTypeName), let b = UTType(secondTypeName) else { return firstTypeName.caseInsensitiveCompare(secondTypeName) == .orderedSame }
        return a.conforms(to: b)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/preferredfilenameextension(fortype:)
    open func preferredFilenameExtension(forType typeName: String) -> String? { UTType(typeName)?.preferredFilenameExtension }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/filenameextension(_:isvalidfortype:)
    open func filenameExtension(_ filenameExtension: String, isValidForType typeName: String) -> Bool {
        guard let type = UTType(typeName) else { return false }
        return UTType.types(tag: filenameExtension.lowercased(), tagClass: .filenameExtension, conformingTo: nil).contains { $0.conforms(to: type) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/localizeddescription(fortype:)
    open func localizedDescription(forType typeName: String) -> String? { UTType(typeName)?.localizedDescription }

    // MARK: Finder labels (no counterpart; see the ADR)

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/filelabelcolors
    open var fileLabelColors: [NSColor] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/filelabels
    open var fileLabels: [String] { unimplemented() }
}

// All state is main-actor isolated or immutable; the API is callable from any thread.
extension NSWorkspace: @unchecked Sendable {}

// MARK: - Platform events

extension NSWorkspace: PlatformWorkspaceObserver {
    public func platformWorkspaceDidObserve(_ event: PlatformWorkspaceEvent) {
        switch event {
        case .applicationDidActivate(let pid):
            // The platform tells the application about its own activation here too (the
            // window backends only report key windows).
            if pid == NSRunningApplication.current.processIdentifier {
                if let app = NSApplication._shared, !app.isActive { app.activate(ignoringOtherApps: true) }
                else { _activeApplicationDidChange(to: NSRunningApplication.current) }
            } else {
                if let app = NSApplication._shared, app.isActive { app.deactivate() }
                _activeApplicationDidChange(to: _application(withProcessIdentifier: pid))
            }
        case .applicationDidLaunch(let info):
            _ = _application(for: info, isNew: true)
        case .applicationDidTerminate(let pid):
            if let app = _applications[pid] { _applicationDidTerminate(app, posting: true) }
        case .applicationDidHide(let pid):
            if let app = _application(withProcessIdentifier: pid) { app._setHidden(true); _post(NSWorkspace.didHideApplicationNotification, application: app) }
        case .applicationDidUnhide(let pid):
            if let app = _application(withProcessIdentifier: pid) { app._setHidden(false); _post(NSWorkspace.didUnhideApplicationNotification, application: app) }
        case .willSleep: _post(NSWorkspace.willSleepNotification)
        case .didWake: _post(NSWorkspace.didWakeNotification)
        case .screensDidSleep: _post(NSWorkspace.screensDidSleepNotification)
        case .screensDidWake: _post(NSWorkspace.screensDidWakeNotification)
        case .sessionDidBecomeActive: _post(NSWorkspace.sessionDidBecomeActiveNotification)
        case .sessionDidResignActive: _post(NSWorkspace.sessionDidResignActiveNotification)
        case .accessibilityDisplayOptionsDidChange: _post(NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
        }
    }

    /// `NSApplication` reports its own activation, hiding and unhiding here, so the
    /// notifications about this process match the application's state on every platform.
    @MainActor internal func _currentApplicationDidChange(active: Bool? = nil, hidden: Bool? = nil) {
        guard _monitoring else { return }
        let current = NSRunningApplication.current
        if let active {
            if active { _activeApplicationDidChange(to: current) }
            else if _lastActivePID == current.processIdentifier { _activeApplicationDidChange(to: nil) }
        }
        if let hidden { _post(hidden ? NSWorkspace.didHideApplicationNotification : NSWorkspace.didUnhideApplicationNotification, application: current) }
    }
}

// MARK: - OpenConfiguration

@available(macOS 10.15, *)
extension NSWorkspace {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration
    @available(macOS 10.15, *)
    open class OpenConfiguration: NSObject, NSCopying, @unchecked Sendable {
        public override init() { super.init() }
        /// The old `LaunchOptions`/configuration dictionary form.
        internal convenience init(launchOptions: NSWorkspace.LaunchOptions, configuration: [NSWorkspace.LaunchConfigurationKey: Any]) {
            self.init()
            activates = !launchOptions.contains(.withoutActivation)
            hides = launchOptions.contains(.andHide)
            hidesOthers = launchOptions.contains(.andHideOthers)
            createsNewApplicationInstance = launchOptions.contains(.newInstance)
            isForPrinting = launchOptions.contains(.andPrint)
            addsToRecentItems = !launchOptions.contains(.withoutAddingToRecents)
            promptsUserIfNeeded = launchOptions.contains(.withErrorPresentation)
            if let a = configuration[.arguments] as? [String] { arguments = a }
            if let e = configuration[.environment] as? [String: String] { environment = e }
        }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/activates
        open var activates: Bool = true
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/addstorecentitems
        open var addsToRecentItems: Bool = true
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/allowsrunningapplicationsubstitution
        open var allowsRunningApplicationSubstitution: Bool = true
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/arguments
        open var arguments: [String] = []
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/createsnewapplicationinstance
        open var createsNewApplicationInstance: Bool = false
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/environment
        open var environment: [String : String] = [:]
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/hides
        open var hides: Bool = false
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/hidesothers
        open var hidesOthers: Bool = false
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/isforprinting
        open var isForPrinting: Bool = false
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/promptsuserifneeded
        open var promptsUserIfNeeded: Bool = true
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/requiresuniversallinks
        open var requiresUniversalLinks: Bool = false
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/copy(with:)
        open func copy(with zone: NSZone? = nil) -> Any {
            let c = OpenConfiguration()
            c.activates = activates; c.addsToRecentItems = addsToRecentItems; c.allowsRunningApplicationSubstitution = allowsRunningApplicationSubstitution
            c.arguments = arguments; c.createsNewApplicationInstance = createsNewApplicationInstance; c.environment = environment
            c.hides = hides; c.hidesOthers = hidesOthers; c.isForPrinting = isForPrinting; c.promptsUserIfNeeded = promptsUserIfNeeded
            c.requiresUniversalLinks = requiresUniversalLinks
            return c
        }
    }
}
