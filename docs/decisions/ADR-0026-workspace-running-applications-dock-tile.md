# ADR-0026: NSWorkspace, NSRunningApplication and NSDockTile

Date: 2026-11-10. Status: accepted, awaiting verification on the Windows PC.

## Context

`NSWorkspace` is AppKit's door to the rest of the system: opening URLs and documents
with their applications, revealing files in the Finder, file and application icons,
which application opens what, the trash, the applications that are running with
notifications about their activation and lifetime, sleep, wake, screen and session
notifications, the accessibility display settings, the desktop picture and file types.
`NSRunningApplication` is one of those applications (activate, hide, terminate, its
identity and icon); `NSDockTile` is the application's icon in the Dock with its badge.

Windows and Linux have all of this, spread over their own services: the shell on Windows
(ShellExecute, Explorer, the system image lists, file associations, the Recycle Bin, the
taskbar, the window list, system parameters and the personalization registry); on Linux
the freedesktop.org conventions (desktop entries, `mimeapps.list`, shared-mime-info, icon
themes, the trash specification, the file manager's and the portals' D-Bus interfaces,
logind, the EWMH window properties) under a desktop that may or may not implement each.
The port had 192 stubs for `NSWorkspace` and none of the three classes did anything.

## Decision

### The seam

`Platform/Workspace.swift` declares `PlatformWorkspace`, the backend's view of the
shell, and `PlatformBackend.workspace` (the host workspace by default). The core owns the
API, the caching, the notification center and the `NSRunningApplication` objects; the
platform answers with plain values:

- `open(_:)`, `open(_:withApplicationAt:options:)` (launching, answering the process),
  `revealFiles(_:selecting:)`.
- `applicationURLs(toOpen:)` for a file, a filename extension or a URL scheme
  (`PlatformOpenTarget`), `applicationURL(withBundleIdentifier:)`, `setDefaultApplication`.
- `icon(for:size:scale:)` for a file, an extension, a folder, an application or a process
  (`PlatformIconTarget`), as pixels; nil lets the core draw a generic one.
- `recycle(_:)`, `noteFileSystemChanged(_:)`.
- `runningApplications`, `frontmostProcessIdentifier`, `runningApplication(withProcessIdentifier:)`,
  `activate`/`hide`/`unhide`/`terminate(processIdentifier:force:)`, `executableArchitecture`.
- `accessibilityDisplayOptions`, `desktopImageURL(forDisplay:)`, `setDesktopImageURL`.
- `setDockTile(_:)` with the badge label, the badge drawn by the core as an overlay image
  and, when the application has an icon of its own (a content view or
  `applicationIconImage`), that icon with the badge composited.
- `startMonitoring()` and an observer that receives `PlatformWorkspaceEvent`s: application
  activation, launch, termination, hide and unhide, sleep and wake, screens sleeping and
  waking, the session resigning and becoming active, accessibility options changing.

`PlatformRunningApplication` is the value behind an `NSRunningApplication`: process id,
name, identity (`bundleIdentifier`), executable, the "application URL" (`urlForApplication`'s
answer), launch date, active, hidden, whether it shows windows.

### The core

- `NSWorkspace.shared` keeps one `NSRunningApplication` per process until it is seen
  terminated, as Apple does, so observers can compare objects. The list is refreshed from
  the platform on every `runningApplications`/`frontmostApplication` read and on the
  platform's events; differences post `didLaunch`/`didTerminate`, the foreground change
  `didDeactivate` then `didActivate` with the application under `applicationUserInfoKey`.
  Monitoring starts when something first asks for the notification center or the
  running applications.
- The current application is special: its activation and hidden state come from
  `NSApplication` (which tells the workspace when it activates, deactivates, hides and
  unhides), its icon is `applicationIconImage` when set, and when the platform reports
  another process in the foreground the workspace deactivates `NSApp` (the window
  backends only report key windows), so `NSApp.isActive` is right on every platform.
- `NSRunningApplication`'s properties answer on any thread behind a lock; the actions
  hop to the main actor. Key-value observing of them needs the Objective-C runtime; the
  workspace notifications carry the same changes.
