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
thread, so calls from the main thread do not change the apartment the Win32 backend's OLE drag
and drop needs. Every toast call runs on one thread the shim owns, in the multithreaded
apartment, and the caller waits for it. The notifier is created once and called from the main
thread, the center's queue and trigger timers; a WinRT object used outside the apartment that
created it fails with `RPC_E_WRONG_THREAD` (found on the PC). The shim traces the toast thread,
its apartment and the calling thread when it creates the notifier and when a toast fails
(every toast with `APPKITWIN_TRACE_TOASTS` set). Linux uses the
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
means the toast notifier's `NotificationSetting` is one of the disabled values: the user
turned the app or all notifications off, or policy or the manifest did. An AppUserModelID that
has never shown a toast has no settings entry yet, and the setting read fails with
`ERROR_NOT_FOUND`; Windows creates the entry, enabled, with the first toast, so that counts as
allowed. On Linux it means no notification server answers on the
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
becomes the process's AUMID unless the process already has one. The registry entry alone is not
enough: on Windows 11 (build 26200, checked on the PC) every toast of a registry-only ID is
accepted, listed in the history and never displayed, and neither `IconUri` nor a
`CustomActivator` value changes that. The shell displays them once a Start-menu shortcut carries
the ID. So the notifier, when it is first created, makes sure
`<Start menu>\Programs\<display name>.lnk` starts the running executable with
`System.AppUserModel.ID` set to the ID and `System.AppUserModel.ToastActivatorCLSID` set to the
app's toast activator (below). It adds the ID to an existing shortcut to the same
executable, and it uses `<ID>.lnk` when another program's shortcut has the display name. The
shortcut stays, like an installed app's Start-menu entry; an installer that makes its own with
the ID makes this a no-op. The center creates the notifier, and with it the shortcut, when
the app first asks for `UNUserNotificationCenter.current()`, which apps do at launch to set the
delegate, so the shortcut is usually in place well before the first toast. The shell takes
some seconds to pick up a new shortcut and drops the toasts shown before then. So for 30
seconds after the process made the shortcut, the shim shows each new toast again every 3
seconds while it is still the toast under its tag, until the shell reports anything about one
of the app's toasts (a click, a close, a timeout into the notification center) or records the
app under `Notifications\Settings\<ID>`. That key alone is not a reliable sign: on the PC
it appeared in one run and not in another where toasts displayed. Toasts use the `ToastGeneric`
template: up to three text lines (title, subtitle, body), one inline image attachment, up to
five buttons, and a text box per text-input action. Each toast gets a tag (the identifier,
hashed when longer than 64 characters) and one group for the app. Removal uses
`ToastNotificationHistory`.

A click on a live banner raises the toast object's `Activated` event, but a click in the
notification center does not: on the PC the toast closed and nothing reached the app. The shell
sends those to the app's COM toast activator, as for any unpackaged app. So the shim registers
one: a CLSID made once per ID and kept as the ID's `CustomActivator` value,
`HKCU\Software\Classes\CLSID\{clsid}\LocalServer32` naming the executable, the CLSID on the
shortcut, and the class object (`INotificationActivationCallback`) registered in the running
process. The activator gets only the activation arguments, so the toast's `launch` and each
button's `arguments` carry the tag as well as the action identifier, each percent-encoded. A
click can arrive both ways; the shim reports it once, and only while the toast is still the one
shown under its tag. A toast clicked after the app quit starts the app (COM runs it with
`-Embedding`), but the click is not reported, since the new process has no record of it. Every
action uses foreground activation. Sound is the system notification sound or silence, since an unpackaged toast cannot
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
- Follow-ups: reporting a click that launched the app on Windows (the activator already starts
  it; the center would need the delivered notification back); persisting pending requests across
  launches; `NSUserNotificationCenter` on the same seam; the toast app icon (`IconUri`) from
  the app's icon.
