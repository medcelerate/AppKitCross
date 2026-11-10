# ADR-0017: The document architecture, the file panels and the Info.plist convention

Date: 2026-11-10. Status: accepted, awaiting verification on the Windows PC.

## Context

AppKit's document architecture (`NSDocument`, `NSDocumentController`,
`NSWindowController`) and the file panels (`NSSavePanel`, `NSOpenPanel`) were stubs. A
document-based application needs, on every platform: documents that read and write
themselves, a controller that knows the application's types and keeps the open and recent
documents, the File menu's actions reaching them through the responder chain, the
unsaved-changes alerts on close and quit, the file name and edited mark in the window
title, and an open/save dialog.

Three things macOS provides are missing off the Mac:

- `UndoManager` and `FileWrapper` are not in swift-corelibs-foundation.
- Document types come from the bundle's `Info.plist`; Windows and Linux executables have
  no bundle.
- The dialogs: Windows has the common item dialogs (`IFileOpenDialog`/`IFileSaveDialog`),
  Linux desktops provide theirs through the xdg-desktop-portal `FileChooser` interface on
  the session bus, and neither the host backend (tests, macOS) nor a Linux session
  without a portal has anything.

## Decision

### Foundation shims

`Sources/AppKit/Support/UndoManager.swift` and `FileWrapper.swift` provide the two classes
on platforms whose Foundation lacks them (`#if !canImport(Darwin)`), with Foundation's API
and semantics: closure-based undo registration, nested groups, grouping by event (the
implicit group closes when the main queue next runs), action names and the
`NSUndoManager…` notifications; regular-file, directory and symbolic-link wrappers that read
and write through `FileManager`. Selector-based undo registration and serialized
representations need the Objective-C runtime and are unavailable. Both names are listed in
`api-inventory/Foundation-windows-types.json`, so the generator emits members typed with
them (`NSWindowDelegate.windowWillReturnUndoManager`, `NSTextAttachment.fileWrapper`, ...)
instead of skipping them.

### Documents

`NSDocument`, `NSDocumentController` and `NSOpenSavePanelDelegate` are hand-written in
`Sources/AppKit/Core`. The override points are Apple's: reading goes URL → file wrapper →
data, writing `write(to:ofType:for:originalContentsURL:)` → `write(to:ofType:)` →
`fileWrapper(ofType:)` → `data(ofType:)`; each lowest level throws a Cocoa error naming
the method to override. `writeSafely` writes beside the destination and swaps the file in.
The change count follows Apple's rules and the document observes its undo manager's
did-close-group, did-undo and did-redo notifications. `save(_:)` saves in place or runs the
save panel as a sheet on `windowForSheet`; `canClose` shows Save / Cancel / Don't Save;
`revertToSaved` asks first; autosaving (elsewhere, or in place for classes that
`autosavesInPlace`) runs on `NSDocumentController.autosavingDelay`.