- Icons are 32-point `NSImage`s (the shell's large icons) cached per target. Where the
  platform has none (Linux without a theme PNG, the host backend) `_NSWorkspaceIcons`
  draws a document with the extension, a folder or an application, so every platform
  answers with an image.
- File types go through UniformTypeIdentifiers: `type(ofFile:)`, `preferredFilenameExtension`,
  `filenameExtension(_:isValidForType:)`, `type(_:conformsToType:)`, `localizedDescription`,
  `isFilePackage(atPath:)` (a directory whose extension names a package type). AppKit
  now depends on the UniformTypeIdentifiers target on Windows and Linux, which lets the
  `UTType` members (`icon(for:)`, `urlForApplication(toOpen:)`, `setDefaultApplication(at:toOpen:)`)
  be declared instead of skipped.
- `recycle` and `duplicate` come in the async and the completion-handler forms;
  `duplicate` copies next to the original as "name copy.ext", "name copy 2.ext" (Finder's
  naming). The deprecated `openFile`, `launchApplication`, `fullPath(forApplication:)`,
  `performFileOperation` and `activeApplication()` are thin covers over the same
  primitives.
- `NSDockTile`: `badgeLabel`, `showsApplicationBadge`, `contentView` and `display()`;
  the badge is a red pill with the label drawn by the core (16 points high), the content
  view is rendered at the tile's 128-point size. `NSApplication.dockTile` is the one the
  platforms show; `NSWindow.dockTile` exists (a minimised window's tile) but the
  platforms have no separate tile for a window, so it reaches nothing.
- `NSApplication.hideOtherApplications`, `unhideAllApplications` and
  `yieldActivation(to:)` go through the workspace.

### Windows (`Win32Workspace.swift`, `cd2d_shell.cpp`)

- Opening and launching: `ShellExecuteEx` (`SEE_MASK_NOCLOSEPROCESS` for the new process
  id, the show command from `activates`/`hides`), documents quoted as `CommandLineToArgv`
  expects. The launch environment cannot be passed through ShellExecute (traced).
- Revealing: `SHOpenFolderAndSelectItems` with the items' PIDLs (a folder opens through
  ShellExecute).
- Icons: `SHGetFileInfo` with `SHGFI_SYSICONINDEX` (and `SHGFI_USEFILEATTRIBUTES` for an
  extension or a folder that need not exist), the matching system image list (`SHIL_SMALL`,
  `SHIL_LARGE`, `SHIL_EXTRALARGE`, `SHIL_JUMBO`), the icon drawn into a 32-bit DIB with
  `DrawIconEx` (the mask supplies alpha for icons without one).
- Associations: `AssocQueryString(ASSOCSTR_EXECUTABLE)` for the default (`ASSOCF_IS_PROTOCOL`
  for schemes; OpenWith.exe is not a handler), `SHAssocEnumHandlers` for the rest.
  `urlForApplication(withBundleIdentifier:)` matches a running process's Application User
  Model ID, then the App Paths registry, then `SearchPath` for `<name>.exe`.
  `setDefaultApplication` throws: Windows 10 and later let only the user choose defaults.
- Recycling: `SHFileOperation` `FO_DELETE` with `FOF_ALLOWUNDO` (the bin's own names are
  not exposed, so the result dictionary is empty for Windows).
- Running applications: the processes that own visible, unowned, non-tool, uncloaked
  top-level windows (the taskbar's buttons), plus the processes launched here while they
  live. Name from the executable's `FileDescription` version string, identity from the
  Application User Model ID (packaged applications) or the executable's base name, launch
  date from `GetProcessTimes`. Hidden means every window minimised; `hide` minimises,
  `unhide` restores, `activate` restores and `SetForegroundWindow`s the first window,
  `terminate` posts `WM_CLOSE` to each window, `forceTerminate` is `TerminateProcess`.
- Events: a WinEvent hook for `EVENT_SYSTEM_FOREGROUND` and minimise start/end; a hidden
  top-level window (broadcasts never reach message-only windows) for `WM_SETTINGCHANGE`
  (accessibility options), `WM_POWERBROADCAST` (suspend and resume; the console display
  state through `RegisterPowerSettingNotification` for the screens) and
  `WM_WTSSESSION_CHANGE` (lock/unlock, console connect/disconnect, through
  `WTSRegisterSessionNotification`); a two-second timer that diffs the window list for
  launches and terminations.
- Accessibility: `SPI_GETCLIENTAREAANIMATION` (off is reduced motion),
  `SPI_GETHIGHCONTRAST`, `SPI_GETSCREENREADER` (a screen reader is VoiceOver's
  counterpart), the personalization registry's `EnableTransparency` (off is reduced
  transparency). Nothing on Windows differentiates without colour or inverts colours
  system-wide as a setting applications see, and there is no Switch Control: those
  answer false.
- Desktop picture: `SPI_GETDESKWALLPAPER`/`SPI_SETDESKWALLPAPER` (one picture for every
  display; the screen argument is ignored).
- Dock tile: `ITaskbarList3::SetOverlayIcon` with the badge on every titled window (the
  taskbar shows the active window's overlay for the group), `WM_SETICON` with the
  composed icon when the tile has a content view or the application an icon image;
  windows created later get both.

### Linux (`LinuxWorkspace.swift`, `LinuxWorkspaceBus.swift`, `LinuxWorkspaceX11.swift`)

- Desktop entries from the XDG data directories (`applications/`, ids with "-" for "/"),
  parsed for Name (localized by `LANG`), Exec, Icon, TryExec, MimeType, NoDisplay,
  StartupWMClass. MIME types from the UTI table's tags, else shared-mime-info's `globs2`;
  directories are `inode/directory`, schemes `x-scheme-handler/<scheme>`. Associations as
  the specification resolves them: `<desktop>-mimeapps.list` and `mimeapps.list` in the
  config and application directories (defaults, added, removed), then `mimeinfo.cache`,
  then the entries' MimeType lists. `setDefaultApplication` writes the user's
  `mimeapps.list`.
- Launching expands the Exec line's field codes (`%f %F %u %U %i %c %k`, the deprecated
  ones dropped, quoting as the specification), resolves the command on PATH and spawns it
  with Foundation's `Process`; the exit is reaped and reported. Without a handler the
  OpenURI portal is tried, then `xdg-open`. The "application URL" is the `.desktop` file;
  `urlForApplication(withBundleIdentifier:)` takes a desktop entry id (with or without
  `.desktop`) or a command on PATH.
- Revealing: `org.freedesktop.FileManager1.ShowItems`/`ShowFolders` on the session bus
  (started on demand when activatable), else the folder opens with its handler.
- Icons: the icon theme (`APPKITWIN_ICON_THEME`, the Settings portal's `icon-theme`, the
  GTK settings file, KDE's globals, else hicolor), its `Inherits` chain and hicolor,
  the `<size>x<size>/<context>` directories (PNG only: the port decodes no SVG; the core
  draws the rest), `pixmaps/` last. Icon names: `text-plain` for `text/plain`, the
  `generic-icons` family, `<media>-x-generic`; `folder`; an entry's `Icon` or
  `application-x-executable`.
- Recycling: the Trash portal when there is one, else the XDG trash specification in
  `$XDG_DATA_HOME/Trash` (`files/` and `info/*.trashinfo` with the path and the deletion
  date; a taken name gets ".2", ".3", …).
- Running applications: on X11 the window manager's `_NET_CLIENT_LIST` with each window's
  `_NET_WM_PID`, `_NET_WM_STATE` (hidden) and `WM_CLASS`, the active one from
  `_NET_ACTIVE_WINDOW`; the entry for a window from `StartupWMClass` or the class as an
  id, else the executable's entry; name, executable and launch date from `/proc`. The
  processes launched here are listed while they live. `activate` and `unhide` send
  `_NET_ACTIVE_WINDOW` (source indication 2, a pager), `hide` is `XIconifyWindow`,
  `terminate` the `WM_DELETE_WINDOW` protocol (else `SIGTERM`), `forceTerminate` `SIGKILL`.
  The backend selects PropertyNotify on the root window and the workspace diffs the list
  on each change. Wayland has no window list: the running applications are those
  launched here and this one, there is no frontmost process and activation, hiding and
  closing other applications answer false.
- D-Bus (one private session-bus and one system-bus connection, pumped from the
  backends' poll loops): the Settings portal's `SettingChanged` (accessibility), the
  screen saver's `ActiveChanged` (screens sleep and wake), logind's `PrepareForSleep`
  (will sleep, did wake) and this process's session `Lock`/`Unlock` and `Active`
  property (session resigning and becoming active).
- Accessibility through the Settings portal: GNOME's `enable-animations` off or KDE's
  `AnimationDurationFactor` 0 is reduced motion, `high-contrast` or a HighContrast GTK
  theme increased contrast, `screen-reader-enabled` VoiceOver. Without a portal every
  option reads false. Nothing reduces transparency, differentiates without colour or
  inverts colours as a setting; there is no Switch Control.
- Desktop picture: `gsettings` (`org.gnome.desktop.background picture-uri`, read and
  written, `picture-uri-dark` too), the Settings portal to read without gsettings; other
  desktops throw `unsupported`.
- Dock tile: the `com.canonical.Unity.LauncherEntry.Update` signal (`count`,
  `count-visible`; a non-numeric label marks the entry urgent instead) that Dash to Dock,
  KDE's task manager and others read, and on X11 the composed icon as `_NET_WM_ICON` on
  this application's windows (the badge on the executable's own icon when the tile has
  none). Wayland windows have no icon protocol in this port.

### Host backend (`HostWorkspace`)

An in-memory stand-in for the tests and for platforms without a backend of their own:
records opened and revealed URLs and launches, keeps handlers and icons a test sets,
lists this process plus the applications a test registers, moves recycled items into a
trash folder under the temporary directory, and injects events with `postEvent`.

### Still `unimplemented()`

With no counterpart on Windows or Linux: the Finder labels (`fileLabels`,
`fileLabelColors`), removable media and ejecting (`mountedRemovableMedia`,
`unmountAndEjectDevice`, `getFileSystemInfo`), `extendPowerOff(by:)`, `requestAuthorization`,
`setIcon(_:forFile:)` (custom file icons), `desktopImageOptions`, `showSearchResults`
(Spotlight), `terminateAutomaticallyTerminableApplications`, `OpenConfiguration.isForPrinting`
(the launch-to-print verb is an application's own), `requiresUniversalLinks` (throws),
`activeSpaceDidChangeNotification`, the volume notifications and
`willPowerOffNotification` (never posted). The macOS 26 message types stay generated
stubs.

## Consequences

- `NSApplication.isActive` now follows the real foreground on Windows and X11 once the
  workspace is monitoring (the first use of its notification center or running
  applications), which the Win32 and X11 window backends did not report before.
- The process list costs a window enumeration per `runningApplications` read and every
  two seconds while monitoring on Windows; on X11 one round trip per root property change.
- Linux desktops without a portal, a FileManager1 service or an icon theme degrade to
  `xdg-open`, opening the folder, and the package's drawn icons; nothing fails.
- Not done: SVG theme icons, per-display wallpapers on Windows, the Wayland window icon
  (xdg-toplevel-icon), `NSWindow.dockTile` on the platforms, `NSDockTilePlugIn`.
- Tests: `WorkspaceTests` on the host workspace (the current application, opening and
  revealing, launching with the running-application substitution and the completion
  handlers, icons from the platform or drawn, file types, recycle and duplicate, the
  application notifications against platform events, power, session and accessibility
  notifications, the dock tile's badge and icon) and `LinuxWorkspaceTests` against a
  temporary XDG tree (a stub desktop entry resolved through `mimeapps.list` and launched
  with the file, icons from a theme directory, the trash). `Examples/Workspace` drives
  the real shells; `tools/linux/run.sh` screenshots it under Xvfb.
