// The workspace seam (ADR-0022): what NSWorkspace, NSRunningApplication and NSDockTile ask
// of the operating system. The core owns the API, the caching, the notification center
// and the running-application objects; a backend answers with the shell's own services:
// Explorer, the shell icon cache, file associations, the Recycle Bin, the taskbar and the
// process list on Windows; the desktop entries, icon themes, the file manager, the XDG
// trash and the X11 window list on Linux; an in-memory stand-in on the host backend.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A process the platform counts as an application: on Windows one that owns a top-level
/// window (what the taskbar shows), on X11 one in `_NET_CLIENT_LIST`, plus the processes
/// this application launched and itself.
public struct PlatformRunningApplication: Sendable, Equatable {
    public var processIdentifier: Int32
    /// The application's display name (the executable's file description or the desktop
    /// entry's Name, else the executable's name).
    public var localizedName: String?
    /// The platform's identity for the application: the Application User Model ID or the
    /// executable's name on Windows, the desktop entry id on Linux.
    public var bundleIdentifier: String?
    public var executableURL: URL?
    /// What `NSWorkspace.urlForApplication` answers for it: the executable on Windows, the
    /// `.desktop` file on Linux (or the executable when none describes it).
    public var applicationURL: URL?
    public var launchDate: Date?
    public var isActive: Bool
    /// Every window minimised (Windows), or `_NET_WM_STATE_HIDDEN` on all of them (X11).
    public var isHidden: Bool
    /// Whether the process shows windows (`activationPolicy == .regular`).
    public var hasWindows: Bool
    public init(processIdentifier: Int32, localizedName: String? = nil, bundleIdentifier: String? = nil, executableURL: URL? = nil,
                applicationURL: URL? = nil, launchDate: Date? = nil, isActive: Bool = false, isHidden: Bool = false, hasWindows: Bool = true) {
        self.processIdentifier = processIdentifier
        self.localizedName = localizedName
        self.bundleIdentifier = bundleIdentifier
        self.executableURL = executableURL
        self.applicationURL = applicationURL
        self.launchDate = launchDate
        self.isActive = isActive
        self.isHidden = isHidden
        self.hasWindows = hasWindows
    }
}

/// The system's accessibility display settings (`NSWorkspace.accessibilityDisplayShould…`).
public struct PlatformAccessibilityDisplayOptions: Sendable, Equatable {
    public var reduceMotion = false
    public var increaseContrast = false
    public var reduceTransparency = false
    public var differentiateWithoutColor = false
    public var invertColors = false
    public var voiceOverEnabled = false
    public var switchControlEnabled = false
    public init() {}
}

/// What the platform tells the workspace about; the core posts the matching
/// `NSWorkspace` notifications and updates its `NSRunningApplication`s.
public enum PlatformWorkspaceEvent: Sendable {
    case applicationDidActivate(processIdentifier: Int32)
    case applicationDidLaunch(PlatformRunningApplication)
    /// A process this workspace launched handed its work to another one (a packaged
    /// application's launcher stub on Windows): the launched `NSRunningApplication` now
    /// stands for the new process, with no launch or termination notification.
    case applicationDidHandOff(fromProcessIdentifier: Int32, to: PlatformRunningApplication)
    case applicationDidTerminate(processIdentifier: Int32)
    case applicationDidHide(processIdentifier: Int32)
    case applicationDidUnhide(processIdentifier: Int32)
    case willSleep
    case didWake
    case screensDidSleep
    case screensDidWake
    case sessionDidBecomeActive
    case sessionDidResignActive
    case accessibilityDisplayOptionsDidChange
}

/// Implemented by `NSWorkspace`. Events arrive on the main actor.
@MainActor
public protocol PlatformWorkspaceObserver: AnyObject {
    func platformWorkspaceDidObserve(_ event: PlatformWorkspaceEvent)
}

/// How to launch something (`NSWorkspace.OpenConfiguration`).
public struct PlatformLaunchOptions: Sendable {
    public var arguments: [String] = []
    public var environment: [String: String] = [:]
    /// Bring the launched application to the front (`activates`).
    public var activates = true
    /// Launch minimised / hidden (`hides`).
    public var hides = false
    /// Start another instance even when one runs (`createsNewApplicationInstance`); the
    /// platforms always start a process, so this is informational.
    public var createsNewApplicationInstance = false
    public init() {}
}

/// What a file association question is about.
public enum PlatformOpenTarget: Sendable, Hashable {
    case file(URL)
    case fileExtension(String)
    case scheme(String)
}

/// What an icon question is about. Icons come back as pixels at `scale`; the core wraps
/// them in an `NSImage` of `size` points and draws its own when the answer is nil.
public enum PlatformIconTarget: Sendable, Hashable {
    case file(path: String)
    case fileExtension(String)
    case folder
    case application(URL)
    case process(Int32)
}

