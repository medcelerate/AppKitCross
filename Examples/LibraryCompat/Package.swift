// swift-tools-version:6.0
// LibraryCompat: a compatibility example that builds popular third-party SwiftUI packages
// against AppKitWin's SwiftUI and reports how well they work (docs/compatibility/
// swiftui-libraries.md). It is a package of its own so the core package stays
// dependency-free.
//
// Build with tools/library-compat.sh: the third-party packages do not declare a dependency
// on AppKitWin, so its modules must already be in the build's Modules directory when they
// compile, which takes two steps (`swift build --target SwiftUI`, then `swift build`), and
// on macOS a deployment-target override.
//
// Every library is declared as a dependency so `tools/library-compat.sh --probe` can build
// each one on its own; only the ones that compile on a platform are linked into the app
// (`linked` below), the rest are documented in the report.
import PackageDescription

// A probe leaves a partial module behind for a library that failed, so `canImport` is not
// enough: each linked library also defines HAS_<NAME> for the source.
var linked: [Target.Dependency] = [
    .product(name: "AppKit", package: "AppKitWin"),
    .product(name: "SwiftUI", package: "AppKitWin"),
    // Build on macOS (the host build against this SwiftUI), Windows and Linux.
    .product(name: "Shimmer", package: "SwiftUI-Shimmer"),
    .product(name: "ConfettiSwiftUI", package: "ConfettiSwiftUI"),
]
var defines: [SwiftSetting] = [.define("HAS_SHIMMER"), .define("HAS_CONFETTI")]
#if os(macOS)
linked += [
    // `#if os(macOS)` … `#else` UIKit: these two treat every other platform as UIKit, so
    // they compile only on the macOS host build.
    .product(name: "WrappingHStack", package: "WrappingHStack"),
    .product(name: "Defaults", package: "Defaults"),
    // One `#if os(…)` switch with no default (Color.systemsBackground) keeps it off Windows
    // and Linux; its `import CoreGraphics.CGGeometry` resolves there through the port's map.
    .product(name: "SwiftUICharts", package: "SwiftUICharts"),
    // Its NetworkImage dependency extends URLSession in a file that imports only Foundation,
    // which on corelibs is FoundationNetworking's.
    .product(name: "MarkdownUI", package: "swift-markdown-ui"),
]
defines += [.define("HAS_WRAPPINGHSTACK"), .define("HAS_DEFAULTS"), .define("HAS_CHARTS"), .define("HAS_MARKDOWNUI")]
#else
linked += [
    // The modules Apple's AppKit re-exports and the libraries import by name.
    .product(name: "ImageIO", package: "AppKitWin"),
    .product(name: "UniformTypeIdentifiers", package: "AppKitWin"),
    .product(name: "Combine", package: "AppKitWin"),
]
#endif
// Not linked anywhere (see the report):
//   SwiftUIIntrospect: `import ObjectiveC`, MapKit/WebKit/AVKit view types, and it reaches
//     into AppKit's private hierarchy (the macOS SDK's MapKit crashes the compiler there);
//   Nuke / NukeUI: `#if !os(macOS) import UIKit`, Core Image, the ImageIO C API.

let package = Package(
    name: "LibraryCompat",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "AppKitWin", path: "../.."),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", exact: "2.4.1"),
        .package(url: "https://github.com/siteline/swiftui-introspect", exact: "27.1.0"),
        .package(url: "https://github.com/simibac/ConfettiSwiftUI", exact: "3.0.0"),
        .package(url: "https://github.com/markiv/SwiftUI-Shimmer", exact: "1.5.1"),
        .package(url: "https://github.com/dkk/WrappingHStack", exact: "2.2.11"),
        .package(url: "https://github.com/willdale/SwiftUICharts", exact: "2.10.4"),
        .package(url: "https://github.com/sindresorhus/Defaults", exact: "9.0.9"),
        .package(url: "https://github.com/kean/Nuke", exact: "13.2.1"),
    ],
    targets: [
        .executableTarget(name: "LibraryCompat", dependencies: linked, path: "Sources/LibraryCompat", swiftSettings: defines),
    ]
)
