# Workspace

`NSWorkspace`, `NSRunningApplication` and `NSDockTile` on the shell (ADR-0022).

What it demonstrates:

- `NSWorkspace.open(_:)` with a URL: the default browser opens it (ShellExecute on
  Windows, the `x-scheme-handler` desktop entry or `xdg-open` on Linux).
- `selectFile(_:inFileViewerRootedAtPath:)` reveals this executable in Explorer or the file
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
  launching another application found by `urlForApplication(withBundleIdentifier:)`
  (`charmap` on Windows, a desktop entry id such as `org.gnome.TextEditor` on Linux), then
  activating, hiding and terminating that instance only, matched by the process identifier
  `openApplication` returned, never by name: an instance already running before Launch,
  perhaps with unsaved work, is never touched. Press Launch first; a test of Activate,
  Hide or Terminate uses the fresh instance the demo started. The demo also remembers
  which processes ran before Launch: when the launch went to one of them (as AppKit's
  `openApplication` answers the running instance of a single-instance application), the
  log says so and the three buttons refuse to act on it. On Windows 11 `notepad` (like
  `calc` and `mspaint`) is such an application and packaged besides: System32 holds a
  launcher stub that hands off to the Store package and exits, the workspace activates the
  package through its app execution alias (or follows the stub's hand-off by executable
  name when its window appears), and while a Notepad is already open that is the instance
  the launch answers with. So the default is `charmap`, an unpackaged application that
  starts a new process with a window every time; `msinfo32` is another.
- The log lists the workspace notifications as they arrive: application activation and
  lifetime, sleep and wake, screens, the session, accessibility settings.

`swift run Workspace --report` prints the workspace's answers without a window.
`swift run Workspace --open <url> --stay <seconds>` opens the URL right after launch and
quits after that long, with the launch, activation and termination notifications on the
console (the Windows CI runs it against a stub scheme handler).
