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
        linkerSettings: [.linkedLibrary("d2d1"), .linkedLibrary("dwrite"), .linkedLibrary("windowscodecs"), .linkedLibrary("ole32"), .linkedLibrary("shlwapi"), .linkedLibrary("oleaut32")]
    ),
    .target(
        name: "CoreGraphics",
        dependencies: ["CD2D"],
        path: "Sources/CoreGraphics",
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    // Placeholder CALayer family until Milestone 4 (DirectComposition).
    .target(
        name: "QuartzCore",
        dependencies: ["CoreGraphics"],
        path: "Sources/QuartzCore",
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
]
appKitDependencies += ["CoreGraphics", "CD2D", "QuartzCore"]
appKitExclude += ["Platform/Host"]
#else
appKitExclude += ["Platform/Win32"]
#endif

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
