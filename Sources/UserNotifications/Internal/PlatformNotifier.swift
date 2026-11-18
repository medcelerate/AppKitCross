// UserNotifications (ADR-0043): the platform seam. `UNUserNotificationCenter` keeps the
// requests, the schedule, the authorization flow and the delegate; a `PlatformNotifier`
// only shows, removes and reports on notifications: Windows toasts (WindowsToastNotifier),
// the freedesktop notification server on Linux (FreedesktopNotifier), and an in-memory
// notifier for the macOS test build and the tests' fakes.

import Foundation

/// What the platform currently allows the app.
enum PlatformAuthorization: Equatable, Sendable {
    /// Notifications can be shown.
    case allowed
    /// The user or policy turned the app's notifications off (Windows settings).
    case deniedBySettings
    /// Nothing can show a notification (no notification server on the session bus).
    case unavailable
}

/// A button on a shown notification.
struct PlatformAction: Equatable, Sendable {
    var identifier: String
    var title: String
    var destructive: Bool
    var foreground: Bool
    /// The text box's button title and placeholder for a `UNTextInputNotificationAction`.
    var textInput: (buttonTitle: String, placeholder: String)?

    static func == (a: PlatformAction, b: PlatformAction) -> Bool {
        a.identifier == b.identifier && a.title == b.title && a.destructive == b.destructive && a.foreground == b.foreground
            && a.textInput?.buttonTitle == b.textInput?.buttonTitle && a.textInput?.placeholder == b.textInput?.placeholder
    }
}

/// One notification as the platform shows it: the request's content flattened, its category's
/// actions resolved, and the presentation options applied.
struct PlatformNotification: Equatable, Sendable {
    var identifier: String
    var title: String
    var subtitle: String
    var body: String
    /// Play a sound; `soundName` is nil for the default sound.
    var playsSound: Bool
    var soundName: String?
    /// Image attachments, shown inline.
    var imageFiles: [URL]
    var actions: [PlatformAction]
    /// Only into the notification list (Action Center), without a banner.
    var listOnly: Bool
    var interruptionLevel: UNNotificationInterruptionLevel
    var threadIdentifier: String
}

enum PlatformDismissReason: Equatable, Sendable {
    /// The user closed it.
    case user
    /// It timed out of the screen (Windows moves it to Action Center; it is still delivered).
    case timedOut
    /// The app removed it, or the platform did for another reason.
    case removed
}

enum PlatformNotificationEvent: Equatable, Sendable {
    /// A click on the notification (`UNNotificationDefaultActionIdentifier`) or on a button.
    case activated(identifier: String, actionIdentifier: String, userText: String?)
    case dismissed(identifier: String, reason: PlatformDismissReason)
}

protocol PlatformNotifier: AnyObject, Sendable {
    /// Gets ready to notify, called on the center's queue once the app first asks for the
    /// center (Windows: registers the app ID, the Start-menu shortcut and the COM activator,
    /// which the shell needs some seconds to pick up before the first toast).
    func prepare()
    func authorization() -> PlatformAuthorization
    /// Shows a notification, replacing one shown with the same identifier.
    func post(_ notification: PlatformNotification) throws
    func remove(identifiers: [String])
    func removeAll()
    /// Sets the app's badge count when the platform has one of its own (Linux's launcher
    /// entry); false when the app's dock tile (AppKit) should show it instead.
    func setBadgeCount(_ count: Int) -> Bool
    /// Called on any thread with what happened to a shown notification.
    func setEventHandler(_ handler: @escaping @Sendable (PlatformNotificationEvent) -> Void)
}

extension PlatformNotifier {
    func prepare() {}
}

/// What the running app is called on the platform: Windows' AppUserModelID and display name,
/// the freedesktop app name and desktop entry.
struct PlatformAppIdentity: Sendable {
    var identifier: String
    var displayName: String
    var executablePath: String

    static var current: PlatformAppIdentity {
        let bundle = Bundle.main
        let executable = bundle.executableURL?.path ?? CommandLine.arguments.first ?? "app"
        let stem = ((executable as NSString).lastPathComponent as NSString).deletingPathExtension
        let identifier = bundle.bundleIdentifier ?? "AppKitCross.\(stem)"
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? stem
        return PlatformAppIdentity(identifier: identifier, displayName: name, executablePath: executable)
    }
}

/// The port's AppKit installs these when NSApplication starts (Sources/AppKit/Support/
/// UserNotificationsBridge.swift); without AppKit the process counts as inactive, so every
/// notification is shown without asking the delegate, and a badge has nowhere to go.
@_spi(AppKitCross)
public enum UNPlatformHooks {
    /// Whether the app is frontmost; read on the main thread before `willPresent`.
    nonisolated(unsafe) public static var isApplicationActive: (@MainActor () -> Bool)?
    /// Brings the app forward for a click or a `.foreground` action.
    nonisolated(unsafe) public static var activateApplication: (@MainActor () -> Void)?
    /// Shows the badge on the dock tile (taskbar overlay) where the platform has no badge.
    nonisolated(unsafe) public static var setApplicationBadge: (@MainActor (Int) -> Void)?
}

/// Records what it is asked to show. The macOS test build's default backend (apps on macOS
/// use Apple's framework, never this) and the base of the tests' fakes.
final class InMemoryNotifier: PlatformNotifier, @unchecked Sendable {
    private let lock = NSLock()
    private var _authorization: PlatformAuthorization
    private var _shown: [PlatformNotification] = []
    private var _badge: Int?
    private var _handler: (@Sendable (PlatformNotificationEvent) -> Void)?
    private let ownsBadge: Bool

    init(authorization: PlatformAuthorization = .allowed, ownsBadge: Bool = true) {
        _authorization = authorization
        self.ownsBadge = ownsBadge
    }

    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    var shown: [PlatformNotification] { locked { _shown } }
    var badge: Int? { locked { _badge } }
    func setAuthorization(_ a: PlatformAuthorization) { locked { _authorization = a } }

    func authorization() -> PlatformAuthorization { locked { _authorization } }
    func post(_ notification: PlatformNotification) throws {
        locked {
            _shown.removeAll { $0.identifier == notification.identifier }
            _shown.append(notification)
        }
    }
    func remove(identifiers: [String]) { locked { _shown.removeAll { identifiers.contains($0.identifier) } } }
    func removeAll() { locked { _shown.removeAll() } }
    func setBadgeCount(_ count: Int) -> Bool {
        guard ownsBadge else { return false }
        locked { _badge = count }
        return true
    }
    func setEventHandler(_ handler: @escaping @Sendable (PlatformNotificationEvent) -> Void) { locked { _handler = handler } }

    /// Simulates the platform reporting an event, as the real notifiers do from their threads.
    func send(_ event: PlatformNotificationEvent) {
        if case let .dismissed(id, reason) = event, reason != .timedOut { remove(identifiers: [id]) }
        if case let .activated(id, _, _) = event { remove(identifiers: [id]) }
        let handler = locked { _handler }
        handler?(event)
    }
}

func makeDefaultNotifier() -> PlatformNotifier {
    #if os(Windows)
    return WindowsToastNotifier(identity: .current)
    #elseif os(Linux)
    return FreedesktopNotifier(identity: .current)
    #else
    return InMemoryNotifier()
    #endif
}
