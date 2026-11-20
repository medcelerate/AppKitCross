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
- Measurement memo (2026-11-19, after a Windows run of Sibyl spent about 1.2 s per event-loop
  iteration re-measuring every transcript row whenever a 50 Hz meter changed): each node
  memoises `sizeThatFits` per proposal across passes. The memo of a node and of all its
  ancestors is dropped when the node re-runs or `setNeedsUpdate()` marks it, and through
  `_ViewNode.invalidateMeasurement()` when a backing view changed size on its own (a split
  divider drag). The whole tree drops it when `_ViewRoot.measureGeneration` moves (new
  content, a new root environment, `invalidateAllMeasurements()`); layout passes no longer
  move it. An unforced pass hands kept children of a primitive their own box, so they no
  longer re-run on every pass. Primitives whose size reads backing-view state that changes
  without a re-run (`_MeasuresBackingViewState`: representables, the AppKit table, vertical
  text fields, date pickers) are re-measured, with their ancestors, at the start of each pass.
  Animations interpolate presentation frames only, so they need no re-measurement. A
  scheduled update invalidates the hosting view's intrinsic size only when its
  `sizingOptions` include `.intrinsicContentSize` and it is not its window's content view
  (`NSHostingRootHost.rootDidScheduleUpdate()`).
- Invalidation (2026-11-19, the same Sibyl run: every meter tick and keystroke redrew every
  text and shape in the window): a scheduled update no longer marks the whole hosting view
  for display. Frame changes mark what they move, and a primitive marks its own view when
  its content changes. Primitives whose `didLayout` only invalidates their view
  (`_RedrawsWhenChanged`: text, shapes, decorations, gradients, masks) are told only when
  their rect or primitive changed. A forced pass keeps a `Text` child whose value and
  environment are equal (`_sameLeafValue`, `_equalEnvironment`; a value that is neither
  `Equatable` nor an object counts as changed), so a list whose body re-ran for an appended
  row keeps its other rows' primitives, memos and pixels. `syncBackingViews` inserts new
  backing views next to their neighbours instead of re-adding every sibling. A view's
  baselines (`ViewDimensions`) are found on first read, not for every alignment query (a
  leading-aligned stack around a list laid out every row's text on every pass).
  `NSScrollView.tile()` and `reflectScrolledClipView(_:)` set scroller values, frames and
  visibility only when they differ. `SwiftUIUpdateCostTests` counts it: a meter tick marks
  no text (was 40) and measures no row; an appended row marks only itself (was 41 texts).
- Layer damage (2026-11-20, the Sibyl capture window on Windows marked `_ContainerView` and
  `_SwiftUISplitView` on every 50 Hz meter tick): the hosting view is layer-backed, and any
  sublayer property change (a capsule's `bounds` through the view's frame) told the root's
  host to repaint everything, so every tick repainted the whole window and drew every text.
  A backing-layer change the view makes to follow its own frame, alpha or hidden state no
  longer reaches the host (`CALayer._hostMarksChange`: the view marks old and new frames in
  its superview); a change made to a layer directly (an `offset` effect's transform) repaints
  what the layer's subtree covered before and after (`layerNeedsDisplay(_:inRootBounds:)`),
  and dirty rects under a transformed layer go through the layer tree. The software
  compositor skips a layer's own drawing when the dirty area misses its bounds, the window
  paints each pending dirty area on its own rather than their bounding box (three meters in
  three rows no longer repaint the row labels between them), `_SplitPrimitive` re-arranges
  its split view only when its size or panes changed, and `alphaValue` ignores a value it
  already has. `SwiftUIMeterCascadeTests` measures the scene.
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
