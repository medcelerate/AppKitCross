# ADR-0045: The app bundle on Windows and Linux

Date: 2026-11-18. Status: accepted.

## Context

A Mac app finds its resources, strings, identity and icon through `Bundle.main`. It reads
images with `NSImage(named:)` and strings with `NSLocalizedString` and `String(localized:)`. It
gets its name and version from the Info.plist. The icon comes from `CFBundleIconFile` or the
asset catalog, and LaunchServices learns its document types and URL schemes from the bundle and
sends later opens to the running instance. A Windows or Linux build made by SwiftPM has none of
this: an executable, SwiftPM's `<Package>_<Target>.resources` folders beside it, and whatever the
developer copies next to it.

swift-corelibs-foundation 6.2 already gives part of it. Checked in the Linux container and in
its source:

- `Bundle.main` is the executable's folder, as a "flat" bundle. An `Info.plist` and resources
  directly in that folder are found. A `Resources/` folder, a sibling `<exe>.resources` and the
  FHS `share/<exe>.resources` are not used for the main bundle.
- The user-language list behind every localization lookup is hard-wired to English off Darwin
  (`_CFBundleCopyUserLanguages`, with the comment "could perhaps read out of LANG"). The only
  input is `-AppleLanguages`, read from argv on Darwin only, into a symbol that is not
  exported. `Bundle.localizedString` and `NSLocalizedString` therefore always answer in the
  development language, and `Locale.preferredLanguages` is `["en-001"]` whatever `LANG` says.
- Any key that has a `.stringsdict` entry crashes `Bundle.localizedString`. The CF result is a
  dictionary that the Swift bridge reads as a string.
- `developmentLocalization` traps when the Info.plist has no `CFBundleDevelopmentRegion`.
- `String(localized:)`, `String.LocalizationValue` and `LocalizedStringResource` do not exist.

## Decision

### The layout

An app is a folder. The port reads what `swift build` produces and what the app-folder layout
tool (ADR-0046) copies; nothing has to be flattened:

```
MyApp/
  MyApp.exe | MyApp
  Info.plist                 or Resources/Info.plist, or in the executable's SwiftPM bundle
  Resources/                 optional: what Contents/Resources holds on macOS
  MyPkg_MyApp.resources/     SwiftPM's bundle of each target (Bundle.module finds them here)
  runtime libraries
```

`_BundleLayout` (Support/AppBundle.swift) searches the main bundle's resources in this order:
`Resources/`, the executable target's own SwiftPM bundle (its `Resources/` subfolder first, for a
`.copy("Resources")`), then the executable's folder. The executable target's bundle is the one
named `*_<executable>.resources`. Including it means `Bundle.main.url(forResource:)`,
`NSImage(named:)` and `NSLocalizedString` find the files SwiftPM copied, both under `swift run`
and in a shipped folder.

The Info.plist is found in this order: the file `APPKITWIN_INFO_PLIST` names (kept from
ADR-0017), then `Info.plist` or `<exe>-Info.plist` in each root. The second name exists because
SwiftPM refuses a resource called `Info.plist`. A bare executable gets `CFBundleExecutable`,
`CFBundleName` and `CFBundleDevelopmentRegion` (`en`) filled in. It gets no made-up
`CFBundleIdentifier`, as on macOS. The platform identity is `CFBundleIdentifier`, else
`AppKitCross.<exe>`, the AUMID UserNotifications already uses. The Wayland app id, the X11
`WM_CLASS`, the desktop entry, the ProgIDs and the single-instance channel are all keyed by it.

### Routing corelibs' Bundle

Apps call these members on corelibs' Bundle object, so the fix must reach that object. Two
approaches fail:

- A subclass cannot be written. Bundle's vtable names implementation-only CoreFoundation types,
  so the compiler refuses: "cannot inherit from class 'Bundle' because it has overridable
  members that could not be loaded".
- A second `NSLocalizedString`, or a `Bundle` extension member in AppKit, is ambiguous rather
  than shadowing (checked with Swift 6.2).

So the port replaces implementations in Bundle's own vtable (Support/BundleHooks.swift). For
each of 13 members it:

1. Looks up corelibs' implementation by its mangled name (`dlsym`, or `GetProcAddress` on
   Foundation.dll).
2. Finds the single slot of Bundle's class metadata that holds that address.
3. Keeps the original and stores a trampoline from `Sources/CBundleHooks` in the slot.

The members are `localizedString(forKey:value:table:)`, `preferredLocalizations`,
`localizations`, `developmentLocalization`, `infoDictionary`, `bundleIdentifier`,
`object(forInfoDictionaryKey:)`, `resourceURL`, `resourcePath`, the two
`url(forResource:withExtension:…)` and the two `path(forResource:ofType:…)`.

The trampolines are C functions declared with clang's `swiftcall` convention that take the
receiver as their `swift_context` parameter (LLVM's swiftself, the register a Swift method gets
`self` in). They forward to C-ABI dispatchers set from Swift. Values cross as the words the Swift
convention passes them in, and ownership is moved explicitly: borrowed arguments are copied,
results are handed over at +1.

