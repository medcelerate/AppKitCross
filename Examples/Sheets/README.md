# Sheets

An AppKit window that presents every kind of attached sheet (ADR-0019), with a SwiftUI pane.

What it demonstrates:

- `NSAlert.beginSheetModal(for:)`: the alert attached under the title bar, ended by its
  buttons (Return for the first, Escape for Cancel), the response in the completion handler.
- `NSOpenPanel.beginSheetModal(for:)`.
- `NSWindow.beginSheet(_:completionHandler:)` with a custom window: a text field, Cancel
  (Escape) and OK (Return), and a button that begins a sheet on the sheet itself.
- The old application-modal pattern: `beginSheet`, `NSApplication.runModal(for:)`,
  `stopModal(withCode:)`, `endSheet(_:returnCode:)`.
- Two sheets begun at once: the second waits in `sheets` until the first ends.
- SwiftUI `.sheet` (Escape or its Done button dismisses it, `onDismiss` reports) and
  `.confirmationDialog` with a destructive and a cancel button.
- What a sheet does to its parent: the window's content takes no clicks, the keyboard goes
  to the sheet, dragging or minimising the window takes the sheet along, and the close
  button refuses until the sheet ends. The sheet slides down on begin and up on end.

Run: `swift run Sheets`. For scripted runs, `--alert`, `--custom`, `--open`, `--queued` or
`--swiftui-sheet` opens that sheet at launch.
