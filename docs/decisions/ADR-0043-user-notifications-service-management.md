# ADR-0043: UserNotifications and ServiceManagement on Windows and Linux

Date: 2026-11-17. Status: accepted.

## Context

Daily To Do (PR 70, the first vendored real app) imports `UserNotifications` for its midday
reminder and `ServiceManagement` for "open at login". The port had neither, so the app built
against two shims in `Examples/DailyTodo/Shims` that printed the reminder on stderr and
reported no login item. Local notifications and a login item are common in Mac utilities, so
both become real modules under Apple's names, on Windows and Linux. On macOS apps keep Apple's
frameworks.

## Decision

### Modules and the build

`Sources/UserNotifications` and `Sources/ServiceManagement` are built on Windows and Linux as
`UserNotifications` and `ServiceManagement` (library products too). AppKit depends on both, so
any target that uses AppKit can `import UserNotifications` without naming it in its package
manifest, as on macOS. AppKit does not re-export them, and neither does Apple's. Daily To Do now
builds unmodified with no shim. On macOS the same sources build as `UserNotificationsPortable` and
`ServiceManagementPortable`, used only by the tests. A module named `UserNotifications` in the
package's build directory would shadow Apple's for every macOS target.

`Sources/CWinAppServices` (Windows only) is the C++ shim for both: WinRT toasts, AUMID
registration, the Run key, the Startup-folder shortcut and `ShellExecute`. It is plain COM over
the WinRT ABI headers, with no WRL or C++/WinRT. It never initializes COM on the caller's
thread: `CoIncrementMTAUsage` keeps the multithreaded apartment alive, so calls from the main
thread do not change the apartment the Win32 backend's OLE drag and drop needs. Linux uses the
existing `CDBus` system library.

### UserNotifications: the center owns the state

`UNUserNotificationCenter` does the work Apple's notification daemon does. It runs the
authorization flow and keeps the categories, the pending requests with their timers, and the
delivered list, all on one serial queue. A `PlatformNotifier` only shows and removes
notifications and reports back clicks, button presses, text replies and dismissals. The
notifiers are `WindowsToastNotifier`, `FreedesktopNotifier` and `InMemoryNotifier` (the macOS
test build and the tests' fakes). The Windows toast XML (`ToastXML`) and the freedesktop
`Notify` arguments (`FreedesktopPayload`) are pure Swift, so the macOS tests check them.

**Authorization.** Neither platform prompts on the app's behalf. Status is `notDetermined`
until the app calls `requestAuthorization` (the requested options are kept in the app's user
defaults). After that it is `authorized`, or `provisional` when `.provisional` was requested,
while the platform lets the app notify, and `denied` while it does not. On Windows "does not"
means the toast notifier's `NotificationSetting` is off: the user turned the app or all
notifications off, or policy did. On Linux it means no notification server answers on the
session bus. `add` fails with `UNError.notificationsNotAllowed` unless the status is authorized
or provisional, as Apple's does. Settings report sound, badge and alert per the requested
options; lock screen, CarPlay, critical and time-sensitive are `.notSupported`.

**Delivery.** A request with no trigger is delivered at once. Time-interval and calendar
triggers run on `DispatchSourceTimer`s against the wall clock, and repeating triggers re-arm.
Delivery needs the app to be running. Unlike Apple's, pending requests do not outlive the
process: Windows and Linux have no daemon that would hold an unpackaged app's schedule (the
Windows scheduled-toast API needs package identity to survive the app). A request with the
identifier of a pending one replaces it.

**Presentation follows Apple's rule.** When the app is frontmost, the center asks the
delegate's `willPresent` on the main queue. A delegate that does not implement it, or no
delegate, means nothing is shown. When the app is not frontmost, the notification is shown
with banner, list, sound and badge. The options are then limited to what was authorized
(provisional is list only and silent). A banner is a normal toast or notification. List-only
is a toast with `SuppressPopup` (straight to Action Center) on Windows, and low urgency on
Linux, which GNOME Shell and KDE Plasma put in the list without a banner. The UserNotifications
module cannot depend on AppKit, so the port's `NSApplication` installs three hooks
(`UNPlatformHooks`, SPI): whether the app is active, how to bring it forward, and where to show
the badge. Without AppKit the process counts as inactive.

**Responses.** A click on the notification is `UNNotificationDefaultActionIdentifier`. A button
is its `UNNotificationAction` identifier. A text-input action gives a
`UNTextInputNotificationResponse` with the typed text. Clicks and `.foreground` actions bring
the app forward. A user dismissal reaches the delegate as `UNNotificationDismissActionIdentifier`
only when the category has `.customDismissAction`. A Windows toast that timed out into Action
Center stays in the delivered list. The delegate protocol has both of Apple's forms of
`willPresent` and `didReceive` (completion handler and async), each with a default that calls
the other. A task-local flag tells the async default that it was reached from the completion
default, so a delegate that implements neither gets Apple's result instead of a loop.

