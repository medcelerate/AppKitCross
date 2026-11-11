// NSEvent (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent
open class NSEvent: NSObject, NSCopying, NSCoding {
    public override init() { super.init() }
    // MARK: Storage
    private var _type: NSEvent.EventType = .applicationDefined
    private var _location = NSPoint.zero
    private var _modifierFlags: NSEvent.ModifierFlags = []
    private var _timestamp: TimeInterval = 0
    private var _windowNumber = 0
    private var _clickCount = 0
    private var _buttonNumber = 0
    private var _eventNumber = 0
    private var _pressure: Float = 0
    private var _deltaX: CGFloat = 0, _deltaY: CGFloat = 0, _deltaZ: CGFloat = 0
    private var _scrollingDeltaX: CGFloat = 0, _scrollingDeltaY: CGFloat = 0
    private var _hasPreciseScrollingDeltas = false
    private var _characters: String? = nil
    private var _charactersIgnoringModifiers: String? = nil
    private var _isARepeat = false
    private var _keyCode: UInt16 = 0
    private var _subtype: NSEvent.EventSubtype = .windowExposed
    private var _data1 = 0, _data2 = 0
    private var _trackingNumber = 0
    private var _userData: UnsafeMutableRawPointer? = nil
    private var _trackingArea: NSTrackingArea? = nil
    private var _phase: NSEvent.Phase = []
    private var _momentumPhase: NSEvent.Phase = []
    private var _magnification: CGFloat = 0
    private var _rotation: Float = 0

    /// Backend-facing state. Mirrors the OS so the class properties can answer without a query.
    nonisolated(unsafe) static var _currentModifierFlags: NSEvent.ModifierFlags = []
    nonisolated(unsafe) static var _pressedMouseButtons = 0

    /// Internal designated initializer used by backends and the factory methods.
    internal init(type: NSEvent.EventType, location: NSPoint, modifierFlags: NSEvent.ModifierFlags,
                  timestamp: TimeInterval, windowNumber: Int) {
        _type = type
        _location = location
        _modifierFlags = modifierFlags
        _timestamp = timestamp
        _windowNumber = windowNumber
        super.init()
    }

    /// Window helper: a mouse-entered or mouse-exited event for a tracking area (NSTrackingArea).
    internal static func _enterExitEvent(type: NSEvent.EventType, location: NSPoint, modifierFlags: NSEvent.ModifierFlags,
                                         timestamp: TimeInterval, windowNumber: Int, trackingArea: NSTrackingArea) -> NSEvent {
        let e = NSEvent(type: type, location: location, modifierFlags: modifierFlags, timestamp: timestamp, windowNumber: windowNumber)
        e._trackingArea = trackingArea
        e._trackingNumber = Int(bitPattern: UInt(bitPattern: ObjectIdentifier(trackingArea).hashValue))
        return e
    }

    /// Backend helper: a scroll-wheel event.
    internal static func _scrollEvent(location: NSPoint, modifierFlags: NSEvent.ModifierFlags, timestamp: TimeInterval,
                                      windowNumber: Int, deltaX: CGFloat, deltaY: CGFloat, precise: Bool,
                                      phase: NSEvent.Phase = [], momentumPhase: NSEvent.Phase = []) -> NSEvent {
        let e = NSEvent(type: .scrollWheel, location: location, modifierFlags: modifierFlags, timestamp: timestamp, windowNumber: windowNumber)
        e._deltaX = deltaX
        e._deltaY = deltaY
        e._scrollingDeltaX = deltaX
        e._scrollingDeltaY = deltaY
        e._hasPreciseScrollingDeltas = precise
        e._phase = phase
        e._momentumPhase = momentumPhase
        return e
    }

