# MD Vault

A fast, native Markdown app for macOS with two views — one keystroke apart.

**Viewer** renders your document: styled headings, nested lists, task checkboxes,
tables, code blocks, quotes, images, clickable links.
**Editor** shows the raw source — every `##`, `**` and backtick stays visible —
syntax-highlighted so the structure still reads at a glance.

Press **⌘E** to flip between them.

| Viewer | Editor |
|:------:|:------:|
| ![The viewer, showing rendered Markdown](docs/viewer.png) | ![The editor, showing highlighted raw source](docs/editor.png) |

*The same document, the same scroll position — ⌘E apart.*

## Why

Most Markdown apps either hide the syntax from you or never show you the result.
MD Vault does both, properly, in a 1.7 MB app that opens instantly.

- **Local only.** No account, no sync, no cloud, no telemetry, no update checks.
  Your files never leave your Mac.
- **No dependencies.** The Markdown parser is written from scratch. The whole app
  links nothing but AppKit, SwiftUI and Foundation.
- **A real document app.** Open Recent, multiple windows, autosave-free explicit
  ⌘S, unsaved-changes warnings and Finder integration all come from the system,
  because it's a proper `NSDocument`-backed app rather than a web view in a wrapper.

## Install

### From source — recommended

Builds in a couple of seconds and avoids Gatekeeper entirely, because software you
compile yourself is never quarantined.

```sh
git clone https://github.com/AadeshTaneja/md-vault.git
cd md-vault
./build.sh --install
```

Requires the Xcode Command Line Tools (`xcode-select --install`). Nothing else.

### From a release

Download the `.dmg` from [Releases](https://github.com/AadeshTaneja/md-vault/releases),
open it, drag **MD Vault** to Applications.

These builds are signed ad-hoc but **not notarized**, so macOS will warn you on
first launch. Either right-click the app and choose **Open**, or clear the flag:

```sh
xattr -dr com.apple.quarantine "/Applications/MD Vault.app"
```

## Make it your default Markdown app

Open any file, then **File ▸ Set MD Vault as Default for Markdown…**

To undo: select a `.md` file in Finder, press ⌘I, change *Open with*, click *Change All*.

## Shortcuts

| Shortcut | Action |
|:---------|:-------|
| ⌘E | Toggle Editor / Viewer |
| ⌘1 / ⌘2 | Go straight to Editor / Viewer |
| ⌘S | Save |
| ⌘+ / ⌘- / ⌘0 | Bigger / smaller / default text size |
| ⌘F | Find (in the editor) |
| ⌘O / ⌘N / ⌘W | Open / new / close, plus File ▸ Open Recent |

## Markdown supported

Headings (ATX and setext), bold / italic / bold-italic, inline code, strikethrough,
links, autolinks, images, blockquotes, nested ordered and unordered lists, task
lists, tight and loose lists, fenced and indented code blocks, tables with column
alignment, thematic breaks, hard line breaks and backslash escapes. YAML front
matter is hidden in the viewer.

Local image paths resolve relative to the document. Images with `http(s)` URLs are
fetched when you open a file that references one — the only time the app touches
the network.

## Build

```sh
./build.sh              # build into ./build
./build.sh --install    # build, then install to /Applications
./scripts/make-dmg.sh   # package the built app as a .dmg
```

There is no Xcode project and no package manager. `build.sh` compiles the sources
with `swiftc`, draws the icon, assembles the bundle, signs it ad-hoc and registers
it with Launch Services.

Tagging a version (`git tag v1.0.0 && git push origin v1.0.0`) builds a DMG and a
zip on GitHub Actions and attaches them to a release.

## Layout

```
Sources/
  MDVaultApp.swift        app entry, menu commands, default-app helper
  ContentView.swift       two-view shell, toolbar, status bar
  MarkdownDocument.swift  FileDocument — open/save/recents come free
  EditorView.swift        NSTextView-backed raw editor
  SyntaxHighlighter.swift regex highlighting for the editor
  Theme.swift             font and sizing rules
  Markdown/
    Inline.swift          inline scanner: emphasis, links, code spans
    InlineRenderer.swift  inline model to AttributedString
    Blocks.swift          block parser: lists, tables, quotes, fences
    MarkdownView.swift    SwiftUI renderer for the viewer
Resources/Info.plist      bundle and .md document-type declarations
Tools/MakeIcon.swift      draws the app icon at build time
scripts/make-dmg.sh       packages a release DMG
sample.md                 exercises every supported feature
```

## License

MIT — see [LICENSE](LICENSE).
