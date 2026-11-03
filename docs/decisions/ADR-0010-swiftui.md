# ADR-0010: SwiftUI on the AppKit hosting seam

Date: 2026-10-30. Status: accepted (first version).

## Context

The project's goal is a SwiftUI stack on Windows and Linux. Every prerequisite is on
main: AppKit with the M6 hosting seam (`NSHostingContent` / `NSHostingRoot`), Core
Animation, Auto Layout, CoreText and the text system, Metal, Combine (ported from
OpenCombine), and the platform backends. On macOS Apple's SwiftUI is a closed
implementation over private AppKit hooks; here the hooks are the public seam.

## Decision

A `SwiftUI` module in the package, built on every platform over the package's AppKit
(it shadows Apple's SwiftUI on macOS exactly as the package's AppKit and QuartzCore
do), so the same implementation runs and is tested on macOS, Windows and Linux.

Shape:

- Public API follows Apple's SwiftUI names and signatures (`View`, `ViewBuilder`,
  `State`, `Binding`, `ObservedObject`, `StateObject`, `Environment`,
  `EnvironmentObject`, `EnvironmentValues`, `Text`, `Button`, `TextField`, `Toggle`,
  `Slider`, `Image`, `Color`, shapes, stacks, `ScrollView`, `List`, `ForEach`, `Group`,
  `AnyView`, `ViewModifier`, the common modifiers, `App`/`Scene`/`WindowGroup`,
  `NSViewRepresentable`, `NSHostingView`/`NSHostingController`). Members that exist
  only to keep source compatible and do nothing yet (animations, accessibility,
  navigation titles) are documented as such in the roadmap, not invented.
- `View` refines AppKit's `NSHostingContent`, so AppKit's `NSHostingView<Content>` and
  `NSHostingController<Content>` are SwiftUI's. `NSViewRepresentable` and
  `NSViewControllerRepresentable` move from the seam into SwiftUI, where they belong.
- Runtime: a tree of `ViewNode`s mirrors the view hierarchy. A node holds its view value,
  persistent storage for dynamic properties, the inherited `EnvironmentValues`, and its
  children. Composite views (those with a `body`) get their dynamic properties installed
  by walking the value with `Mirror` (each wrapper holds a reference box, so linking the
  box to the node's storage needs no write-back), then `body` is evaluated and
  reconciled against the previous child by type and position (by `id` under `ForEach`).
  Primitive views (`Body == Never`) provide a `_Primitive` object that measures, places,
  and owns an AppKit backing view where one is needed.
- Rendering maps to AppKit: `Text` and shapes draw themselves in small `NSView`
  subclasses through CoreText and CoreGraphics; `Button`, `TextField`, `Toggle`,
  `Slider`, `Image` and `ScrollView` are `NSButton`, `NSTextField`, `NSSlider`,
  `NSImageView` and `NSScrollView`, so native behaviour, focus and accessibility come
  from AppKit. Decorating modifiers (background, overlay, border, corner radius, clip,
  opacity) wrap their content in a layer-backed `NSView`. Layout containers (stacks,
  padding, frames, spacers) own no view.
- Layout follows SwiftUI's proposal protocol: `sizeThatFits(ProposedViewSize)` and
  placement, with stack distribution by flexibility and layout priority, `Spacer`,
  `frame`, `padding`, `fixedSize`, alignment guides for the standard alignments.
- Invalidation: a `State`/`ObservedObject`/`StateObject` change marks its node and asks
  the host for layout; the next AppKit layout pass re-evaluates dirty bodies top-down,
  reconciles, lays out and resizes backing views. Updates coalesce in AppKit's display
  cycle, so tests drive them with `layoutSubtreeIfNeeded()` or a window display.
- `App` runs `NSApplication`: `WindowGroup` makes an `NSWindow` whose content is an
  `NSHostingView` of the scene's content, sized to the content's ideal size.

## Consequences

- Apps written against SwiftUI's common surface compile and run on Windows and Linux
  with native AppKit-backed controls.
- Animations (second version): `withAnimation`, `.animation(_:value:)`, transitions on
  insertion and removal, animated layout changes of backed views and the animatable
  `opacity`, `offset`, `scaleEffect` and `rotationEffect` modifiers are interpolated by the
  runtime on the host's display link (cubic Bézier curves and damped springs); not a
  transaction per node as Apple does, so overlapping animations on one property retarget
  from the current value rather than blend.
- Navigation (third version): `NavigationStack` keeps its pages in an observable state
  object passed down the environment; `NavigationLink` pushes a destination or a value
  that `navigationDestination(for:)` resolves; a `[T]`/`NavigationPath` binding is kept
  in sync; pages animate with a push transition. `TabView`, `Picker` and alerts read their
  items (`tabItem`, `tag`, `Button`s) by inspecting the view boxes at runtime; the
  segmented and radio-group pickers are built from AppKit buttons (menu style falls back to
  segmented until a popup button exists); sheets are `NSWindow.beginSheet` windows hosting
  the content with `dismiss` in the environment; alerts are `NSAlert`s shown as sheets.
- `GeometryReader` rebuilds its content when its size changes and the root settles the pass;
  `@AppStorage`/`@SceneStorage` read and write `UserDefaults` and re-render on
  `UserDefaults.didChangeNotification`; `@FocusState` with `focused(_:equals:)` drives and
  follows the first-responder state of the text field under the modifier (other focusable
  controls are not tracked yet); `onSubmit` fires on the field's Return.
- Not in this version: gestures beyond tap and hover, `NavigationStack`/`NavigationSplitView`,
  `List` selection and swipe actions, `Table`, `Form` styling, `Picker` menus,
  `Menu`/`commands`, `TabView`, sheets and alerts, `@AppStorage`, `@FocusState`,
  `GeometryReader` (planned next), `Canvas`, `TimelineView`, drag and drop.
- Apple's SwiftUI identity rules are approximated: structural identity by position and
  type, explicit identity by `id(_:)` and `ForEach` ids.
