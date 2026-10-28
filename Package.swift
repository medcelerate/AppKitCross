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
                         .linkedLibrary("d3d11"), .linkedLibrary("dxgi"), .linkedLibrary("dxguid"),
                         // Milestone 3b: DirectComposition presentation of translucent windows and
                         // the DWM frame/backdrop attributes used by Win32Window.
                         .linkedLibrary("dcomp"), .linkedLibrary("dwmapi")]
    ),
    .target(
        name: "CoreGraphics",
        dependencies: ["CD2D"],
        path: "Sources/CoreGraphics",
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
]
targets += [
    // extern "C" shim over DirectWrite (fonts, shaping, glyph runs) for the CoreText module.
    .target(name: "CDirectWrite", dependencies: ["CD2D"], path: "Sources/CDirectWrite", linkerSettings: [.linkedLibrary("dwrite")]),
    .target(
        name: "CoreText",
        dependencies: ["CoreGraphics", "CD2D", "CDirectWrite"],
        path: "Sources/CoreText",
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
]
// UniformTypeIdentifiers and ImageIO (ADR-0009): UTType over the SDK's core-type table;
// CGImageSource/CGImageDestination over the WIC decode/encode in the CD2D shim.
targets += [
    .target(name: "UniformTypeIdentifiers", path: "Sources/UniformTypeIdentifiers", swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(name: "ImageIO", dependencies: ["CoreGraphics", "CoreText", "CD2D"], path: "Sources/ImageIO", swiftSettings: [.swiftLanguageMode(.v5)]),
]
appKitDependencies += ["CoreGraphics", "CD2D", "CoreText"]
appKitExclude += ["Platform/Linux"]
let quartzCoreDependencies: [Target.Dependency] = ["CoreGraphics"]
let leafModuleProducts: [Product] = [.library(name: "UniformTypeIdentifiers", targets: ["UniformTypeIdentifiers"]), .library(name: "ImageIO", targets: ["ImageIO"])]
let leafModuleTestDependencies: [Target.Dependency] = ["UniformTypeIdentifiers", "ImageIO"]
#elseif os(Linux)
// Linux: Cairo + PangoCairo for CoreGraphics and text, Xlib or Wayland for windows (Milestone 8).
targets += [
    .systemLibrary(name: "CCairo", path: "Sources/CCairo", pkgConfig: "pangocairo",
                   providers: [.apt(["libcairo2-dev", "libpango1.0-dev", "libx11-dev"])]),
    .systemLibrary(name: "CX11", path: "Sources/CX11", pkgConfig: "x11", providers: [.apt(["libx11-dev"])]),
    // Wayland client + xkbcommon + wl_cursor, with the xdg-shell protocol tables compiled in
    // (wayland-scanner output, see tools/linux/gen-wayland-protocols.sh).
    .target(
        name: "CWayland",
        path: "Sources/CWayland",
        linkerSettings: [.linkedLibrary("wayland-client"), .linkedLibrary("wayland-cursor"), .linkedLibrary("xkbcommon")]
    ),
    .target(
        name: "CoreGraphics",
        dependencies: ["CCairo"],
        path: "Sources/CoreGraphics",
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
]
targets += [
    .target(
        name: "CoreText",
        dependencies: ["CoreGraphics", "CCairo"],
        path: "Sources/CoreText",
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
]
// UniformTypeIdentifiers and ImageIO (ADR-0009): UTType over the SDK's core-type table;
// CGImageSource/CGImageDestination over Cairo's PNG reader and writer.
targets += [
    .target(name: "UniformTypeIdentifiers", path: "Sources/UniformTypeIdentifiers", swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(name: "ImageIO", dependencies: ["CoreGraphics", "CoreText", "CCairo"], path: "Sources/ImageIO", swiftSettings: [.swiftLanguageMode(.v5)]),
]
appKitDependencies += ["CoreGraphics", "CCairo", "CX11", "CWayland", "CoreText"]
appKitExclude += ["Platform/Win32"]
let quartzCoreDependencies: [Target.Dependency] = ["CoreGraphics"]
let leafModuleProducts: [Product] = [.library(name: "UniformTypeIdentifiers", targets: ["UniformTypeIdentifiers"]), .library(name: "ImageIO", targets: ["ImageIO"])]
let leafModuleTestDependencies: [Target.Dependency] = ["UniformTypeIdentifiers", "ImageIO"]
#else
// macOS: Apple's UniformTypeIdentifiers and ImageIO are the reference the tests run against.
appKitExclude += ["Platform/Win32", "Platform/Linux"]
let quartzCoreDependencies: [Target.Dependency] = []
let leafModuleProducts: [Product] = []
let leafModuleTestDependencies: [Target.Dependency] = []
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

// Metal (ADR-0004): the API as protocols plus the reference device, on every platform;
// MetalKit's MTKView sits on AppKit. The D3D12 shim is Windows-only.
#if os(Windows)
targets += [
    .target(name: "CMetalD3D12", path: "Sources/CMetalD3D12", linkerSettings: [.linkedLibrary("d3d12"), .linkedLibrary("dxgi"), .linkedLibrary("d3dcompiler")]),
]
let metalDependencies: [Target.Dependency] = ["CMetalD3D12"]
#else
let metalDependencies: [Target.Dependency] = []
#endif
targets += [
    .target(name: "Metal", dependencies: metalDependencies, path: "Sources/Metal", swiftSettings: [.swiftLanguageMode(.v5)]),
]

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
    .target(name: "MetalKit", dependencies: ["AppKit", "Metal"], path: "Sources/MetalKit", swiftSettings: [.swiftLanguageMode(.v5), .enableUpcomingFeature("StrictConcurrency")]),
    .executableTarget(
        name: "HelloWindow",
        dependencies: ["AppKit", "Metal", "MetalKit"],
        path: "Examples/HelloWindow"
    ),
    .testTarget(
        name: "AppKitTests",
        dependencies: ["AppKit", "Metal", "MetalKit"] + leafModuleTestDependencies,
        path: "Tests/AppKitTests"
    ),
]

let package = Package(
    name: "AppKitWin",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AppKit", targets: ["AppKit"]),
        .library(name: "Metal", targets: ["Metal"]),
        .library(name: "MetalKit", targets: ["MetalKit"]),
    ] + leafModuleProducts,
    targets: targets,
    cxxLanguageStandard: .cxx17
)
