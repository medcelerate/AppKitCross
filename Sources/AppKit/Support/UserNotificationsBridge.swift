// What the port's UserNotifications needs from the running app (ADR-0043): whether it is
// frontmost (Apple asks the delegate's willPresent only then), how to bring it forward for a
// click on a notification, and where to show the app badge (the dock tile: the taskbar
// overlay on Windows, the Unity launcher entry on Linux). UserNotifications cannot depend on
// AppKit, so NSApplication installs these when it starts.

#if os(Windows) || os(Linux)
@_spi(AppKitCross) import UserNotifications

@MainActor
enum UserNotificationsBridge {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        UNPlatformHooks.isApplicationActive = { NSApplication._shared?.isActive ?? false }
        UNPlatformHooks.activateApplication = { NSApplication._shared?.activate(ignoringOtherApps: true) }
        UNPlatformHooks.setApplicationBadge = { count in
            NSApplication._shared?.dockTile.badgeLabel = count > 0 ? String(count) : nil
        }
    }
}
#endif