The safeguards:

- Nothing is installed unless every slot is found exactly once.
- After installing, a call through the vtable must reach the port (a self-test), else the
  originals are put back and the reason is printed once on stderr.
- `APPKITWIN_CORELIBS_BUNDLE=1` turns the hooks off.
- The hooks are installed when the first `NSApplication` is made, and before the port's own
  lookups. Code that runs before then gets corelibs' answers.

Localization members answer for every bundle, module bundles included. Resource and Info.plist
members answer for the main bundle and call corelibs' original for any other bundle.

This was checked on arm64 and x86-64 Linux, debug and release, including 200,000 calls through
the hooks, before it was adopted. Windows uses the same swiftcall lowering on both sides (Swift's
IRGen uses clang's), and the PC run verifies it. The proper fix belongs in corelibs: read
`LANG`, export the language override and fix the stringsdict bridge. When those land, the hooks
can go.

### Localization

Support/Localization.swift is the engine:

- **Languages.** `-AppleLanguages "(de, en)"` on the command line wins, as on macOS. Otherwise
  the user's UI languages on Windows (`GetUserPreferredUILanguages`), or gettext's order on
  Linux: `LANGUAGE` (unless the locale is C), then `LC_ALL`, `LC_MESSAGES`, `LANG`, with POSIX
  names turned into BCP 47 (`sr_RS@latin` becomes `sr-Latn-RS`).
- **Matching.** A preference matches a bundle's localization exactly, then with the region or
  script dropped, then by a regional variant of its language. Otherwise the development
  localization, then Base. Lookups fall back from the preferred localization to the development
  one, then to Base, key by key.
- **Tables.** `.strings` files are parsed by the port (comments, escapes, unquoted words, the
  `"key";` form, UTF-8 or UTF-16 with a BOM, binary and XML plists). `.stringsdict` entries
  apply CLDR cardinal rules: `zero` wins for 0 when the rule has it, and every conversion gets
  an explicit position, so a variant without a number ("one file") does not shift later
  arguments. Uncompiled String Catalogs (`<table>.xcstrings`, which SwiftPM copies off macOS)
  are read too: string units, plural variations, and the source language's keys as their own
  values.
- **`Bundle.localizedString`.** It has no arguments, so a stringsdict entry answers with its
  `other` forms and explicit positions (`%1$lld Dateien`). `String.localizedStringWithFormat`
  of that is right for plural-other counts. For an exact plural, use `String(localized:)` or
  SwiftUI's `Text`, which carry the values.

On Windows and Linux, AppKit declares `String.LocalizationValue` (Apple's key format: `%@`,
`%lld`, `%lf` and the others), `String(localized:…)` and `LocalizedStringResource`. They are
visible through `import AppKit`, `Cocoa` or `SwiftUI`. A file that imports only Foundation does
not see them, which is a known gap. SwiftUI's `LocalizedStringKey` builds the same keys, and
`Text` looks its key up in the bundle and table it is given. `InfoPlist.strings` localizes
`object(forInfoDictionaryKey:)` and the display name.

### Resources, asset catalogs, nibs

- `NSImage(named:)` and `Bundle.image(forResource:)` look up files with any image extension
  (with their `@2x`/`@3x` siblings as further representations), then asset catalogs.
- Catalogs are read uncompiled (Support/AssetCatalog.swift). Image sets give one representation
  per scale, and the template rendering intent is honoured. App icon sets give one
  representation per size. Data sets back `NSDataAsset`, now hand-written. Colour sets
  (ADR-0038) share the lookup. Folders that provide a namespace are honoured. Dark-appearance
  and non-Mac idiom variants are skipped.
- The catalog search goes at most two folders below each root, because the executable's folder
  under `swift build` holds thousands of build products.
- `NSSound(named:)` searches the same roots.
- `NSNib(nibNamed:bundle:)` is now hand-written. It finds `<name>.nib` or `.xib` and answers nil
  when there is none. Instantiating a nib stays unimplemented, because interfaces are built in
  code (ARCHITECTURE).

### Identity and icon

- `NSApplication`, `NSDocumentController`, SwiftUI's `App` name and the About panel read
  `_AppBundle`. The About panel shows "Version 1.2 (34)" (the build is left out when it equals
  the version), the credits, `NSHumanReadableCopyright` and the icon.
- `applicationIconImage` returns the image set on it, else the Info.plist's icon, else the
  executable's icon as the shell shows it. Setting nil goes back to the default.
- The Info.plist icon comes from `CFBundleIconName` (an app icon set) or `CFBundleIconFile` (a
  PNG or ICO of that name; `.icns` is not read). It reaches the windows at launch through the
  dock tile path of ADR-0026: `WM_SETICON` on Win32 (title bar, taskbar, Alt-Tab) and
  `_NET_WM_ICON` on X11.
- Wayland has no window-icon protocol in common use, so the compositor takes the icon from the
  desktop entry whose id is the window's app id. The app id is now the identity instead of the
  constant "AppKitCross".
- X11 windows now set `WM_CLASS`: the executable's name, and the identity as the class, which
  matches the desktop entry's `StartupWMClass`.

### Opening documents and URLs

At launch, every application now gets the documents and URLs on its command line, not only
document-based ones:

- `-Key value` pairs (the argument domain) and `--switches` are skipped.
- `file:` URLs become paths.
- URLs of the schemes the Info.plist declares (or with `://`) go to `application(_:open:)`.
- Files go to the document controller if the app has one. Otherwise they go to
  `application(_:openFiles:)` or `application(_:openFile:)`, then to `application(_:open:)`
  when `openFile` declines.

### Single instance

An application with a `CFBundleIdentifier` claims a per-user channel when its first
`NSApplication` is made:

- On Windows, a named pipe created with `FILE_FLAG_FIRST_PIPE_INSTANCE`. The sender calls
  `AllowSetForegroundWindow` on the server's process.
- On Linux, a Unix socket in `$XDG_RUNTIME_DIR`. A socket file left behind by a dead process is
  replaced.

A later launch sends its arguments and working directory, gets a one-byte acknowledgement and
exits. The running instance opens what it received as launch items. With nothing to open, it
asks `applicationShouldHandleReopen`, then brings back a minimised window or opens an untitled
document, and comes to the front. Messages that arrive during launch wait for
`applicationDidFinishLaunching`. Two launches at once (a multi-file open from Explorer) are
resolved by whichever creates the pipe or binds the socket first.

The hand-off is off on the host backend. It can also be turned off with
`AppKitCrossAllowsMultipleInstances` in the Info.plist or `APPKITWIN_MULTIPLE_INSTANCES=1`.

### File associations

LaunchServices has no counterpart, so registration happens only when asked: `MyApp
--appkitcross-register` or `--appkitcross-unregister` (prints what it did and exits, for
installers and the layout tool), `NSWorkspace._registerApplication()` (port only), or the
Info.plist key `AppKitCrossRegistersFileTypes` (registers at launch when the registration is
missing or names another executable). It never runs at an ordinary launch otherwise.

`_AppRegistration` computes the plan from `CFBundleDocumentTypes` (through `LSItemContentTypes`,
the Info.plist's UTI declarations and UTType's tables), `CFBundleURLTypes` and
`LSApplicationCategoryType`. The plan is tested on every platform.

On Windows, everything goes under HKCU, so no elevation is needed:

- A ProgID per type, with `shell\open\command` set to `"exe" "%1"` and `DefaultIcon` set to
  `"…\AppIcon.ico",0`. Paths are written with backslashes: Foundation's paths on Windows use
  forward slashes, which `AssocQueryString` and ShellExecute reject (found on the PC).
- The type's extensions' `OpenWithProgids`. The app is offered, never made the default: the
  extension's default and `Content Type` are the user's and the system's, and Windows 10 and
  later leave the choice to the user anyway.
- `Applications\<exe>` with `SupportedTypes`.
- A Capabilities key listed under `RegisteredApplications`, for Settings > Default apps.
- URL scheme keys, unless another executable owns the scheme.
- Then `SHCNE_ASSOCCHANGED`.

Unregistering removes the ProgIDs, `Applications\<exe>`, the Capabilities key and its
`RegisteredApplications` value, the `OpenWithProgids` entries, and the extension keys they leave
empty. `NSWorkspace.setDefaultApplication(at:toOpen:)` for the running app registers it and
opens Settings on its Default apps page, then throws `unsupported` with that explanation.
`PlatformWorkspaceError` is a `LocalizedError`, so an alert shows the sentence.

On Linux:

- `~/.local/share/applications/<identity>.desktop`, with `MimeType`, `Exec … %F`/`%U`,
  `StartupWMClass` and the icon written as a PNG into the hicolor theme.
- A shared-mime-info package for extensions no MIME type covers, and for declared UTIs.
- Then `update-mime-database` and `update-desktop-database`, and `xdg-mime default` for Owner
  types that have no default yet.

Recent documents in the Windows jump list are not done.

## Consequences

- A Mac app's resource, localization and identity code runs unchanged once the app has started.
  Before the first `NSApplication`, corelibs answers. In practice that is only code in
  `main.swift` ahead of `NSApplication.shared`, or a command-line tool without AppKit.
- The hooks depend on corelibs' mangled names and on Bundle's class layout staying ordinary
  Swift metadata. A Foundation that changes either loses the hooks with a message rather than
  crashing, because of the unique-slot check and the self-test.
- `Locale.preferredLanguages` and `Bundle.preferredLocalizations(from:)` (a class method, not
  in the vtable) stay corelibs'.
- Tests: `BundleTests` (24 on macOS, 25 on Windows and Linux with the corelibs routing; fixture app folder `Tests/AppKitTests/Fixtures/SampleApp`).
- Examples: HelloWindow carries a localized greeting (en, de) and a resource image in its
  SwiftPM bundle. MDVault has an icon, the `.md` association and the single instance.