**Windows.** The app registers an AppUserModelID (its bundle identifier, otherwise
`AppKitCross.<exe>`) under `HKCU\Software\Classes\AppUserModelId` with its display name. That ID
becomes the process's AUMID unless the process already has one. Toasts use the `ToastGeneric`
template: up to three text lines (title, subtitle, body), one inline image attachment, up to
five buttons, and a text box per text-input action. Each toast gets a tag (the identifier,
hashed when longer than 64 characters) and one group for the app. Removal uses
`ToastNotificationHistory`. An unpackaged app has no COM activator, so activation arrives only
through the toast object's `Activated` event. The shim keeps every shown toast and its handlers
alive until the toast is activated, dismissed or removed. A toast clicked in Action Center while
the app runs therefore still reaches the delegate. One clicked after the app quit starts
nothing. Every action uses foreground activation, because background activation needs the COM
activator. Sound is the system notification sound or silence, since an unpackaged toast cannot
name its own audio file. Windows has no badge for an unpackaged app; the badge goes to the dock
tile.

**Linux.** The notifier owns a private session-bus connection on its own serial queue. A
dispatch read source on the bus socket delivers the server's signals: `ActionInvoked`,
`NotificationClosed` and KDE's `NotificationReplied`. It never touches AppKit's bus connections
or poll loop. `Notify` sends the title as the summary and the subtitle and body as the body
(escaped when the server takes markup). It sends the actions with `default` for the click, plus
a `desktop-entry` hint, urgency, `sound-name` `message-new-instant` or `suppress-sound`, and
`image-path` for an image attachment. A text-input action becomes `inline-reply` where the
server supports it; elsewhere it is a plain button whose response carries empty text. The badge
goes through AppKit's dock tile, which already sends the Unity launcher entry.

### ServiceManagement: the app's login item

`SMAppService.mainApp` registers the running executable. `status` reads the registration back
on every call, so changes made in the system's own settings show.

- **Windows.** A value named after the app under
  `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` holds the quoted executable path. If the
  Run key cannot be written, the fallback is `<Startup folder>\<app>.lnk`. An entry the user
  turned off in Task Manager or Settings (`Explorer\StartupApproved`, low bit set) reads back as
  `.requiresApproval`, which is the same meaning as Apple's.
  `openSystemSettingsLoginItems()` opens `ms-settings:startupapps`.
- **Linux.** An XDG autostart entry, `$XDG_CONFIG_HOME/autostart/<app id>.desktop` (default
  `~/.config/autostart`), with the Exec value quoted per the Desktop Entry specification. An
  entry with `Hidden=true` or `X-GNOME-Autostart-enabled=false` is `.requiresApproval`. An entry
  under our name that points at another executable (the app moved) is `.notRegistered`, and
  `register()` rewrites it. `openSystemSettingsLoginItems()` opens KDE's Autostart module or
  GNOME Tweaks. When neither is installed, it opens the autostart folder.

Errors are `NSError`s in `SMAppServiceErrorDomain` carrying the `kSMError…` codes:
`unregister()` of an item that is not registered throws `kSMErrorJobNotFound`, and a failed
write throws `kSMErrorInternalFailure` with the underlying error. Helper services
(`loginItem(identifier:)`, launch agents and daemons) need bundle layouts the port's apps do not
have, so they are not provided.

### Considered

- **Shell_NotifyIcon balloons on Windows.** They need a notification-area icon, cannot carry
  buttons, and Windows 10 and 11 turn them into plain toasts anyway.
- **The Windows App SDK's `AppNotificationManager`.** It handles activation after the app quits,
  but it adds a redistributable runtime that the port does not otherwise need.
- **The XDG notification portal (`org.freedesktop.portal.Notification`).** Inside Flatpak it is
  the right interface. Outside a sandbox it needs a desktop file the portal can match, and its
  activations go through `org.freedesktop.Application`, which the port's apps do not export.
  The plain notification server works everywhere.
- **systemd user units for the Linux login item.** XDG autostart is what every desktop's startup
  settings show and edit; systemd units are not.

## Consequences

- Daily To Do's midday reminder is a real toast or notification. Its "Open at login" still
  stops at its own `Bundle.main.bundleURL.pathExtension == "app"` check off macOS (upstream
  behaviour, unchanged).
- HelloWindow's Layout Demo has a "notifications" tab (`APPKITWIN_LAYOUT_TAB=notifications`)
  for checking by hand.
- Tests: `UserNotificationsTests` (the center against the in-memory notifier, the toast XML,
  the `Notify` arguments) and `ServiceManagementTests` (the XDG backend in a temporary directory,
  error paths over a fake) run on every platform. `FreedesktopNotifierTests` (Linux) owns
  `org.freedesktop.Notifications` on the session bus and plays the server. It skips without a
  session bus or when a real server owns the name; run it under `dbus-run-session`.
- Follow-ups: activation after the app quit on Windows (a COM activator registered with the
  AUMID, launching the app with the toast's arguments); persisting pending requests across
  launches; `NSUserNotificationCenter` on the same seam; the toast app icon (`IconUri`) from
  the app's icon.
