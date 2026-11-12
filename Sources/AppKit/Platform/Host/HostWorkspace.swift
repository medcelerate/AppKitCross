// The workspace services on the host backend (ADR-0022): an in-memory stand-in for tests
// and for platforms that offer nothing. Opening and revealing are recorded, the running
// applications are this process plus whatever a test registers, icons are left to the
// core's drawn fallback, recycling moves the item into a trash folder under the temporary
// directory, and tests inject events with `postEvent`.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

@MainActor
public final class HostWorkspace: PlatformWorkspace {
    public static let shared = HostWorkspace()

    public weak var observer: (any PlatformWorkspaceObserver)?
    public private(set) var isMonitoring = false
    public func startMonitoring() { isMonitoring = true }

    /// What `open`, `revealFiles` and the launches were asked for, oldest first.
    public private(set) var openedURLs: [URL] = []
    public private(set) var revealedURLs: [URL] = []
    public private(set) var launches: [(application: URL?, urls: [URL], options: PlatformLaunchOptions)] = []
    /// A process identifier in `otherApplications` that every launch answers with instead
    /// of a new one: a single-instance application already running took the request.
    public var launchResolvesTo: Int32?
    /// Test hooks: whether `open` succeeds, what the handlers are, what the icons are.
    public var opensSucceed = true
    public var handlers: [PlatformOpenTarget: [URL]] = [:]
    public var applicationsByIdentifier: [String: URL] = [:]
    public var icons: [PlatformIconTarget: CGImage] = [:]
    public var iconRequests: [PlatformIconTarget] = []
    public var accessibilityDisplayOptions = PlatformAccessibilityDisplayOptions()
    public var desktopImages: [Int: URL] = [:]
    public private(set) var dockTiles: [PlatformDockTile] = []
    public private(set) var fileSystemNotes: [String] = []
    /// Processes a test registered besides this one.
    public var otherApplications: [PlatformRunningApplication] = []
    private var nextPID: Int32 = 60_000
    public private(set) var activated: [Int32] = []
    public private(set) var hidden: Set<Int32> = []
    public private(set) var terminated: [(Int32, Bool)] = []
    /// The trash folder `recycle` moves items into.
    public let trashURL = FileManager.default.temporaryDirectory.appendingPathComponent("AppKitCross-Trash-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)

    public func reset() {
        openedURLs.removeAll(); revealedURLs.removeAll(); launches.removeAll(); launchResolvesTo = nil; handlers.removeAll(); applicationsByIdentifier.removeAll()
        icons.removeAll(); iconRequests.removeAll(); dockTiles.removeAll(); fileSystemNotes.removeAll(); otherApplications.removeAll()
        activated.removeAll(); hidden.removeAll(); terminated.removeAll(); desktopImages.removeAll()
        opensSucceed = true
        accessibilityDisplayOptions = PlatformAccessibilityDisplayOptions()
    }

    /// Delivers an event as the platform would.
    public func postEvent(_ event: PlatformWorkspaceEvent) { observer?.platformWorkspaceDidObserve(event) }

    public func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return opensSucceed
    }

    public func open(_ urls: [URL], withApplicationAt applicationURL: URL?, options: PlatformLaunchOptions) throws -> PlatformRunningApplication {
        launches.append((applicationURL, urls, options))
        let app: URL
        if let applicationURL { app = applicationURL }
        else if let first = urls.first, let handler = applicationURLs(toOpen: .file(first)).first ?? applicationURLs(toOpen: .scheme(first.scheme ?? "")).first { app = handler }
        else { throw PlatformWorkspaceError.noApplication(urls.first?.absoluteString ?? "nothing") }
        if let pid = launchResolvesTo, let running = otherApplications.first(where: { $0.processIdentifier == pid }) { return running }
        nextPID += 1
        let process = PlatformRunningApplication(processIdentifier: nextPID, localizedName: app.deletingPathExtension().lastPathComponent,
                                                 bundleIdentifier: app.deletingPathExtension().lastPathComponent, executableURL: app, applicationURL: app,
                                                 launchDate: Date(), isActive: options.activates, isHidden: options.hides, hasWindows: true)
        otherApplications.append(process)
        return process
    }

    public func revealFiles(_ urls: [URL], selecting: Bool) -> Bool {
        revealedURLs += urls
        return opensSucceed
    }