The responder chain: `NSWindow.windowController` becomes the window's `nextResponder`,
`NSWindowController.tryToPerform` tries its document, `NSApplication.sendAction` ends at
the delegate and then the shared document controller, and menu validation
(`NSApplication._target(forAction:)`) looks the same way. `NSWindow.performClose` and the
platform's close button ask the document before closing. `NSWindowController.
synchronizeWindowTitleWithDocumentName` sets the title (through
`windowTitle(forDocumentDisplayName:)`), `representedURL` and `isDocumentEdited`.

At launch a document-based application (one whose Info.plist declares
`CFBundleDocumentTypes`, or that already created a document controller) opens the files
named on the command line, else an untitled document when `applicationShouldOpenUntitledFile`
agrees; `terminate(_:)` reviews unsaved documents after the delegate's reply.

Selector-based completion callbacks (`canClose(withDelegate:shouldClose:contextInfo:)` and
friends) cannot be invoked without the Objective-C runtime. The port delivers the selector
through the target/action registry (`NSSelectorHandling` or `setActionHandler(for:)`) with
the Bool result as the sender; the closure and async forms work as on macOS.

Without the Objective-C runtime initializers are not inherited as `required`, so
`NSDocument.init()` is `required` on Windows and Linux (`init(contentsOf:ofType:)`,
`init(for:withContentsOf:ofType:)` and `init(type:)` are `required convenience` everywhere):
a subclass that overrides `init()` writes `required init()`, which macOS accepts too.

### The Info.plist convention

The document controller reads one dictionary, looked up in this order:

1. the file named by the `APPKITWIN_INFO_PLIST` environment variable;
2. `Info.plist` next to the executable;
3. `Bundle.main.infoDictionary` (on corelibs Foundation this is the adjacent file again;
   on macOS the bundle's).

`CFBundleDocumentTypes` entries are read as on macOS: `LSItemContentTypes` (the UTIs
documents are typed with), `CFBundleTypeExtensions`, `CFBundleTypeRole`,
`NSDocumentClass` (a `Module.Class` name resolved through the Swift runtime, or a bare
name tried against the executable's module) and `NSExportableTypes`.
`UTExportedTypeDeclarations`/`UTImportedTypeDeclarations` register their identifier,
parents, extensions and description with the port's `UTType` (`UTType._declare`), so
`typeForContents(of:)` can match a file's extension by conformance. A SwiftPM executable
keeps its plist as a resource (under another name: SwiftPM refuses a resource called
`Info.plist`) and points the variable at it from `main.swift` (`Examples/TextEdit`).

### The file-dialog seam

`PlatformBackend.fileDialog: (any PlatformFileDialog)?` (Platform/FileDialog.swift)
replaces the former `runFileDialog`. A backend that has a native dialog answers with an
object whose `run(_:parent:)` shows it modally for a `PlatformFileDialogOptions` (save or
open, title, prompt, message, directory, default name, extensions and their descriptions,
file/directory/multiple choices, hidden files) and returns the chosen URLs; nil means the
panel draws itself.

- Windows: `Win32FileDialog` over the CD2D shim's `cd2d_file_dialog`
  (`IFileOpenDialog`/`IFileSaveDialog`, type filters from the extensions, parented to the
  key window's HWND).
- Linux: `LinuxFileChooserPortal` talks `org.freedesktop.portal.FileChooser` over libdbus on
  a private session-bus connection: `OpenFile`/`SaveFile` with the `a{sv}` options
  (`handle_token`, `modal`, `multiple`, `directory`, `accept_label`, `current_name`,
  `current_folder`, glob `filters`), the request path predicted from the unique name and
  the token so the `Response` signal's match rule is in place before the call, and the
  backend's event pump run while waiting. The X11 backend parents with `x11:<xid>`;
  the Wayland backend passes no parent (xdg-foreign exports are a follow-up). Without a
  portal on the bus (or no session bus) the backend answers nil. zenity is no longer used.
- The host backend answers nil, or a `HostFileDialog` stand-in a test installs.

`APPKITWIN_FILE_DIALOG=package` forces the package-drawn panel everywhere (screenshots,
tests); `=native` is the default.

### The package-drawn panel

`NSSavePanel` builds its own content when there is no native dialog
(`_NSFilePanelController`): a message, the name field (save), a Where field with Up, the
directory listing in an `NSTableView` (name, date, size; folders and files the type filter
or the delegate rule out shown dimmed and unselectable), a type pop-up over
`allowedContentTypes`/`allowedFileTypes` (with All Files when other types are allowed),
New Folder (an alert with a name field), Cancel (Escape) and the prompt button (Return).
Keyboard: arrows move in the list, Return enters a folder or confirms, the name and Where
fields confirm or navigate on Return. The delegate's `shouldEnable`, `userEnteredFilename`,
`validate`, `didChangeToDirectoryURL`, `didSelect` and `panelSelectionDidChange` are
called at the same points as on macOS; the native path applies `validate` to the dialog's
answer. The controls are ordinary AppKit controls with accessibility labels, so the
panel is reachable through the UI Automation and AT-SPI bridges (ADR-0013).

`runModal` runs the panel through `NSApplication.runModal(for:)`, `begin` shows it
modeless with a completion, `beginSheetModal` attaches it with `NSWindow.beginSheet`
and ends it with `endSheet`. `NSOpenSavePanelDelegate` refines `NSWindowDelegate` so the
panel's delegate lives in the window's slot (Swift cannot redeclare `delegate` with a
narrower type, Objective-C can).

### Window titles

`NSWindow.isDocumentEdited` shows as a dot in the close button of the package-drawn title
bar (Wayland client-side decorations, `fullSizeContentView` windows), as macOS draws it,
and through `PlatformWindow.setDocumentEdited` as an asterisk before the native title on
Windows and X11/Wayland server-side decorations, which is how those platforms' own editors
mark it. `representedFilename` and `setTitleWithRepresentedFilename` are implemented over
`representedURL`.

### RTF

`NSAttributedString(rtf:documentAttributes:)`, `rtf(from:documentAttributes:)`,
`data(from:documentAttributes:)` and `init(data:options:documentAttributes:)` are
implemented in `Core/NSAttributedString+RTF.swift`: font table, colour table, per-run font,
size, bold, italic, underline and colour, paragraph alignment, `\uN` escapes; the reader
also takes Latin-1 `\'xx` escapes, `\uc`, skipped `\*` destinations and the common
symbol words. Images, tables, lists and styles are not read; RTFD stays unimplemented.

## Consequences

- `tools/apigen/config.json` lists the three new hand-written types and skips the four
  RTF members; `Foundation-windows-types.json` gained `FileWrapper` and `UndoManager`.
- `Examples/TextEdit` is the reference document application; `Tests/AppKitTests/
  DocumentTests.swift` covers the lifecycle, the change count with the undo manager,
  the save/revert/reopen round trip, type lookup, the Open Recent menu, the responder
  chain, the unsaved-changes flows, both panels driven programmatically, the shims and
  the RTF round trip on the host backend.
- Not done: `NSTextView` does not register undo actions, so a text document counts edits
  from the text-change notification rather than from its undo manager; printing, versions,
  sharing, state restoration, `NSPersistentDocument`; xdg-foreign parents for the portal
  dialog on Wayland; Windows and Linux desktops do not get file-type associations from the
  Info.plist (that is the installer's job on those platforms).
