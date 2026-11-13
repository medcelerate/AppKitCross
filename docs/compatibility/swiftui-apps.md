# Third-party SwiftUI apps on AppKitCross

Whole apps, as opposed to the libraries in [swiftui-libraries.md](swiftui-libraries.md):
a real open-source SwiftUI macOS app vendored under `Examples/` unmodified and built against
the port, as the end-to-end measure of where the port stands. Each entry lists what the app
uses, what broke, what was fixed in the port for it and what is left.

## Daily To Do (`Examples/DailyTodo`, 2026-11-12)

[Noreen21/daily-todo](https://github.com/Noreen21/daily-todo), MIT, 1,075 lines of Swift,
vendored at commit `213775aa` (2026-11-06). Chosen because it is a plain SwiftPM package with
no third-party dependencies, pure SwiftUI (no SwiftData, Core Data, SpriteKit or WebKit), and
exercises the everyday surface: a `NavigationStack` with a toolbar, a date field, a text field,
a list of checkbox rows, an empty-state view, a settings sheet with a grouped form, pickers,
read-only rows, `environmentObject`, JSON file persistence, a timer, plus two Apple frameworks
the port lacks (`UserNotifications`, `ServiceManagement`). Alternatives looked at and why not:
Infinity Notes (SwiftData models and `@Query`, which need the macro and a persistence layer
the port has no counterpart for), TomatoBar (a menu-bar-only app over Carbon hot keys and
`LaunchAtLogin`), Pomosh (Xcode project with HotKey, IOKit and WebKit), CmdMD (31,000 lines).

Status: builds on the macOS host build against the port's SwiftUI and the real
UserNotifications/ServiceManagement; builds on Windows and Linux against the shims (CI); the
app's own self-checks (`DailyTodoChecks`) build on every CI job and run on the macOS and Linux
jobs (on Windows the PC runs them: they assert POSIX file permissions, which corelibs may
report differently there). Its two screens, rebuilt from
the same views in `Tests/AppKitTests/SwiftUIRealAppTests.swift`, host and work on the headless
backend (the empty state comes and goes with the rows, the toolbar button opens the settings
sheet, the grouped form shows the time picker, the pop-up and the read-only rows, the toggle
drives the model and the read-only row follows, Done dismisses). The Windows PC run is
recorded in the pull request.

### Gaps found

| Symptom | Root cause | Owner in `Sources/` | Status |
| --- | --- | --- | --- |
| `cannot find 'ContentUnavailableView' in scope` (ContentView.swift:73) | The view did not exist. | `SwiftUI/Forms.swift` | Fixed in this PR: `ContentUnavailableView` with the label/description/actions, title+image/systemImage inits, `.search` and `.search(text:)`; icon above a bold title, secondary description, centred. |
| `cannot find 'LabeledContent' in scope` (SettingsView.swift:50, 54, 58) | The view did not exist. | `SwiftUI/Forms.swift` | Fixed in this PR: `LabeledContent` (view-builder, title, title+value, title+value+format inits), `LabeledContentStyle`, `AutomaticLabeledContentStyle`, `labeledContentStyle(_:)`; label leading, value trailing in the secondary colour. |
| `value of type 'Form<Content>' has no member 'formStyle'`, `.grouped` (SettingsView.swift:85) | `FormStyle` did not exist. | `SwiftUI/Forms.swift`, `SwiftUI/Views.swift` (`Form`) | Fixed in this PR: `FormStyle`, `AutomaticFormStyle`, `ColumnsFormStyle`, `GroupedFormStyle`, `formStyle(_:)`; the grouped style boxes the rows on a control-background panel. |
| Opening Settings trapped: `No ObservableObject of type AppStore found` | `.sheet` (and `.popover`) hosted their content in a fresh `NSHostingView` with a fresh environment, so the presenter's environment objects, fonts and tints were lost; Apple's presentations inherit the presenting view's environment. | `SwiftUI/Navigation.swift` (`_presented`) | Fixed in this PR: presented content starts from the presenting node's environment, keeping only the new host's window-derived values (appearance, scale, activity, direction, locale). |
| `cannot find type 'ObservableObject' in scope` on Windows and Linux (ReminderScheduler.swift:7, a file that imports AppKit and Foundation but not SwiftUI or Combine) | On macOS `import Foundation` (hence `import AppKit`) brings Combine's `ObservableObject` and `@Published` into scope through the overlay, and apps rely on it; corelibs' Foundation has no Combine and the port's AppKit did not re-export the port's Combine. | `AppKit/Support/Exports.swift`, `Package.swift` | Fixed in this PR: AppKit depends on and re-exports the port's `Combine` where there is no Objective-C runtime (CI found it: the macOS host build cannot). |
| `instance method 'lock' is unavailable from asynchronous contexts` in the UserNotifications shim on Windows and Linux | Corelibs' toolchains reject `NSLock.lock()` inside an `async` function; Apple's is lenient. | `Examples/DailyTodo/Shims` | Fixed in this PR: the shim's async methods take the lock through a synchronous helper (a pattern for the port's own code too: no `NSLock` calls in async functions). |
| `@objc` on the `UNUserNotificationCenterDelegate` method does not compile off Darwin (ReminderScheduler.swift:95) | `@objc` needs the Objective-C runtime. | — (language) | Upstream patch in the vendored copy: `#if canImport(ObjectiveC)` around the attribute, the only source change. |
| `no such module 'UserNotifications'` on Windows and Linux | The port has no UserNotifications. | — (new module) | Shim in `Examples/DailyTodo/Shims/UserNotifications`: the API the app uses; `add` asks the delegate and prints the title and body on stderr. Follow-up: a real `UserNotifications` module over Windows toasts (`Shell_NotifyIcon` balloons or WinRT `ToastNotificationManager`) and `org.freedesktop.Notifications` over D-Bus on Linux, with `NSUserNotificationCenter` on the same seam. |
| `no such module 'ServiceManagement'` on Windows and Linux | The port has no ServiceManagement. | — (new module) | Shim in `Examples/DailyTodo/Shims/ServiceManagement`: `SMAppService.mainApp` reports `.notFound` and `register()` throws. Follow-up: the `Run` registry key / Startup folder on Windows, an XDG autostart entry on Linux. |
| Swift 6 language-mode errors in upstream's `DailyTodoChecks` (`main actor-isolated var 'failures'`) | The root package's tools version is 6.0, so a target without a language-mode setting builds in Swift 6 mode; upstream is tools 5.9. | `Package.swift` | Build note, not a port gap: the three vendored targets set `.swiftLanguageMode(.v5)`. |
| Toolbar gear, the empty state's check mark and the rows' arrow show no glyph | `Image(systemName:)` has no symbol source: `NSImage(systemSymbolName:accessibilityDescription:)` is `unimplemented()` and the SwiftUI image draws nothing for a symbol name (the `Label` titles still show). | `AppKit/Core/NSImage.swift`, `SwiftUI/Views.swift` (`_ImagePrimitive`) | Follow-up: a small built-in glyph table for the common symbol names (drawn as paths, or from a bundled icon font) with the name as the accessibility label. |
| Unverified off macOS: `TimeZone.localizedName(for:locale:)` and `abbreviation()` in the time-zone pop-up, `Date.formatted(Date.FormatStyle(...))` in the Schedule rows, `FileManager.setAttributes([.posixPermissions:])` on the JSON file | swift-corelibs-foundation / swift-foundation behaviour on Windows, not the port's. | — | PC checklist items in the pull request; the self-checks (`DailyTodoChecks`) assert the file permissions, so their Windows run is a checklist item too. |

Not run: the vendored executable was not launched on the macOS host in the session that made
this PR (the session's sandbox refused to execute the downloaded program), so the host-side
runtime verification is the mirrored screens test above; the Windows run is the PC checklist.
