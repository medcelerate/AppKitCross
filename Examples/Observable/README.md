# Observable

SwiftUI views driven by a model object that changes on its own, same source on every platform.

What it demonstrates:

- An `ObservableObject` model with `@Published` properties, held by the root view as a
  `@StateObject`. The port has no Observation framework (`@Observable` macro and
  `Observation` module are not in swift-corelibs-foundation or this package), so the
  Combine-based pattern is the one to use; it is what Apple's SwiftUI used before macOS 14.
- A `Timer.publish(every:on:in:).autoconnect()` Combine publisher whose `sink` advances the
  model once a second (the port's Combine is a port of OpenCombine; macOS uses Apple's).
- A `List` with a selection binding whose rows update live as the model ticks.
- A detail pane editing the selected vehicle through a `Binding` into the model's array
  (`TextField`, `Slider`, `Toggle`), so edits show in the list at once.
- `Toggle`, `Button` and `.disabled` driven by the model; a pause toggle stops the ticks.

Run it:

```bash
swift run Observable
```
