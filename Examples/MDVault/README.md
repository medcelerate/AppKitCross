# MDVault

The second real third-party SwiftUI macOS app built against AppKitCross, and the first
document-based one: [MD Vault](https://github.com/AadeshTaneja/md-vault) (MIT, `Sources/`
vendored from upstream commit `eff8e40d7539ca2cc8545511a6c82994ee59ff42`, 2026-09-27; its README
is kept as [UPSTREAM-README.md](UPSTREAM-README.md), its license as [LICENSE](LICENSE)). The
point is not the app but what it finds: every build or runtime gap it ran into is in
[docs/compatibility/swiftui-apps.md](../../docs/compatibility/swiftui-apps.md), with what was
fixed in the port for it and what is a follow-up.

What the app uses: a `DocumentGroup` over a `FileDocument` (Markdown and plain text, read as
UTF-8 with a Latin-1 fallback, written as UTF-8), an `NSViewRepresentable` around
`NSTextView.scrollableTextView()` as the editor (undo, the find bar, no smart substitutions,
a regex syntax highlighter restyling the text storage on every change), a Markdown viewer
written in SwiftUI from its own parser (`Text` of `AttributedString` runs built from
`NSFont`s, a `Grid` for tables, `AsyncImage` and `NSImage(contentsOf:)` for images, nested
lists, block quotes, horizontally scrolling code blocks, `textSelection`), a segmented
`Picker` in the toolbar's principal slot switching editor and viewer, a status bar on
`.bar`, `@AppStorage` for font sizes and the last mode, `Commands` with `@FocusedValue` reading a
`focusedSceneValue` binding (View > Toggle Editor / Viewer, ⌘E, ⌘1, ⌘2, Bigger / Smaller /
Actual Size), `NSWorkspace.setDefaultApplication(at:toOpen:)` and `NSAlert` (File > Set MD
Vault as Default for Markdown…), dynamic `NSColor(name:dynamicProvider:)` colours and
`UTType(importedAs:)` for `net.daringfireball.markdown`.

## Layout

| Path | Contents |
| --- | --- |
| `Sources/MDVault` | The app (upstream `Sources/`, unmodified except one `@MainActor` on the editor's coordinator in `EditorView.swift`, marked `AppKitCross:` in the source; see below). |
| `Resources/Info.plist` | Upstream's Info.plist, unmodified: the app name, the Markdown UTI declaration (`UTImportedTypeDeclarations`, with the `md`, `markdown`, ... extensions), the document types and `CFBundleIconFile` = `AppIcon`. The whole folder is the target's SwiftPM resource (`.copy("Resources")`), where the port finds the Info.plist at launch (ADR-0045); `APPKITWIN_INFO_PLIST` still overrides it. |
| `Resources/AppIcon.png`, `Resources/AppIcon.ico` | The icon (the port's: upstream's is an `.icns` made by `Tools/MakeIcon.swift`): the PNG for the windows and the Linux desktop entry, the ICO for the Windows file association's icon. |
| `Resources/sample.md`, `Resources/Welcome.md` | Upstream's sample documents, for trying the viewer. |

The target is declared in the root `Package.swift` (it depends on the `AppKit` and `SwiftUI`
products like the other examples, plus `UniformTypeIdentifiers` off macOS) in Swift 5
language mode, as upstream's `swiftc` build implies. Upstream's `Tools/MakeIcon.swift`,
`build.sh` and release scripts (an app-bundle build with `iconutil`, `codesign` and
`lsregister`) are not vendored.

The one source change: Apple's AppKit is imported from Objective-C, so its main-actor
annotations are implicitly `@preconcurrency` and reading `textView?.textStorage` from the
coordinator (a plain `NSObject` subclass) is not even a warning in Swift 5 mode; the port's
AppKit is Swift, where the same read is an error. Marking the coordinator `@MainActor` is
correct on both. The port-side fix (`@preconcurrency` on the port's main-actor annotations
so Swift 5 clients get Apple's leniency) is a follow-up in the gap table.

## Build and run

```bash
swift build --product MDVault
.build/debug/MDVault Examples/MDVault/Resources/sample.md
```

On Windows (one job at a time, as CI does, see `docs/ci-windows-runner.md`):

```
swift build -c debug -j 1 --product MDVault
.build\debug\MDVault.exe Examples\MDVault\Resources\sample.md
```

The app bundle (ADR-0045): the windows show the icon; a second `MDVault other.md` while one
runs opens the document in the running instance and exits; `MDVault --appkitcross-register`
registers the Markdown and plain-text types for the current user (Explorer's Open With and
Settings > Default apps on Windows, `~/.local/share/applications/com.aadesh.mdvault.desktop`
on Linux) and `--appkitcross-unregister` removes them; File > Set MD Vault as Default for
Markdown registers too, then sets the default on Linux or opens Settings on its page on Windows.

Without `APPKITWIN_INFO_PLIST` the app still runs (the DocumentGroup knows its types), but
it is named after its executable ("MDVault") and, on Windows and Linux, the Markdown type
has no filename extensions: `.md` files do not open and new documents save without an
extension (plain-text `.txt` files work). On macOS the system declares the Markdown type.

With no file argument the app opens an untitled document, as a document-based app does on
macOS. ⌘E (Ctrl+E on Windows and Linux) switches between the raw editor and the formatted
viewer; File > Save asks where to save an untitled document; closing an edited document asks
whether to save it.
