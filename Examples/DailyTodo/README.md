# DailyTodo

A real third-party SwiftUI macOS app built against AppKitCross as it is: [Daily To Do](https://github.com/Noreen21/daily-todo)
(MIT, `Sources/` vendored from upstream commit `213775aabe04fbdd90a78128d0f052c04601d91f`,
2026-11-06; its README is kept as [UPSTREAM-README.md](UPSTREAM-README.md), its license as
[LICENSE](LICENSE)). The point is not the app but what it finds: every build or runtime gap it
ran into is in [docs/compatibility/swiftui-apps.md](../../docs/compatibility/swiftui-apps.md),
with what was fixed in the port for it and what is a follow-up.

What the app uses, all of it common SwiftUI: a `WindowGroup` with `windowResizability`,
`NavigationStack` with `navigationTitle` and a `toolbar` button, `DatePicker` (`.field`, date
only and hour-and-minute), `TextField` with `onSubmit`, a `List` of rows with a checkbox
`Toggle`, `strikethrough` text and a `Label` button, `ContentUnavailableView` as the empty
state, a `.sheet` holding a grouped `Form` with `Section`s, a `Picker` over every known time
zone, `LabeledContent` rows and a `Done` toolbar button through `@Environment(\.dismiss)`,
an `ObservableObject` store passed by `environmentObject`, JSON persistence through
`JSONEncoder` and `FileManager` under Application Support, a repeating `Timer`, and two Apple
frameworks the port does not have: `UserNotifications` (the midday reminder) and
`ServiceManagement` (open at login).

## Layout

| Path | Contents |
| --- | --- |
| `Sources/DailyTodo` | The app (upstream, unmodified except one `#if canImport(ObjectiveC)` around an `@objc` in `ReminderScheduler.swift`, marked `AppKitCross:` in the source). |
| `Sources/DailyTodoCore` | The app's logic module (upstream, unmodified). |
| `Sources/DailyTodoChecks` | The app's dependency-free self-checks (upstream, unmodified); CI builds them everywhere and runs them on macOS and Linux. |
| `Shims/UserNotifications`, `Shims/ServiceManagement` | Modules under Apple's names for Windows and Linux only (the macOS host build uses the real frameworks); each file's header comment says which port gap it covers and what the real implementation would be. |

The three upstream targets are declared in the root `Package.swift` (the app depends on the
`AppKit` and `SwiftUI` products like the other examples, plus `Combine` and the two shims off
macOS) in Swift 5 language mode, as upstream's tools version 5.9 implies.

## Build and run

```bash
swift build --product DailyTodo && .build/debug/DailyTodo        # macOS host build, Linux
swift build --product DailyTodoChecks && .build/debug/DailyTodoChecks
```

On Windows (one job at a time, as CI does, see `docs/ci-windows-runner.md`):

```
swift build -c debug -j 1 --product DailyTodo
.build\debug\DailyTodo.exe
```

Tasks are saved to `DailyTodo/daily-todo.json` under the user's Application Support
directory (`~/Library/Application Support` on macOS, `%APPDATA%` or `%LOCALAPPDATA%` on
Windows, `~/.local/share` on Linux, whichever Foundation's `applicationSupportDirectory`
resolves to); an error saving shows in red at the bottom of the window. Settings is the gear
in the toolbar; "Open at login" reports an error on Windows and Linux (the shim), and on macOS
when not run from an app bundle (upstream's own check). The midday reminder, when due, is
printed on stderr by the shim instead of shown as a notification.
