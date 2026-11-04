# Calculator

A SwiftUI `App` with a `WindowGroup`, built with the same source on macOS, Windows and Linux.

What it demonstrates:

- `@main` on an `App` with a `WindowGroup` scene; `.windowResizability(.contentSize)` keeps
  the window at the content's fixed size.
- A grid of `Button`s laid out with `VStack`/`HStack` (`ForEach` over rows).
- Keyboard input through `.keyboardShortcut(_:modifiers: [])`: the digit keys, `+ - * /`,
  `.`, `%`, Return (`=`), Backspace and Escape (`C`) press the matching buttons.
- The standard application menu bar from the `App` runner, extended with a `CommandMenu`
  ("Calculator" with Clear ⌘K and Copy Result ⇧⌘C). `NSPasteboard` copies the result.
- An `ObservableObject` model with `@Published` properties driving the display.

Run it:

```bash
swift run Calculator
```