    /// Backend helper: a gesture event (magnify, rotate, swipe, beginGesture, endGesture,
    /// smartMagnify, pressure). `magnification` and `rotation` (degrees) are this event's
    /// change; `deltaX`/`deltaY` carry a swipe's direction; `phase` marks the first and
    /// last event of a gesture where the platform reports one.
    internal static func _gestureEvent(type: NSEvent.EventType, location: NSPoint, modifierFlags: NSEvent.ModifierFlags,
                                       timestamp: TimeInterval, windowNumber: Int, magnification: CGFloat = 0, rotation: Float = 0,
                                       deltaX: CGFloat = 0, deltaY: CGFloat = 0, phase: NSEvent.Phase = [], pressure: Float = 0) -> NSEvent {
        let e = NSEvent(type: type, location: location, modifierFlags: modifierFlags, timestamp: timestamp, windowNumber: windowNumber)
        e._magnification = magnification
        e._rotation = rotation
        e._deltaX = deltaX
        e._deltaY = deltaY
        e._phase = phase
        e._pressure = pressure
        return e
    }

    /// Backend helper: a mouse event carrying motion deltas and the button that caused it.
    internal static func _mouseEvent(type: NSEvent.EventType, location: NSPoint, modifierFlags: NSEvent.ModifierFlags,
                                     timestamp: TimeInterval, windowNumber: Int, clickCount: Int, buttonNumber: Int,
                                     deltaX: CGFloat = 0, deltaY: CGFloat = 0, pressure: Float = 0) -> NSEvent {
        let e = NSEvent(type: type, location: location, modifierFlags: modifierFlags, timestamp: timestamp, windowNumber: windowNumber)
        e._clickCount = clickCount
        e._buttonNumber = buttonNumber
        e._deltaX = deltaX
        e._deltaY = deltaY
        e._pressure = pressure
        return e
    }

