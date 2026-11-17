// NSScreen (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(QuartzCore)
import QuartzCore
#endif
#if canImport(CoreText)
import CoreText
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen
open class NSScreen: NSObject {
    private let _display: PlatformDisplay

    internal init(display: PlatformDisplay) {
        _display = display
        super.init()
    }

    open override var description: String { "<NSScreen \(_display.localizedName) \(_display.frame)>" }
    open override func isEqual(_ object: Any?) -> Bool { (object as? NSScreen).map { $0._display.frame == _display.frame } ?? false }
    open override var hash: Int { Int(_display.frame.minX) ^ Int(_display.frame.minY) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea
    @available(macOS 12.0, *)
    /// Nil: only Mac displays with a camera housing have auxiliary areas (macOS returns nil
    /// for every other screen).
    open var auxiliaryTopLeftArea: NSRect? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytoprightarea
    @available(macOS 12.0, *)
    open var auxiliaryTopRightArea: NSRect? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/backingalignedrect(_:options:)
    open func backingAlignedRect(_ rect: NSRect, options: AlignmentOptions = []) -> NSRect {
        let s = backingScaleFactor
        let x0 = (rect.minX * s).rounded(.down) / s, y0 = (rect.minY * s).rounded(.down) / s
        let x1 = (rect.maxX * s).rounded(.up) / s, y1 = (rect.maxY * s).rounded(.up) / s
        return NSRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/backingscalefactor
    open var backingScaleFactor: CGFloat { _display.backingScaleFactor }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/canrepresent(_:)
    @available(macOS 10.12, *)
    /// The port composes in sRGB on every platform (Direct2D, Cairo), so only the sRGB
    /// gamut is representable (ADR-0037).
    open func canRepresent(_ displayGamut: NSDisplayGamut) -> Bool { displayGamut == .sRGB }
    /// The CGDirectDisplayID for this screen. This will return nil if there isn't one and will never return kCGNullDirectDisplay.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/cgdirectdisplayid
    @available(macOS 26.0, *)
    /// Nil: Quartz display IDs exist only on macOS ("nil if there isn't one").
    open var cgDirectDisplayID: CGDirectDisplayID? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/colorspace
    /// sRGB: the port composes in sRGB on every platform (ADR-0037).
    open var colorSpace: NSColorSpace? { .sRGB }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/colorspacedidchangenotification
    static public var colorSpaceDidChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSScreenColorSpaceDidChangeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/convertrectfrombacking(_:)
    open func convertRectFromBacking(_ rect: NSRect) -> NSRect {
        let s = backingScaleFactor
        return NSRect(x: rect.minX / s, y: rect.minY / s, width: rect.width / s, height: rect.height / s)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/convertrecttobacking(_:)
    open func convertRectToBacking(_ rect: NSRect) -> NSRect {
        let s = backingScaleFactor
        return NSRect(x: rect.minX * s, y: rect.minY * s, width: rect.width * s, height: rect.height * s)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/deepest
    class public var deepest: NSScreen? { main }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/depth
    /// 24-bit RGB for an 8-bit display (macOS: 520 on an SDR panel), 64-bit RGB for deeper output.
    open var depth: NSWindow.Depth { _display.bitsPerSample > 8 ? .sixtyfourBitRGB : .twentyfourBitRGB }
    /// The keys macOS 15 reports: bits per sample, calibrated RGB, a screen, resolution
    /// (72 dpi × backing scale), size (the frame's) and the screen number (1-based).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/devicedescription
    open var deviceDescription: [NSDeviceDescriptionKey : Any] {
        let dpi = 72 * backingScaleFactor
        let number = MainActor.assumeIsolated { Platform.backend.displays.firstIndex { $0.frame == _display.frame } ?? 0 } + 1
        return [.bitsPerSample: _display.bitsPerSample, .colorSpaceName: NSColorSpaceName.calibratedRGB, .isScreen: "YES",
                .resolution: NSValue(size: NSSize(width: dpi, height: dpi)), .size: NSValue(size: frame.size),
                NSDeviceDescriptionKey(rawValue: "NSScreenNumber"): NSNumber(value: number)]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/displaylink(target:selector:)
    @available(macOS 14.0, *)
    @MainActor open func displayLink(target: Any, selector: Selector) -> CADisplayLink {
        _CoreAnimationHost.installIfNeeded()
        let t = target as AnyObject
        return CADisplayLink { link in _ = ActionRegistry.perform(selector, on: t, with: link) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/displayupdategranularity
    @available(macOS 12.0, *)
    /// One refresh interval: the port's displays refresh at a fixed rate (no variable refresh).
    open var displayUpdateGranularity: TimeInterval { 1 / _display.refreshRate }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/frame
    open var frame: NSRect { _display.frame }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/lastdisplayupdatetimestamp
    @available(macOS 12.0, *)
    /// When the port's frame clock last ticked (the display-link clock, `CACurrentMediaTime`'s
    /// timebase); 0 before the first frame.
    open var lastDisplayUpdateTimestamp: TimeInterval { MainActor.assumeIsolated { CARuntime.lastTickTime } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/localizedname
    @available(macOS 10.15, *)
    open var localizedName: String { _display.localizedName }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/main
    class public var main: NSScreen? {
        MainActor.assumeIsolated {
            if let key = NSApplication._shared?.keyWindow, let s = key.screen { return s }
            let all = screens
            return all.first { $0._display.isMain } ?? all.first
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/maximumextendeddynamicrangecolorcomponentvalue
    @available(macOS 10.11, *)
    open var maximumExtendedDynamicRangeColorComponentValue: CGFloat { _display.maximumEDRValue }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/maximumframespersecond
    @available(macOS 12.0, *)
    open var maximumFramesPerSecond: Int { Int(_display.refreshRate.rounded()) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/maximumpotentialextendeddynamicrangecolorcomponentvalue
    @available(macOS 10.15, *)
    open var maximumPotentialExtendedDynamicRangeColorComponentValue: CGFloat { _display.maximumPotentialEDRValue }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/maximumreferenceextendeddynamicrangecolorcomponentvalue
    @available(macOS 10.15, *)
    open var maximumReferenceExtendedDynamicRangeColorComponentValue: CGFloat { _display.maximumReferenceEDRValue }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/maximumrefreshinterval
    @available(macOS 12.0, *)
    /// The refresh interval (fixed-rate displays: the same as the minimum).
    open var maximumRefreshInterval: TimeInterval { 1 / _display.refreshRate }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/minimumrefreshinterval
    @available(macOS 12.0, *)
    open var minimumRefreshInterval: TimeInterval { 1 / _display.refreshRate }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets
    @available(macOS 12.0, *)
    open var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/screens
    class public var screens: [NSScreen] { MainActor.assumeIsolated { Platform.backend.displays.map { NSScreen(display: $0) } } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/screenshaveseparatespaces
    /// False: Windows virtual desktops and X11/Wayland workspaces span every monitor.
    class public var screensHaveSeparateSpaces: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/supportedwindowdepths
    open var supportedWindowDepths: UnsafePointer<NSWindow.Depth> { unimplemented("NSScreen.supportedWindowDepths — a zero-terminated C list cannot be made of the port's NSWindow.Depth, a Swift enum with no 0 case whose storage is not its raw value") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/visibleframe
    open var visibleFrame: NSRect { _display.visibleFrame }
}
