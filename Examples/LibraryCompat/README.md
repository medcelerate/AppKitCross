# LibraryCompat

Popular third-party SwiftUI packages built against AppKitWin's `SwiftUI`, one tab each:
SwiftUI-Shimmer, ConfettiSwiftUI, WrappingHStack, Defaults, swift-markdown-ui,
SwiftUI-Introspect, SwiftUICharts and Nuke. The verdicts per platform and the API gaps
they ran into are in [docs/compatibility/swiftui-libraries.md](../../docs/compatibility/swiftui-libraries.md).

It is a package of its own (the core package stays dependency-free), built by the script
at the repository root, which also probes each library on its own:

```bash
tools/library-compat.sh --run        # build, then run
tools/library-compat.sh --probe      # each library alone: "builds" or its first error
Examples/LibraryCompat/.build/debug/LibraryCompat --screenshot shots   # one PNG per tab
APPKITWIN_COMPAT_TAB=confetti Examples/LibraryCompat/.build/debug/LibraryCompat
```

Which libraries are linked on each platform is decided in `Package.swift`; a tab for a
library that does not build on the platform shows the reason instead of the demo.