    public func applicationURLs(toOpen target: PlatformOpenTarget) -> [URL] {
        if let h = handlers[target] { return h }
        if case .file(let url) = target, !url.pathExtension.isEmpty { return handlers[.fileExtension(url.pathExtension.lowercased())] ?? [] }
        return []
    }

    public func applicationURL(withBundleIdentifier identifier: String) -> URL? { applicationsByIdentifier[identifier] }

    public func setDefaultApplication(at applicationURL: URL, toOpen target: PlatformOpenTarget) throws {
        var list = handlers[target] ?? []
        list.removeAll { $0 == applicationURL }
        handlers[target] = [applicationURL] + list
    }

    public func icon(for target: PlatformIconTarget, size: CGFloat, scale: CGFloat) -> CGImage? {
        iconRequests.append(target)
        return icons[target]
    }

    public func recycle(_ url: URL) throws -> URL? {
        let fm = FileManager.default
        try fm.createDirectory(at: trashURL, withIntermediateDirectories: true)
        var destination = trashURL.appendingPathComponent(url.lastPathComponent)
        var n = 1
        while fm.fileExists(atPath: destination.path) {
            n += 1
            destination = trashURL.appendingPathComponent(url.deletingPathExtension().lastPathComponent + " \(n)").appendingPathExtension(url.pathExtension)
        }
        try fm.moveItem(at: url, to: destination)
        return destination
    }

    public func noteFileSystemChanged(_ path: String) { fileSystemNotes.append(path) }

    public var current: PlatformRunningApplication {
        let exe = URL(fileURLWithPath: CommandLine.arguments.first ?? ProcessInfo.processInfo.processName)
        return PlatformRunningApplication(processIdentifier: ProcessInfo.processInfo.processIdentifier, localizedName: ProcessInfo.processInfo.processName,
                                          bundleIdentifier: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName, executableURL: exe,
                                          applicationURL: exe, launchDate: nil, isActive: true, isHidden: false, hasWindows: true)
    }

    public var runningApplications: [PlatformRunningApplication] { [current] + otherApplications }
    public var frontmostProcessIdentifier: Int32? { otherApplications.first(where: { $0.isActive })?.processIdentifier ?? current.processIdentifier }
    public func runningApplication(withProcessIdentifier pid: Int32) -> PlatformRunningApplication? { runningApplications.first { $0.processIdentifier == pid } }

    public func activate(processIdentifier pid: Int32) -> Bool {
        guard let i = otherApplications.firstIndex(where: { $0.processIdentifier == pid }) else { return pid == current.processIdentifier }
        activated.append(pid)
        for j in otherApplications.indices { otherApplications[j].isActive = j == i }
        otherApplications[i].isHidden = false
        hidden.remove(pid)
        postEvent(.applicationDidActivate(processIdentifier: pid))
        return true
    }
    public func hide(processIdentifier pid: Int32) -> Bool {
        guard let i = otherApplications.firstIndex(where: { $0.processIdentifier == pid }) else { return false }
        otherApplications[i].isHidden = true
        hidden.insert(pid)
        postEvent(.applicationDidHide(processIdentifier: pid))
        return true
    }
    public func unhide(processIdentifier pid: Int32) -> Bool {
        guard let i = otherApplications.firstIndex(where: { $0.processIdentifier == pid }) else { return false }
        otherApplications[i].isHidden = false
        hidden.remove(pid)
        postEvent(.applicationDidUnhide(processIdentifier: pid))
        return true
    }
    public func terminate(processIdentifier pid: Int32, force: Bool) -> Bool {
        guard let i = otherApplications.firstIndex(where: { $0.processIdentifier == pid }) else { return false }
        terminated.append((pid, force))
        otherApplications.remove(at: i)
        postEvent(.applicationDidTerminate(processIdentifier: pid))
        return true
    }
    public func executableArchitecture(processIdentifier pid: Int32) -> Int? { nil }

    public func desktopImageURL(forDisplay index: Int) -> URL? { desktopImages[index] }
    public func setDesktopImageURL(_ url: URL, forDisplay index: Int) throws { desktopImages[index] = url }

    public func setDockTile(_ tile: PlatformDockTile) { dockTiles.append(tile) }
}
