// swift-tools-version:6.0
import PackageDescription
import CompilerPluginSupport
import Foundation

// Windows-only modules. On macOS these are NOT declared: Apple's Foundation re-exports
// the real CoreGraphics, and a local module with the same name shadows the overlay and
// breaks CGRect. On Windows, Foundation only provides the geometry types (CGRect etc.),
// so our CoreGraphics module supplies CGContext, CGPath, CGColor, ... over Direct2D.
var targets: [Target] = []
var appKitDependencies: [Target.Dependency] = []
// The Liquid Glass shader sources (ADR-0052 stage 2) are embedded into GlassShaders.swift by
// tools/glass/embed-shaders.py, not built.
var appKitExclude: [String] = ["Platform/Shaders"]

#if os(Windows)
// DirectWrite and DirectComposition headers are C++-only; they arrive with C++ interop in
// Milestone 2/4. Milestone 1 needs only Direct2D, which `WinSDK` exposes as C.
targets += [
    // extern "C" shim over the Direct2D C++ COM interfaces (d2d1.h has no C vtables).
    .target(
        name: "CD2D",
        path: "Sources/CD2D",
        linkerSettings: [.linkedLibrary("d2d1"), .linkedLibrary("dwrite"), .linkedLibrary("windowscodecs"), .linkedLibrary("ole32"), .linkedLibrary("shlwapi"), .linkedLibrary("oleaut32"), .linkedLibrary("shell32"), .linkedLibrary("advapi32"),
                         // Milestone 3: DXGI flip-model swap chain presentation (d3d11 device, dxgi
                         // factory/swap chain, dxguid for the DXGI debug GUIDs).
                         .linkedLibrary("d3d11"), .linkedLibrary("dxgi"), .linkedLibrary("dxguid"),
                         // Milestone 3b: DirectComposition presentation of translucent windows and
                         // the DWM frame/backdrop attributes used by Win32Window.
                         .linkedLibrary("dcomp"), .linkedLibrary("dwmapi"),
                         // ADR-0026: the shell (version resources, session notifications).
                         .linkedLibrary("version"), .linkedLibrary("wtsapi32"), .linkedLibrary("user32"),
                         // ADR-0022: printers (winspool), the PrintDlgEx dialog and the common colour
                         // dialog (comdlg32, also behind APPKITWIN_COLOR_PANEL=native), print tickets
                         // (prntvpt) and the print document package target's CLSID/IIDs (uuid).
                         .linkedLibrary("winspool"), .linkedLibrary("comdlg32"), .linkedLibrary("prntvpt"), .linkedLibrary("uuid")]
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
    // extern "C" shim over the Text Services Framework: a text store (ITextStoreACP) per
    // window for input method composition, clause attributes and the candidate list (ADR-0045).
    .target(
        name: "CTextServices",
        path: "Sources/CTextServices",
        linkerSettings: [.linkedLibrary("ole32"), .linkedLibrary("oleaut32"), .linkedLibrary("uuid")]
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
appKitDependencies += ["CoreGraphics", "CD2D", "CoreText", "CUIAutomation", "ImageIO", "UniformTypeIdentifiers", "CTextServices"]
// The spell checker seam (ADR-0030): the Windows Spell Checking API over COM.
targets += [.target(name: "CSpellCheck", path: "Sources/CSpellCheck", linkerSettings: [.linkedLibrary("ole32")])]
appKitDependencies += ["CSpellCheck", "Combine"]
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
appKitDependencies += ["CoreGraphics", "CCairo", "CX11", "CWayland", "CoreText", "CDBus", "ImageIO", "UniformTypeIdentifiers"]
// The spell checker seam (ADR-0030): hunspell, loaded at run time.
targets += [.target(name: "CSpellCheck", path: "Sources/CSpellCheck", linkerSettings: [.linkedLibrary("dl")])]
appKitDependencies += ["CSpellCheck", "Combine"]
appKitExclude += ["Platform/Win32"]
// The Liquid Glass GPU program (ADR-0052 stage 2) drives the Vulkan shim directly.
appKitDependencies += ["CMetalVulkan"]
let quartzCoreDependencies: [Target.Dependency] = ["CoreGraphics"]
let swiftUIDependencies: [Target.Dependency] = ["AppKit", "Combine", "UniformTypeIdentifiers"]
let leafModuleProducts: [Product] = [.library(name: "UniformTypeIdentifiers", targets: ["UniformTypeIdentifiers"]), .library(name: "ImageIO", targets: ["ImageIO"])]
let leafModuleTestDependencies: [Target.Dependency] = ["UniformTypeIdentifiers", "ImageIO"]
let platformTestDependencies: [Target.Dependency] = ["CDBus"]
#else
// macOS: Apple's UniformTypeIdentifiers and ImageIO are the reference the tests run against.
// The Liquid Glass GPU program (ADR-0052 stage 2) runs on Apple's Metal through an
// Objective-C shim, so AppKit never imports Apple's Metal module (the port's own `Metal`
// target would shadow it).
targets += [.target(name: "CGlassMetal", path: "Sources/CGlassMetal", linkerSettings: [.linkedFramework("Metal"), .linkedFramework("Foundation")])]
appKitDependencies += ["CGlassMetal"]
let audioShimDependencies: [Target.Dependency] = []
appKitExclude += ["Platform/Win32", "Platform/Linux"]
let quartzCoreDependencies: [Target.Dependency] = []
let swiftUIDependencies: [Target.Dependency] = ["AppKit"]
let leafModuleProducts: [Product] = []
let leafModuleTestDependencies: [Target.Dependency] = []
let platformTestDependencies: [Target.Dependency] = []
#endif

// The crash report shim (ADR-0046): a minidump and text report on Windows (DbgHelp), a
// backtrace report on Linux. Built on macOS too, where only the tests use it.
#if os(Windows)
targets += [.target(name: "CCrashReport", path: "Sources/CCrashReport", linkerSettings: [.linkedLibrary("dbghelp"), .linkedLibrary("shell32")])]
#else
targets += [.target(name: "CCrashReport", path: "Sources/CCrashReport")]
#endif
appKitDependencies += ["CCrashReport"]

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

// ADR-0045: Swift-convention trampolines the port places in swift-corelibs-foundation's
// Bundle vtable (Bundle cannot be subclassed from another module), so Bundle.main and
// NSLocalizedString follow the app layout and the user's languages. Windows and Linux only
// (macOS apps use Apple's Bundle; on the host build XCTest imports AppKit, which must not
// need a C module its clients cannot see).
#if os(Windows) || os(Linux)
targets += [.target(name: "CBundleHooks", path: "Sources/CBundleHooks")]
appKitDependencies += ["CBundleHooks"]
#endif

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

// UserNotifications and ServiceManagement (ADR-0043): local notifications over Windows
// toasts (WinRT, through the CWinAppServices shim) and the freedesktop notification server
// (D-Bus), and the app's login item over the Run key / Startup folder and XDG autostart.
// AppKit depends on both, so `import UserNotifications` and `import ServiceManagement`
// resolve in any target that uses AppKit, as they do on macOS (AppKit does not re-export
// them; Apple's does not either). On macOS apps use Apple's frameworks; the tests compile
// the same sources as UserNotificationsPortable and ServiceManagementPortable instead, so the
// module names never shadow Apple's.
#if os(Windows)
targets += [
    .target(name: "CWinAppServices", path: "Sources/CWinAppServices",
            linkerSettings: [.linkedLibrary("runtimeobject"), .linkedLibrary("ole32"), .linkedLibrary("shell32"), .linkedLibrary("advapi32"), .linkedLibrary("uuid")]),
]
let notificationPlatformDependencies: [Target.Dependency] = ["CWinAppServices"]
let loginItemPlatformDependencies: [Target.Dependency] = ["CWinAppServices"]
let notificationTestPlatformDependencies: [Target.Dependency] = []
#elseif os(Linux)
let notificationPlatformDependencies: [Target.Dependency] = ["CDBus"]
let loginItemPlatformDependencies: [Target.Dependency] = []
// The D-Bus test plays the notification server itself.
let notificationTestPlatformDependencies: [Target.Dependency] = ["CDBus"]
#endif
#if os(Windows) || os(Linux)
targets += [
    .target(name: "UserNotifications", dependencies: notificationPlatformDependencies, path: "Sources/UserNotifications", swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(name: "ServiceManagement", dependencies: loginItemPlatformDependencies, path: "Sources/ServiceManagement", swiftSettings: [.swiftLanguageMode(.v5)]),
]
appKitDependencies += ["UserNotifications", "ServiceManagement"]
let systemServiceProducts: [Product] = [.library(name: "UserNotifications", targets: ["UserNotifications"]), .library(name: "ServiceManagement", targets: ["ServiceManagement"])]
let userNotificationsModule: Target.Dependency = "UserNotifications"
let serviceManagementModule: Target.Dependency = "ServiceManagement"
#else
targets += [
    .target(name: "UserNotificationsPortable", path: "Sources/UserNotifications", swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(name: "ServiceManagementPortable", path: "Sources/ServiceManagement", swiftSettings: [.swiftLanguageMode(.v5)]),
]
let systemServiceProducts: [Product] = []
let userNotificationsModule: Target.Dependency = "UserNotificationsPortable"
let serviceManagementModule: Target.Dependency = "ServiceManagementPortable"
let notificationTestPlatformDependencies: [Target.Dependency] = []
#endif
targets += [
    .testTarget(name: "UserNotificationsTests", dependencies: [userNotificationsModule] + notificationTestPlatformDependencies, path: "Tests/UserNotificationsTests", swiftSettings: [.swiftLanguageMode(.v5)]),
    .testTarget(name: "ServiceManagementTests", dependencies: [serviceManagementModule], path: "Tests/ServiceManagementTests", swiftSettings: [.swiftLanguageMode(.v5)]),
]

// OSLog, Network and CoreMIDI (ADR-0050): the three system frameworks Sibyl, the first
// commercial app ported, imports beside AppKit. Built under Apple's names on Windows and
// Linux (library products); on macOS apps use Apple's frameworks and the same sources build
// as `OSLogPortable`, `NetworkPortable` and `CoreMIDIPortable` for the tests only (a module
// named `Network` in the build directory would shadow Apple's for every macOS target).
// `OSLog` writes to stderr (Windows: also OutputDebugString); `Network` is NWConnection/
// NWListener/NWBrowser over BSD sockets and Winsock with a small mDNS responder and browser;
// `CoreMIDI` is the output subset over WinMM (`CWinMIDI`) and the ALSA sequencer
// (`CALSASeq`, dlopen'ed like `CALSA`).
#if os(Windows)
targets += [
    .target(name: "CWinMIDI", path: "Sources/CWinMIDI", linkerSettings: [.linkedLibrary("winmm")]),
    // Windows MIDI Services (MIDI 2.0, UMP) through C++/WinRT; compiles to the availability
    // check alone without a Windows.Devices.Midi2 (or preview App SDK
    // Microsoft.Windows.Devices.Midi2) projection on the include path, and WinMM is used.
    // advapi32: RegGetValueW for the App SDK runtime's registry key (ADR-0050).
    .target(name: "CWinMIDI2", path: "Sources/CWinMIDI2", linkerSettings: [.linkedLibrary("runtimeobject"), .linkedLibrary("ole32"), .linkedLibrary("advapi32")]),
]
let coreMIDIPlatformDependencies: [Target.Dependency] = ["CWinMIDI", "CWinMIDI2"]
let networkLinkerSettings: [LinkerSetting] = [.linkedLibrary("ws2_32"), .linkedLibrary("iphlpapi")]
#elseif os(Linux)
targets += [
    .target(name: "CALSASeq", path: "Sources/CALSASeq", linkerSettings: [.linkedLibrary("dl")]),
]
let coreMIDIPlatformDependencies: [Target.Dependency] = ["CALSASeq"]
let networkLinkerSettings: [LinkerSetting] = []
#else
let coreMIDIPlatformDependencies: [Target.Dependency] = []
let networkLinkerSettings: [LinkerSetting] = []
#endif
#if os(Windows) || os(Linux)
targets += [
    .target(name: "OSLog", path: "Sources/OSLog", swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(name: "Network", path: "Sources/Network", swiftSettings: [.swiftLanguageMode(.v5)], linkerSettings: networkLinkerSettings),
    .target(name: "CoreMIDI", dependencies: coreMIDIPlatformDependencies, path: "Sources/CoreMIDI", swiftSettings: [.swiftLanguageMode(.v5)]),
]
let systemFrameworkProducts: [Product] = [.library(name: "OSLog", targets: ["OSLog"]), .library(name: "Network", targets: ["Network"]), .library(name: "CoreMIDI", targets: ["CoreMIDI"])]
let osLogModule: Target.Dependency = "OSLog"
let networkModule: Target.Dependency = "Network"
let coreMIDIModule: Target.Dependency = "CoreMIDI"
#else
targets += [
    .target(name: "OSLogPortable", path: "Sources/OSLog", swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(name: "NetworkPortable", path: "Sources/Network", swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(name: "CoreMIDIPortable", path: "Sources/CoreMIDI", swiftSettings: [.swiftLanguageMode(.v5)]),
]
let systemFrameworkProducts: [Product] = []
let osLogModule: Target.Dependency = "OSLogPortable"
let networkModule: Target.Dependency = "NetworkPortable"
let coreMIDIModule: Target.Dependency = "CoreMIDIPortable"
#endif
targets += [
    .testTarget(name: "OSLogTests", dependencies: [osLogModule], path: "Tests/OSLogTests", swiftSettings: [.swiftLanguageMode(.v5)]),
    .testTarget(name: "NetworkTests", dependencies: [networkModule], path: "Tests/NetworkTests", swiftSettings: [.swiftLanguageMode(.v5)]),
    .testTarget(name: "CoreMIDITests", dependencies: [coreMIDIModule], path: "Tests/CoreMIDITests", swiftSettings: [.swiftLanguageMode(.v5)]),
]

// On macOS the tests import Apple's Combine; on Windows and Linux they need our target.
#if os(Windows) || os(Linux)
let combineProducts: [Product] = [.library(name: "Combine", targets: ["Combine"])]
let combineTestDependencies: [Target.Dependency] = ["Combine"]
// Examples/DailyTodo imports UserNotifications and ServiceManagement without naming them:
// they come with AppKit, as on macOS.
let dailyTodoPlatformDependencies: [Target.Dependency] = ["Combine"]
let mdVaultDependencies: [Target.Dependency] = ["UniformTypeIdentifiers"]
#else
let dailyTodoPlatformDependencies: [Target.Dependency] = []
let mdVaultDependencies: [Target.Dependency] = []
let combineProducts: [Product] = []
let combineTestDependencies: [Target.Dependency] = []
#endif

var appKitTestDependencies: [Target.Dependency] = ["AppKit", "Cocoa", "Metal", "MetalKit", "SwiftUI"]
appKitTestDependencies += combineTestDependencies
appKitTestDependencies += leafModuleTestDependencies
appKitTestDependencies += platformTestDependencies
appKitTestDependencies += avfAudioDependencies
var audioPlayerDependencies: [Target.Dependency] = ["AppKit"]
audioPlayerDependencies += avfAudioDependencies

// The compiler plugin behind `#Preview` (ADR-0049): no swift-syntax, just the plugin
// protocol over stdin/stdout. AppKit (and through it SwiftUI) declares the macros.
targets.append(.macro(name: "AppKitCrossPreviewMacros", path: "Sources/PreviewMacros", swiftSettings: [.swiftLanguageMode(.v5)]))
appKitDependencies.append("AppKitCrossPreviewMacros")

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
    // The Cocoa umbrella (AppKit + Foundation; the port has no Core Data to re-export).
    .target(name: "Cocoa", dependencies: ["AppKit"], path: "Sources/Cocoa", swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(name: "MetalKit", dependencies: ["AppKit", "QuartzCore", "Metal"], path: "Sources/MetalKit", swiftSettings: [.swiftLanguageMode(.v5), .enableUpcomingFeature("StrictConcurrency")]),
    .executableTarget(
        name: "HelloWindow",
        dependencies: ["AppKit", "Metal", "MetalKit", "SwiftUI"],
        path: "Examples/HelloWindow",
        // ADR-0045: a localized greeting (en, de) and an image, found through Bundle.main in
        // the target's SwiftPM bundle (AppKitCross_HelloWindow.resources/Resources).
        resources: [.copy("Resources")]
    ),
    // Small, self-contained examples (Examples/<Name>/README.md says what each shows).
    .executableTarget(name: "Calculator", dependencies: ["AppKit", "SwiftUI"], path: "Examples/Calculator", exclude: ["README.md"]),
    .executableTarget(name: "FramelessWindow", dependencies: ["AppKit"], path: "Examples/FramelessWindow", exclude: ["README.md"]),
    .executableTarget(name: "Animation", dependencies: ["AppKit", "SwiftUI"], path: "Examples/Animation", exclude: ["README.md"]),
    .executableTarget(name: "Drawing", dependencies: ["AppKit"], path: "Examples/Drawing", exclude: ["README.md"]),
    .executableTarget(name: "Observable", dependencies: ["AppKit", "SwiftUI"], path: "Examples/Observable", exclude: ["README.md"]),
    .executableTarget(name: "AudioPlayer", dependencies: audioPlayerDependencies, path: "Examples/AudioPlayer", exclude: ["README.md"]),
    .executableTarget(name: "Sheets", dependencies: ["AppKit", "SwiftUI"], path: "Examples/Sheets", exclude: ["README.md"]),
    // The document-based example: its Info.plist (CFBundleDocumentTypes) travels as a
    // resource (SwiftPM refuses a resource named Info.plist, hence Resources/TextEdit-Info.plist)
    // and main.swift points APPKITWIN_INFO_PLIST at it (ADR-0017).
    .executableTarget(name: "TextEdit", dependencies: ["AppKit"], path: "Examples/TextEdit", exclude: ["README.md"], resources: [.copy("Resources")]),
    .executableTarget(name: "Toolbar", dependencies: ["AppKit"], path: "Examples/Toolbar", exclude: ["README.md"]),
    .executableTarget(name: "Glass", dependencies: ["AppKit", "SwiftUI"], path: "Examples/Glass", exclude: ["README.md"]),
    .executableTarget(name: "Workspace", dependencies: ["AppKit"] + leafModuleTestDependencies.filter { "\($0)".contains("UniformTypeIdentifiers") }, path: "Examples/Workspace", exclude: ["README.md"]),
    // A real third-party SwiftUI app, vendored unmodified (one `#if canImport(ObjectiveC)`
    // around an `@objc`): Daily To Do (MIT, Examples/DailyTodo/README.md). Its logic module and
    // its dependency-free self-checks come along.
    // Upstream declares tools version 5.9, so its three targets build in Swift 5 language mode.
    .target(name: "DailyTodoCore", path: "Examples/DailyTodo/Sources/DailyTodoCore", swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(name: "DailyTodo", dependencies: ["AppKit", "SwiftUI", "DailyTodoCore"] + dailyTodoPlatformDependencies, path: "Examples/DailyTodo/Sources/DailyTodo", swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(name: "DailyTodoChecks", dependencies: ["DailyTodoCore"], path: "Examples/DailyTodo/Sources/DailyTodoChecks", swiftSettings: [.swiftLanguageMode(.v5)]),
    // The second real app, document-based: MD Vault (MIT, Examples/MDVault/README.md), its
    // `Sources/` vendored unmodified. Upstream builds with plain `swiftc` (Swift 5 mode). Its
    // Resources/ folder (upstream's Info.plist with the document types, the Markdown UTI and
    // the app name, the icon, the sample documents) is the target's SwiftPM bundle, where the
    // port finds the Info.plist and the icon at launch (ADR-0045).
    .executableTarget(name: "MDVault", dependencies: ["AppKit", "SwiftUI"] + mdVaultDependencies, path: "Examples/MDVault",
                      exclude: ["LICENSE", "README.md", "UPSTREAM-README.md"], sources: ["Sources/MDVault"], resources: [.copy("Resources")],
                      swiftSettings: [.swiftLanguageMode(.v5)]),
    .testTarget(
        name: "AppKitTests",
        dependencies: appKitTestDependencies,
        path: "Tests/AppKitTests",
        // BundleTests reads the fixture app folder from the source tree (ADR-0045).
        exclude: ["Fixtures"],
        swiftSettings: avfAudioTestSettings
    ),
]


// Shipping (ADR-0046): `swift package bundle --product <Name>` lays out a folder that runs
// without a Swift toolchain. The plugin builds the product and runs AppKitCrossBundle, whose
// logic (PE imports, ELF DT_NEEDED, the library policy, zip) is AppBundler.
targets += [
    .target(name: "AppBundler", path: "Sources/AppBundler", swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(name: "AppKitCrossBundle", dependencies: ["AppBundler"], path: "Sources/AppKitCrossBundle", swiftSettings: [.swiftLanguageMode(.v5)]),
    .plugin(
        name: "AppBundle",
        capability: .command(
            intent: .custom(verb: "bundle", description: "Build an executable product and lay it out as a folder that runs without Swift installed (--zip, --appimage)"),
            permissions: [.writeToPackageDirectory(reason: "The app folder and archives go to .build/bundle")]
        ),
        dependencies: ["AppKitCrossBundle"],
        path: "Plugins/AppBundle"
    ),
    .testTarget(name: "AppBundlerTests", dependencies: ["AppBundler"], path: "Tests/AppBundlerTests", swiftSettings: [.swiftLanguageMode(.v5)]),
]


let package = Package(
    name: "AppKitCross",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AppKit", targets: ["AppKit"]),
        .library(name: "Cocoa", targets: ["Cocoa"]),
        .library(name: "Metal", targets: ["Metal"]),
        .library(name: "MetalKit", targets: ["MetalKit"]),
        .library(name: "SwiftUI", targets: ["SwiftUI"]),
        .plugin(name: "AppBundle", targets: ["AppBundle"]),
    ] + combineProducts + leafModuleProducts + avfAudioProducts + systemServiceProducts + systemFrameworkProducts,
    targets: targets,
    cxxLanguageStandard: .cxx17
)