/// The taskbar/launcher presentation of this application (`NSDockTile`).
public struct PlatformDockTile: Sendable {
    /// The badge text; nil clears it.
    public var badgeLabel: String?
    /// The badge drawn by the core (a filled pill with the label) for platforms that
    /// overlay a small image on the taskbar button; pixels at `scale`.
    public var badgeOverlay: CGImage?
    /// The application icon to show in place of the executable's: the dock tile's content
    /// view, or the application icon image, with the badge already composited; nil keeps
    /// the executable's icon.
    public var icon: CGImage?
    public var scale: CGFloat
    public init(badgeLabel: String?, badgeOverlay: CGImage?, icon: CGImage?, scale: CGFloat) {
        self.badgeLabel = badgeLabel
        self.badgeOverlay = badgeOverlay
        self.icon = icon
        self.scale = scale
    }
}

public enum PlatformWorkspaceError: Error, CustomStringConvertible {
    /// Nothing is registered to open the target.
    case noApplication(String)
    /// The process could not be started.
    case launchFailed(String)
    /// The file operation failed (recycle, duplicate, set wallpaper).
    case fileOperationFailed(String)
    /// The platform has no way to do this.
    case unsupported(String)
    public var description: String {
        switch self {
        case .noApplication(let s): return "no application to open \(s)"
        case .launchFailed(let s): return "could not launch \(s)"
        case .fileOperationFailed(let s): return "file operation failed: \(s)"
        case .unsupported(let s): return "unsupported: \(s)"
        }
    }
}

@MainActor
public protocol PlatformWorkspace: AnyObject {
    /// Where events go; set by `NSWorkspace` when something first asks for its
    /// notification center or running applications.
    var observer: (any PlatformWorkspaceObserver)? { get set }
    /// Starts watching the system (foreground changes, the process list, power and
    /// session events, settings changes); idempotent.
    func startMonitoring()

    // MARK: Opening
    /// Opens the URL with its registered handler (the default browser, the file's
    /// application, the folder in the file manager). Fire and forget.
    func open(_ url: URL) -> Bool
    /// Launches the application at `applicationURL` (an executable, a `.desktop` file; nil
    /// means the registered handler of the first URL) with `urls` as its documents and
    /// answers the process it started.
    func open(_ urls: [URL], withApplicationAt applicationURL: URL?, options: PlatformLaunchOptions) throws -> PlatformRunningApplication
    /// Shows the files selected in the file manager (Explorer, the FileManager1 service);
    /// a folder URL with `selecting == false` opens the folder itself.
    func revealFiles(_ urls: [URL], selecting: Bool) -> Bool

    // MARK: File associations
    /// The applications registered for the target, default first. Application URLs are
    /// executables on Windows and `.desktop` files on Linux.
    func applicationURLs(toOpen target: PlatformOpenTarget) -> [URL]
    /// The application with this identity (an Application User Model ID or executable
    /// name, a desktop entry id).
    func applicationURL(withBundleIdentifier identifier: String) -> URL?
    func setDefaultApplication(at applicationURL: URL, toOpen target: PlatformOpenTarget) throws

    // MARK: Icons
    /// The icon the shell shows for the target, `size` points on a side at `scale`, or nil
    /// when the platform has none (the core then draws a generic one).
    func icon(for target: PlatformIconTarget, size: CGFloat, scale: CGFloat) -> CGImage?

    // MARK: Files
    /// Moves the item to the Recycle Bin / trash. Returns where it went when that is known.
    func recycle(_ url: URL) throws -> URL?
    /// `NSWorkspace.noteFileSystemChanged`: tells the shell a path changed.
    func noteFileSystemChanged(_ path: String)

    // MARK: Running applications
    var runningApplications: [PlatformRunningApplication] { get }
    /// The process that owns the foreground window.
    var frontmostProcessIdentifier: Int32? { get }
    func runningApplication(withProcessIdentifier pid: Int32) -> PlatformRunningApplication?
    func activate(processIdentifier pid: Int32) -> Bool
    func hide(processIdentifier pid: Int32) -> Bool
    func unhide(processIdentifier pid: Int32) -> Bool
    /// Asks the process to quit (closes its windows), or kills it when `force`.
    func terminate(processIdentifier pid: Int32, force: Bool) -> Bool
    /// The executable architecture of another process (`NSBundleExecutableArchitecture…`
    /// values), nil when the platform cannot tell.
    func executableArchitecture(processIdentifier pid: Int32) -> Int?

    // MARK: Settings
    var accessibilityDisplayOptions: PlatformAccessibilityDisplayOptions { get }
    /// The desktop picture of the display at `index` in `displays` (nil: none or unknown).
    func desktopImageURL(forDisplay index: Int) -> URL?
    func setDesktopImageURL(_ url: URL, forDisplay index: Int) throws

    // MARK: The application's own tile
    func setDockTile(_ tile: PlatformDockTile)
}

extension PlatformBackend {
    /// The in-memory stand-in for backends without a shell of their own (the host backend).
    public var workspace: any PlatformWorkspace { HostWorkspace.shared }
}