    open override var description: String {
        "NSEvent: type=\(_type) loc=(\(_location.x),\(_location.y)) time=\(_timestamp) flags=\(_modifierFlags.rawValue) win=\(_windowNumber)"
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/init(cgevent:)
    public init?(cgEvent: CGEvent) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/init(eventref:)
    public init?(eventRef: UnsafeRawPointer) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/absolutex
    open var absoluteX: Int { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/absolutey
    open var absoluteY: Int { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/absolutez
    open var absoluteZ: Int { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)
    public class func addGlobalMonitorForEvents(matching mask: NSEvent.EventTypeMask, handler block: @escaping (NSEvent) -> Void) -> Any? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents(matching:handler:)
    public class func addLocalMonitorForEvents(matching mask: NSEvent.EventTypeMask, handler block: @escaping (NSEvent) -> NSEvent?) -> Any? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/alltouches()
    @available(macOS 10.12, *)
    open func allTouches() -> Set<NSTouch> { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/associatedeventsmask
    @available(macOS 10.10, *)
    open var associatedEventsMask: NSEvent.EventTypeMask { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/buttonmask
    open var buttonMask: NSEvent.ButtonMask { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/buttonnumber
    open var buttonNumber: Int { _buttonNumber }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/capabilitymask
    open var capabilityMask: Int { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/cgevent
    open var cgEvent: CGEvent? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/characters
    open var characters: String? { _characters }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/characters(byapplyingmodifiers:)
    @available(macOS 10.15, *)
    open func characters(byApplyingModifiers modifiers: NSEvent.ModifierFlags) -> String? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/charactersignoringmodifiers
    open var charactersIgnoringModifiers: String? { _charactersIgnoringModifiers }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/clickcount
    open var clickCount: Int { _clickCount }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/coalescedtouches(for:)
    @available(macOS 10.12, *)
    open func coalescedTouches(for touch: NSTouch) -> [NSTouch] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/context
    open var context: NSGraphicsContext? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/data1
    open var data1: Int { _data1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/data2
    open var data2: Int { _data2 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/deltax
    open var deltaX: CGFloat { _deltaX }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/deltay
    open var deltaY: CGFloat { _deltaY }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/deltaz
    open var deltaZ: CGFloat { _deltaZ }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/deviceid
    open var deviceID: Int { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/doubleclickinterval
    class public var doubleClickInterval: TimeInterval { 0.5 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/enterexitevent(with:location:modifierflags:timestamp:windownumber:context:eventnumber:trackingnumber:userdata:)
    public class func enterExitEvent(with type: NSEvent.EventType, location: NSPoint, modifierFlags flags: NSEvent.ModifierFlags, timestamp time: TimeInterval, windowNumber wNum: Int, context unusedPassNil: NSGraphicsContext?, eventNumber eNum: Int, trackingNumber tNum: Int, userData data: UnsafeMutableRawPointer?) -> NSEvent? {
        let e = NSEvent(type: type, location: location, modifierFlags: flags, timestamp: time, windowNumber: wNum)
        e._eventNumber = eNum
        e._trackingNumber = tNum
        e._userData = data
        return e
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/eventnumber
    open var eventNumber: Int { _eventNumber }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/eventref
    open var eventRef: UnsafeRawPointer? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/foreverduration
    static public var foreverDuration: TimeInterval { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/hasprecisescrollingdeltas
    open var hasPreciseScrollingDeltas: Bool { _hasPreciseScrollingDeltas }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/isarepeat
    open var isARepeat: Bool { _isARepeat }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/isdirectioninvertedfromdevice
    open var isDirectionInvertedFromDevice: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/isenteringproximity
    open var isEnteringProximity: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/ismousecoalescingenabled
    class public var isMouseCoalescingEnabled: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/isswipetrackingfromscrolleventsenabled
    class public var isSwipeTrackingFromScrollEventsEnabled: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/keycode
    open var keyCode: UInt16 { _keyCode }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/keyevent(with:location:modifierflags:timestamp:windownumber:context:characters:charactersignoringmodifiers:isarepeat:keycode:)
    public class func keyEvent(with type: NSEvent.EventType, location: NSPoint, modifierFlags flags: NSEvent.ModifierFlags, timestamp time: TimeInterval, windowNumber wNum: Int, context unusedPassNil: NSGraphicsContext?, characters keys: String, charactersIgnoringModifiers ukeys: String, isARepeat flag: Bool, keyCode code: UInt16) -> NSEvent? {
        let e = NSEvent(type: type, location: location, modifierFlags: flags, timestamp: time, windowNumber: wNum)
        e._characters = keys
        e._charactersIgnoringModifiers = ukeys
        e._isARepeat = flag
        e._keyCode = code
        return e
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/keyrepeatdelay
    class public var keyRepeatDelay: TimeInterval { 0.5 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/keyrepeatinterval
    class public var keyRepeatInterval: TimeInterval { 1.0 / 12.0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/locationinwindow
    open var locationInWindow: NSPoint { _location }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/magnification
    open var magnification: CGFloat { _magnification }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/modifierflags
    open var modifierFlags: NSEvent.ModifierFlags { _modifierFlags }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/modifierflags
    class public var modifierFlags: NSEvent.ModifierFlags { _currentModifierFlags }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/momentumphase
    open var momentumPhase: NSEvent.Phase { _momentumPhase }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/mouseevent(with:location:modifierflags:timestamp:windownumber:context:eventnumber:clickcount:pressure:)
    public class func mouseEvent(with type: NSEvent.EventType, location: NSPoint, modifierFlags flags: NSEvent.ModifierFlags, timestamp time: TimeInterval, windowNumber wNum: Int, context unusedPassNil: NSGraphicsContext?, eventNumber eNum: Int, clickCount cNum: Int, pressure: Float) -> NSEvent? {
        let e = NSEvent(type: type, location: location, modifierFlags: flags, timestamp: time, windowNumber: wNum)
        e._eventNumber = eNum
        e._clickCount = cNum
        e._pressure = pressure
        switch type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged: e._buttonNumber = 1
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged: e._buttonNumber = 2
        default: e._buttonNumber = 0
        }
        return e
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/mouselocation
    class public var mouseLocation: NSPoint { MainActor.assumeIsolated { Platform.backend.mouseLocation } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/otherevent(with:location:modifierflags:timestamp:windownumber:context:subtype:data1:data2:)
    public class func otherEvent(with type: NSEvent.EventType, location: NSPoint, modifierFlags flags: NSEvent.ModifierFlags, timestamp time: TimeInterval, windowNumber wNum: Int, context unusedPassNil: NSGraphicsContext?, subtype: Int16, data1 d1: Int, data2 d2: Int) -> NSEvent? {
        let e = NSEvent(type: type, location: location, modifierFlags: flags, timestamp: time, windowNumber: wNum)
        e._subtype = NSEvent.EventSubtype(rawValue: Int(subtype)) ?? .applicationActivated
        e._data1 = d1
        e._data2 = d2
        return e
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/phase
    open var phase: NSEvent.Phase { _phase }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/pointingdeviceid
    open var pointingDeviceID: Int { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/pointingdeviceserialnumber
    open var pointingDeviceSerialNumber: Int { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/pointingdevicetype
    open var pointingDeviceType: NSEvent.PointingDeviceType { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/pressedmousebuttons
    class public var pressedMouseButtons: Int { _pressedMouseButtons }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/pressure
    open var pressure: Float { _pressure }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/pressurebehavior
    @available(macOS 10.11, *)
    open var pressureBehavior: NSEvent.PressureBehavior { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/removemonitor(_:)
    public class func removeMonitor(_ eventMonitor: Any) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/rotation
    open var rotation: Float { _rotation }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/scrollingdeltax
    open var scrollingDeltaX: CGFloat { _scrollingDeltaX }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/scrollingdeltay
    open var scrollingDeltaY: CGFloat { _scrollingDeltaY }
    /// Returns `nil` if the receiver is not a “special” key event.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/specialkey
    open var specialKey: NSEvent.SpecialKey? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/stage
    @available(macOS 10.10, *)
    open var stage: Int { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/stagetransition
    @available(macOS 10.10, *)
    open var stageTransition: CGFloat { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/startperiodicevents(afterdelay:withperiod:)
    public class func startPeriodicEvents(afterDelay delay: TimeInterval, withPeriod period: TimeInterval) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/stopperiodicevents()
    public class func stopPeriodicEvents() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/subtype
    open var subtype: NSEvent.EventSubtype { _subtype }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/systemtabletid
    open var systemTabletID: Int { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/tabletid
    open var tabletID: Int { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/tangentialpressure
    open var tangentialPressure: Float { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/tilt
    open var tilt: NSPoint { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/timestamp
    open var timestamp: TimeInterval { _timestamp }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/touches(for:)
    @available(macOS 10.12, *)
    open func touches(for view: NSView) -> Set<NSTouch> { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/touches(matching:in:)
    open func touches(matching phase: NSTouch.Phase, in view: NSView?) -> Set<NSTouch> { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/trackswipeevent(options:dampenamountthresholdmin:max:usinghandler:)
    open func trackSwipeEvent(options: NSEvent.SwipeTrackingOptions = [], dampenAmountThresholdMin minDampenThreshold: CGFloat, max maxDampenThreshold: CGFloat, usingHandler trackingHandler: @escaping (CGFloat, NSEvent.Phase, Bool, UnsafeMutablePointer<ObjCBool>) -> Void) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/trackingarea
    open var trackingArea: NSTrackingArea? { _trackingArea }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/trackingnumber
    open var trackingNumber: Int { _trackingNumber }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/type
    open var type: NSEvent.EventType { _type }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/uniqueid
    open var uniqueID: UInt64 { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/userdata
    open var userData: UnsafeMutableRawPointer? { _userData }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/vendordefined
    open var vendorDefined: Any { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/vendorid
    open var vendorID: Int { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/vendorpointingdevicetype
    open var vendorPointingDeviceType: Int { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/window
    open var window: NSWindow? {
        let n = _windowNumber
        return MainActor.assumeIsolated { NSApplication._shared?.window(withWindowNumber: n) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/windownumber
    open var windowNumber: Int { _windowNumber }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any { self }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { }
    // Requirement of NSCoding
    public required init?(coder: NSCoder) { super.init() }
}
