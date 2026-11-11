# Workspace

`NSWorkspace`, `NSRunningApplication` and `NSDockTile` on the shell (ADR-0022).

What it demonstrates:

- `NSWorkspace.open(_:)` with a URL: the default browser opens it (ShellExecute on
  Windows, the `x-scheme-handler` desktop entry or `xdg-open` on Linux).
- `activateFileViewerSelecting(_:)` reveals this executable in Explorer or the file
  manager (`org.freedesktop.FileManager1.ShowItems`); `selectFile(nil, inFileViewerRootedAtPath:)`
  opens a folder.
- `icon(forFileType:)`, `icon(for: UTType)`, `icon(forFile:)` and
  `NSRunningApplication.current.icon`: the shell's icons for `.txt`, `.pdf`, a folder
  and the application (the system image list on Windows, the icon theme on Linux; the
  package draws a generic document, folder or application where the platform has none).
- `recycle(_:completionHandler:)` moves a temporary file to the Recycle Bin or the XDG
  trash.
- `NSApp.dockTile.badgeLabel` shows a count on the taskbar button (an overlay icon on
  Windows; the launcher count and the window icon on Linux).
- The frontmost application, kept current by `didActivateApplicationNotification`;
  launching, activating, hiding and terminating another application found by
  `urlForApplication(withBundleIdentifier:)` and `runningApplications(withBundleIdentifier:)`
  (`notepad` on Windows, a desktop entry id such as `org.gnome.TextEditor` on Linux).
- The log lists the workspace notifications as they arrive: application activation and
  lifetime, sleep and wake, screens, the session, accessibility settings.

`swift run Workspace --report` prints the workspace's answers without a window.
`swift run Workspace --open <url> --stay <seconds>` opens the URL right after launch and
quits after that long, with the launch, activation and termination notifications on the
console (the Windows CI runs it against a stub scheme handler).
