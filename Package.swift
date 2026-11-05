// swift-tools-version:6.0
import PackageDescription
import Foundation

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
    // Apple's CoreGraphics submodule names (`import CoreGraphics.CGGeometry`): a clang
    // module map the Swift CoreGraphics module overlays (Sources/CCoreGraphicsModules).
    .systemLibrary(name: "CCoreGraphicsModules", path: "Sources/CCoreGraphicsModules"),
    .target(
        name: "CoreGraphics",
        dependencies: ["CD2D", "CCoreGraphicsModules"],
        path: "Sources/CoreGraphics",
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    // extern "C" shim over the UI Automation provider interfaces (ADR-0013).
    .target(
        name: "CUIAutomation",
        path: "Sources/CUIAutomation",
        linkerSettings: [.linkedLibrary("uiautomationcore"), .linkedLibrary("oleaut32"), .linkedLibrary("ole32")]
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
targets += [
    // Combine (ADR-0008): a port of OpenCombine under Apple's module name, so code written
    // against Combine compiles unchanged. On macOS the package uses Apple's Combine.
    .target(
        name: "Combine",
        path: "Sources/Combine",
        exclude: ["LICENSE", "NOTICE"],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
]
// UniformTypeIdentifiers and ImageIO (ADR-0009): UTType over the SDK's core-type table;
// CGImageSource/CGImageDestination over the WIC decode/encode in the CD2D shim.
targets += [
    .target(name: "UniformTypeIdentifiers", path: "Sources/UniformTypeIdentifiers", swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(name: "ImageIO", dependencies: ["CoreGraphics", "CoreText", "CD2D"], path: "Sources/ImageIO", swiftSettings: [.swiftLanguageMode(.v5)]),
]
targets += [
    // extern "C" shim over WASAPI (IMMDeviceEnumerator, IAudioClient3, IAudioRenderClient)
    // for the AVFAudio output stream (ADR-0014).
    .target(name: "CWASAPI", path: "Sources/CWASAPI", linkerSettings: [.linkedLibrary("ole32"), .linkedLibrary("avrt"), .linkedLibrary("uuid")]),
]
let audioShimDependencies: [Target.Dependency] = ["CWASAPI"]
appKitDependencies += ["CoreGraphics", "CD2D", "CoreText", "CUIAutomation"]
appKitExclude += ["Platform/Linux"]
let quartzCoreDependencies: [Target.Dependency] = ["CoreGraphics"]
let swiftUIDependencies: [Target.Dependency] = ["AppKit", "Combine", "UniformTypeIdentifiers"]
let leafModuleProducts: [Product] = [.library(name: "UniformTypeIdentifiers", targets: ["UniformTypeIdentifiers"]), .library(name: "ImageIO", targets: ["ImageIO"])]
let leafModuleTestDependencies: [Target.Dependency] = ["UniformTypeIdentifiers", "ImageIO"]
let platformTestDependencies: [Target.Dependency] = ["CUIAutomation"]
#elseif os(Linux)
// Linux: Cairo + PangoCairo for CoreGraphics and text, Xlib or Wayland for windows (Milestone 8).
targets += [
    .systemLibrary(name: "CCairo", path: "Sources/CCairo", pkgConfig: "pangocairo",
                   providers: [.apt(["libcairo2-dev", "libpango1.0-dev", "libx11-dev"])]),
    .systemLibrary(name: "CX11", path: "Sources/CX11", pkgConfig: "x11", providers: [.apt(["libx11-dev", "libxi-dev"])]),
    // libdbus-1 for the AT-SPI2 accessibility bridge (ADR-0013).
    .systemLibrary(name: "CDBus", path: "Sources/CDBus", pkgConfig: "dbus-1", providers: [.apt(["libdbus-1-dev"])]),
    // Wayland client + xkbcommon + wl_cursor, with the xdg-shell protocol tables compiled in
    // (wayland-scanner output, see tools/linux/gen-wayland-protocols.sh).
    .target(
        name: "CWayland",
        path: "Sources/CWayland",
        linkerSettings: [.linkedLibrary("wayland-client"), .linkedLibrary("wayland-cursor"), .linkedLibrary("xkbcommon")]
    ),
    .systemLibrary(name: "CCoreGraphicsModules", path: "Sources/CCoreGraphicsModules"),
    .target(
        name: "CoreGraphics",
        dependencies: ["CCairo", "CCoreGraphicsModules"],
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
targets += [
    // Combine (ADR-0008): a port of OpenCombine under Apple's module name, so code written
    // against Combine compiles unchanged. On macOS the package uses Apple's Combine.
    .target(
        name: "Combine",
        path: "Sources/Combine",
        exclude: ["LICENSE", "NOTICE"],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
]
// UniformTypeIdentifiers and ImageIO (ADR-0009): UTType over the SDK's core-type table;
// CGImageSource/CGImageDestination over Cairo's PNG reader and writer.
targets += [
    .target(name: "UniformTypeIdentifiers", path: "Sources/UniformTypeIdentifiers", swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(name: "ImageIO", dependencies: ["CoreGraphics", "CoreText", "CCairo"], path: "Sources/ImageIO", swiftSettings: [.swiftLanguageMode(.v5)]),
]
targets += [
    // PipeWire and ALSA output streams for AVFAudio (ADR-0014). Both shims dlopen their
    // library at runtime; CPipeWireSystem only supplies the PipeWire include paths through
    // pkg-config (without libpipewire-0.3-dev the shim compiles to stubs, as CMetalVulkan
    // does without the Vulkan headers).
    .systemLibrary(name: "CPipeWireSystem", path: "Sources/CPipeWireSystem", pkgConfig: "libpipewire-0.3",
                   providers: [.apt(["libpipewire-0.3-dev"])]),
    .target(name: "CPipeWire", dependencies: ["CPipeWireSystem"], path: "Sources/CPipeWire", linkerSettings: [.linkedLibrary("dl")]),
    .target(name: "CALSA", path: "Sources/CALSA", linkerSettings: [.linkedLibrary("dl")]),
]
let audioShimDependencies: [Target.Dependency] = ["CPipeWire", "CALSA"]
appKitDependencies += ["CoreGraphics", "CCairo", "CX11", "CWayland", "CoreText", "CDBus"]
appKitExclude += ["Platform/Win32"]
let quartzCoreDependencies: [Target.Dependency] = ["CoreGraphics"]
let swiftUIDependencies: [Target.Dependency] = ["AppKit", "Combine", "UniformTypeIdentifiers"]
let leafModuleProducts: [Product] = [.library(name: "UniformTypeIdentifiers", targets: ["UniformTypeIdentifiers"]), .library(name: "ImageIO", targets: ["ImageIO"])]
let leafModuleTestDependencies: [Target.Dependency] = ["UniformTypeIdentifiers", "ImageIO"]
let platformTestDependencies: [Target.Dependency] = ["CDBus"]
#else
// macOS: Apple's UniformTypeIdentifiers and ImageIO are the reference the tests run against.
let audioShimDependencies: [Target.Dependency] = []
appKitExclude += ["Platform/Win32", "Platform/Linux"]
let quartzCoreDependencies: [Target.Dependency] = []
let swiftUIDependencies: [Target.Dependency] = ["AppKit"]
let leafModuleProducts: [Product] = []
let leafModuleTestDependencies: [Target.Dependency] = []
let platformTestDependencies: [Target.Dependency] = []
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
#elseif os(Linux)
// The Vulkan shim (ADR-0012) dlopens the loader at runtime; only <vulkan/vulkan.h> is a
// build-time dependency, and without it the shim compiles to stubs.
targets += [
    .target(name: "CMetalVulkan", path: "Sources/CMetalVulkan", linkerSettings: [.linkedLibrary("dl")]),
]
let metalDependencies: [Target.Dependency] = ["CMetalVulkan"]
#else
let metalDependencies: [Target.Dependency] = []
#endif
targets += [
    .target(name: "Metal", dependencies: metalDependencies, path: "Sources/Metal", swiftSettings: [.swiftLanguageMode(.v5)]),
]

// AVFAudio and AVFoundation (ADR-0014): the audio API under Apple's module names, over a
// pure-Swift engine and the WASAPI / PipeWire / ALSA streams. Built on Windows and Linux;
// on macOS the package uses Apple's AVFAudio (the tests then run against the real one),
// unless APPKITWIN_HOST_AVFAUDIO=1 shadows it with ours so the engine's own tests run on
// the Mac too (the null output backend only; no CoreAudio stream). The engine's lock-free
// queues use the CAudioAtomics inline C atomics (the Synchronization module needs macOS
// 15); AVFAudio imports them as an implementation detail, so no client of the module
// needs the clang module map (the XCTest interface build, which loads our AppKit, would
// otherwise fail to find it).
#if os(Windows) || os(Linux)
let buildsAVFAudio = true
#else
let buildsAVFAudio = ProcessInfo.processInfo.environment["APPKITWIN_HOST_AVFAUDIO"] == "1"
#endif
var avfAudioProducts: [Product] = []
var avfAudioDependencies: [Target.Dependency] = []
var avfAudioTestSettings: [SwiftSetting] = []
if buildsAVFAudio {
    targets += [
        .target(name: "CAudioAtomics", path: "Sources/CAudioAtomics"),
        .target(name: "AVFAudio", dependencies: ["CAudioAtomics"] + audioShimDependencies, path: "Sources/AVFAudio", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "AVFoundation", dependencies: ["AVFAudio"], path: "Sources/AVFoundation", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
    avfAudioProducts = [.library(name: "AVFAudio", targets: ["AVFAudio"]), .library(name: "AVFoundation", targets: ["AVFoundation"])]
    avfAudioDependencies = ["AVFAudio", "AVFoundation"]
    avfAudioTestSettings = [.define("APPKITWIN_AVFAUDIO")]
    appKitDependencies += ["AVFAudio"]
}

// On macOS the tests import Apple's Combine; on Windows and Linux they need our target.
#if os(Windows) || os(Linux)
let combineProducts: [Product] = [.library(name: "Combine", targets: ["Combine"])]
let combineTestDependencies: [Target.Dependency] = ["Combine"]
#else
let combineProducts: [Product] = []
let combineTestDependencies: [Target.Dependency] = []
#endif

var appKitTestDependencies: [Target.Dependency] = ["AppKit", "Metal", "MetalKit", "SwiftUI"]
appKitTestDependencies += combineTestDependencies
appKitTestDependencies += leafModuleTestDependencies
appKitTestDependencies += platformTestDependencies
appKitTestDependencies += avfAudioDependencies
var audioPlayerDependencies: [Target.Dependency] = ["AppKit"]
audioPlayerDependencies += avfAudioDependencies

targets += [
    // SwiftUI over this AppKit (ADR-0010), on every platform.
    .target(name: "SwiftUI", dependencies: swiftUIDependencies, path: "Sources/SwiftUI", swiftSettings: [.swiftLanguageMode(.v5)]),
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
    .target(name: "MetalKit", dependencies: ["AppKit", "QuartzCore", "Metal"], path: "Sources/MetalKit", swiftSettings: [.swiftLanguageMode(.v5), .enableUpcomingFeature("StrictConcurrency")]),
    .executableTarget(
        name: "HelloWindow",
        dependencies: ["AppKit", "Metal", "MetalKit", "SwiftUI"],
        path: "Examples/HelloWindow"
    ),
    // Small, self-contained examples (Examples/<Name>/README.md says what each shows).
    .executableTarget(name: "Calculator", dependencies: ["AppKit", "SwiftUI"], path: "Examples/Calculator", exclude: ["README.md"]),
    .executableTarget(name: "FramelessWindow", dependencies: ["AppKit"], path: "Examples/FramelessWindow", exclude: ["README.md"]),
    .executableTarget(name: "Animation", dependencies: ["AppKit", "SwiftUI"], path: "Examples/Animation", exclude: ["README.md"]),
    .executableTarget(name: "Drawing", dependencies: ["AppKit"], path: "Examples/Drawing", exclude: ["README.md"]),
    .executableTarget(name: "Observable", dependencies: ["AppKit", "SwiftUI"], path: "Examples/Observable", exclude: ["README.md"]),
    .executableTarget(name: "AudioPlayer", dependencies: audioPlayerDependencies, path: "Examples/AudioPlayer", exclude: ["README.md"]),
    .testTarget(
        name: "AppKitTests",
        dependencies: appKitTestDependencies,
        path: "Tests/AppKitTests",
        swiftSettings: avfAudioTestSettings
    ),
]


let package = Package(
    name: "AppKitWin",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AppKit", targets: ["AppKit"]),
        .library(name: "Metal", targets: ["Metal"]),
        .library(name: "MetalKit", targets: ["MetalKit"]),
        .library(name: "SwiftUI", targets: ["SwiftUI"]),
    ] + combineProducts + leafModuleProducts + avfAudioProducts,
    targets: targets,
    cxxLanguageStandard: .cxx17
)
