# Animation

Core Animation and SwiftUI animation in one AppKit window, same source on every platform.

What it demonstrates:

- A layer-backed `NSView` hosting a `CALayer` scene (`wantsLayer`, sublayers, `CAShapeLayer`,
  `CATextLayer`).
- Explicit animations: `CABasicAnimation` on `position.x` (autoreversing), on `opacity` and
  `transform.scale` inside a `CAAnimationGroup`, and on `transform.rotation.y` for a 3D flip
  under a perspective `sublayerTransform` (`m34`). The flip is rendered in real 3D by the
  DirectComposition path on Windows; software backends show the affine approximation.
- `CAKeyframeAnimation` with a `path` (`calculationMode = .paced`) moving a dot along a
  dashed figure-eight track.
- Implicit animations: "Jump" changes `backgroundColor`, `cornerRadius` and `position`
  inside a `CATransaction` with `setAnimationDuration`.
- Play/pause/reset with public timing API: pause copies each layer's `presentation()` values
  into the model and removes the animations; play adds them again with `timeOffset` set to
  the elapsed time so they resume where they stopped.
- A SwiftUI pane in an `NSHostingView`: `withAnimation(.spring())` moves, rotates and
  scales a square; `.animation(_:value:)` with `repeatForever` pulses a circle.

Run it:

```bash
swift run Animation
swift run Animation --paused   # starts paused
```

Space plays or pauses, ⌘J jumps, ⌘R resets.
