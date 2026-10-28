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
    open var auxiliaryTopLeftArea: NSRect? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytoprightarea
    @available(macOS 12.0, *)
    open var auxiliaryTopRightArea: NSRect? { unimplemented() }
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
    open func canRepresent(_ displayGamut: NSDisplayGamut) -> Bool { unimplemented() }
    /// The CGDirectDisplayID for this screen. This will return nil if there isn't one and will never return kCGNullDirectDisplay.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/cgdirectdisplayid
    @available(macOS 26.0, *)
    open var cgDirectDisplayID: CGDirectDisplayID? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/colorspace
    open var colorSpace: NSColorSpace? { unimplemented() }
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
    open var depth: NSWindow.Depth { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/devicedescription
    open var deviceDescription: [NSDeviceDescriptionKey : Any] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/displaylink(target:selector:)
    @available(macOS 14.0, *)
    open func displayLink(target: Any, selector: Selector) -> CADisplayLink { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/displayupdategranularity
    @available(macOS 12.0, *)
    open var displayUpdateGranularity: TimeInterval { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/frame
    open var frame: NSRect { _display.frame }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/lastdisplayupdatetimestamp
    @available(macOS 12.0, *)
    open var lastDisplayUpdateTimestamp: TimeInterval { unimplemented() }
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
    open var maximumExtendedDynamicRangeColorComponentValue: CGFloat { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/maximumframespersecond
    @available(macOS 12.0, *)
    open var maximumFramesPerSecond: Int { 60 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/maximumpotentialextendeddynamicrangecolorcomponentvalue
    @available(macOS 10.15, *)
    open var maximumPotentialExtendedDynamicRangeColorComponentValue: CGFloat { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/maximumreferenceextendeddynamicrangecolorcomponentvalue
    @available(macOS 10.15, *)
    open var maximumReferenceExtendedDynamicRangeColorComponentValue: CGFloat { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/maximumrefreshinterval
    @available(macOS 12.0, *)
    open var maximumRefreshInterval: TimeInterval { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/minimumrefreshinterval
    @available(macOS 12.0, *)
    open var minimumRefreshInterval: TimeInterval { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets
    @available(macOS 12.0, *)
    open var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/screens
    class public var screens: [NSScreen] { MainActor.assumeIsolated { Platform.backend.displays.map { NSScreen(display: $0) } } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/screenshaveseparatespaces
    class public var screensHaveSeparateSpaces: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/supportedwindowdepths
    open var supportedWindowDepths: UnsafePointer<NSWindow.Depth> { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscreen/visibleframe
    open var visibleFrame: NSRect { _display.visibleFrame }
}
