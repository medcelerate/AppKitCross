// swift-tools-version:6.0
import PackageDescription

// Windows-only modules. On macOS these are NOT declared: Apple's Foundation re-exports
// the real CoreGraphics, and a local module with the same name shadows the overlay and
// breaks CGRect. On Windows, Foundation only provides the geometry types (CGRect etc.),
// so our CoreGraphics module supplies CGContext, CGPath, CGColor, ... over Direct2D.
var targets: [Target] = []
var appKitDependencies: [Target.Dependency] = []
var appKitExclude: [String] = []

#if os(Windows)
// DirectWrite and DirectComposition headers are C++-only; they arrive with C++ interop in
// Milestone 2/4. Milestone 1 needs only Direct2D, which `WinSDK` exposes as C.
targets += [
    // extern "C" shim over the Direct2D C++ COM interfaces (d2d1.h has no C vtables).
    .target(
        name: "CD2D",
        path: "Sources/CD2D",
        linkerSettings: [.linkedLibrary("d2d1"), .linkedLibrary("dwrite"), .linkedLibrary("windowscodecs"), .linkedLibrary("ole32"), .linkedLibrary("shlwapi"), .linkedLibrary("oleaut32"), .linkedLibrary("shell32"),
                         // Milestone 3: DXGI flip-model swap chain presentation (d3d11 device, dxgi
                         // factory/swap chain, dxguid for the DXGI debug GUIDs).
                         .linkedLibrary("d3d11"), .linkedLibrary("dxgi"), .linkedLibrary("dxguid")]
    ),
    .target(
        name: "CoreGraphics",
        dependencies: ["CD2D"],
        path: "Sources/CoreGraphics",
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
]
appKitDependencies += ["CoreGraphics", "CD2D"]
appKitExclude += ["Platform/Host", "Platform/Linux"]
let quartzCoreDependencies: [Target.Dependency] = ["CoreGraphics"]
#elseif os(Linux)
// Linux: Cairo + PangoCairo for CoreGraphics and text, Xlib for windows (Milestone 8).
targets += [
    .systemLibrary(name: "CCairo", path: "Sources/CCairo", pkgConfig: "pangocairo",
                   providers: [.apt(["libcairo2-dev", "libpango1.0-dev", "libx11-dev"])]),
    .systemLibrary(name: "CX11", path: "Sources/CX11", pkgConfig: "x11", providers: [.apt(["libx11-dev"])]),
    .target(
        name: "CoreGraphics",
        dependencies: ["CCairo"],
        path: "Sources/CoreGraphics",
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
]
appKitDependencies += ["CoreGraphics", "CCairo", "CX11"]
appKitExclude += ["Platform/Win32"]
let quartzCoreDependencies: [Target.Dependency] = ["CoreGraphics"]
#else
appKitExclude += ["Platform/Win32", "Platform/Linux"]
let quartzCoreDependencies: [Target.Dependency] = []
#endif

// QuartzCore is ours on every platform: the CALayer tree, animations and the software
// compositor are pure Swift over CGContext, so the macOS test run exercises them too
// (the module shadows Apple's QuartzCore inside this package only).
targets += [
    .target(
        name: "QuartzCore",
        dependencies: quartzCoreDependencies,
        path: "Sources/QuartzCore",
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
]
appKitDependencies += ["QuartzCore"]

targets += [
    .target(
        name: "AppKit",
        dependencies: appKitDependencies,
        path: "Sources/AppKit",
        exclude: appKitExclude,
        swiftSettings: [
            .swiftLanguageMode(.v5),
            .enableUpcomingFeature("StrictConcurrency"),
        ]
    ),
    .executableTarget(
        name: "HelloWindow",
        dependencies: ["AppKit"],
        path: "Examples/HelloWindow"
    ),
    .testTarget(
        name: "AppKitTests",
        dependencies: ["AppKit"],
        path: "Tests/AppKitTests"
    ),
]

let package = Package(
    name: "AppKitWin",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AppKit", targets: ["AppKit"]),
    ],
    targets: targets,
    cxxLanguageStandard: .cxx17
)
