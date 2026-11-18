// NSEvent (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() say why (ADR-0038).
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
    // Tablet and pointing-device fields (zero unless a backend reports a pen or tablet).
    private var _absolute = (x: 0, y: 0, z: 0)
    private var _buttonMask: NSEvent.ButtonMask = []
    private var _tilt = NSPoint.zero
    private var _tangentialPressure: Float = 0
    private var _deviceID = 0, _tabletID = 0, _systemTabletID = 0, _vendorID = 0
    private var _pointingDeviceID = 0, _pointingDeviceSerialNumber = 0, _vendorPointingDeviceType = 0, _capabilityMask = 0
    private var _pointingDeviceType: NSEvent.PointingDeviceType = .unknown
    private var _isEnteringProximity = false
    private var _uniqueID: UInt64 = 0
    // Force Touch stage of a pressure event.
    private var _stage = 0
    private var _stageTransition: CGFloat = 0
    private var _pressureBehavior: NSEvent.PressureBehavior = .unknown

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
        MainActor.assumeIsolated {
            if let tag = trackingArea._legacyTag {
                e._trackingNumber = tag
                e._userData = trackingArea._legacyUserData
            }
        }
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
                                       deltaX: CGFloat = 0, deltaY: CGFloat = 0, phase: NSEvent.Phase = [], pressure: Float = 0,
                                       stage: Int = 0, stageTransition: CGFloat = 0) -> NSEvent {
        let e = NSEvent(type: type, location: location, modifierFlags: modifierFlags, timestamp: timestamp, windowNumber: windowNumber)
        e._magnification = magnification
        e._rotation = rotation
        e._deltaX = deltaX
        e._deltaY = deltaY
        e._phase = phase
        e._pressure = pressure
        e._stage = stage
        e._stageTransition = stageTransition
        if type == .pressure { e._pressureBehavior = .primaryDefault }
        return e
    }

    /// Backend helper: what a pen or tablet reported with a mouse or tablet event (Windows
    /// pointer messages fill it; the other backends report no tablets yet).
    internal func _setTabletFields(absolute: (x: Int, y: Int, z: Int) = (0, 0, 0), buttonMask: NSEvent.ButtonMask = [], tilt: NSPoint = .zero,
                                   tangentialPressure: Float = 0, deviceID: Int = 0, pointingDeviceType: NSEvent.PointingDeviceType = .unknown,
                                   pointingDeviceID: Int = 0, uniqueID: UInt64 = 0, isEnteringProximity: Bool = false) {
        _absolute = absolute; _buttonMask = buttonMask; _tilt = tilt; _tangentialPressure = tangentialPressure
        _deviceID = deviceID; _pointingDeviceType = pointingDeviceType; _pointingDeviceID = pointingDeviceID
        _uniqueID = uniqueID; _isEnteringProximity = isEnteringProximity
    }

    // MARK: Validity of type-specific members
    //
    // AppKit raises NSInternalInconsistencyException ("Invalid message sent to event") when a
    // member is read from an event of the wrong type; the port stops the same way.

    private var _isMouseOrTablet: Bool {
        switch _type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
             .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .tabletPoint, .tabletProximity:
            return true
        default: return false
        }
    }
    private var _isTouchEvent: Bool {
        switch _type {
        case .gesture, .magnify, .swipe, .rotate, .beginGesture, .endGesture, .smartMagnify, .directTouch, .pressure: return true
        default: return false
        }
    }
    private var _isKey: Bool { _type == .keyDown || _type == .keyUp }
    private func _require(_ valid: Bool, _ member: String = #function) {
        precondition(valid, "Invalid message sent to event \"\(description)\" (\(member))")
    }

    // MARK: Event monitors (addLocalMonitorForEvents / addGlobalMonitorForEvents)

    /// A monitor token, the opaque object the add calls return (AppKit's
    /// _NSLocalEventObserver / _NSGlobalEventObserver).
    internal final class _Monitor: NSObject {
        let mask: NSEvent.EventTypeMask
        let local: ((NSEvent) -> NSEvent?)?
        let global: ((NSEvent) -> Void)?
        init(mask: NSEvent.EventTypeMask, local: ((NSEvent) -> NSEvent?)?, global: ((NSEvent) -> Void)?) {
            self.mask = mask; self.local = local; self.global = global
        }
    }
    nonisolated(unsafe) private static var _localMonitors: [_Monitor] = []
    nonisolated(unsafe) private static var _globalMonitors: [_Monitor] = []

    /// Runs the local monitors, in the order they were added, on an event NSApplication is
    /// about to dispatch: each sees what the one before returned; nil stops the event.
    internal static func _runLocalMonitors(_ event: NSEvent) -> NSEvent? {
        var current = event
        for m in _localMonitors where m.mask.contains(EventTypeMask(type: current.type)) {
            // A monitor removed by an earlier one in this pass is not called.
            guard _localMonitors.contains(where: { $0 === m }) else { continue }
            guard let next = m.local?(current) else { return nil }
            current = next
        }
        return current
    }

    /// An event the backend saw going to another application.
    internal static func _deliverGlobal(_ event: NSEvent) {
        for m in _globalMonitors where m.mask.contains(EventTypeMask(type: event.type)) && _globalMonitors.contains(where: { $0 === m }) {
            m.global?(event)
        }
    }

    private static func _updateGlobalMonitoring() {
        let mask = _globalMonitors.reduce(EventTypeMask()) { $0.union($1.mask) }
        var handler: (@MainActor (NSEvent) -> Void)? = nil
        if !mask.isEmpty { handler = { (event: NSEvent) in NSEvent._deliverGlobal(event) } }
        MainActor.assumeIsolated { Platform.backend.setGlobalEventMonitoring(mask: mask, handler: handler) }
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
    public init?(cgEvent: CGEvent) { appleOnlyUnavailable("NSEvent.init(cgEvent:) — Quartz event services are macOS-only; the port's CGEvent carries no event record") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/init(eventref:)
    public init?(eventRef: UnsafeRawPointer) { appleOnlyUnavailable("NSEvent.init(eventRef:) — Carbon EventRef is macOS-only") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/absolutex
    open var absoluteX: Int { _require(_isMouseOrTablet); return _absolute.x }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/absolutey
    open var absoluteY: Int { _require(_isMouseOrTablet); return _absolute.y }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/absolutez
    open var absoluteZ: Int { _require(_isMouseOrTablet); return _absolute.z }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)
    /// The handler sees events the platform reports going to other applications (Windows:
    /// low-level mouse and keyboard hooks; the host backend's test hook). X11 and Wayland
    /// do not show other clients' input, so there the monitor exists but is never called,
    /// as on macOS for key events without accessibility trust.
    public class func addGlobalMonitorForEvents(matching mask: NSEvent.EventTypeMask, handler block: @escaping (NSEvent) -> Void) -> Any? {
        let m = _Monitor(mask: mask, local: nil, global: block)
        _globalMonitors.append(m)
        _updateGlobalMonitoring()
        return m
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents(matching:handler:)
    /// The handler runs inside `NSApplication.sendEvent(_:)` before dispatch, in the order
    /// monitors were added; returning nil drops the event, returning another event
    /// dispatches that one instead (macOS 15 behaviour, probed).
    public class func addLocalMonitorForEvents(matching mask: NSEvent.EventTypeMask, handler block: @escaping (NSEvent) -> NSEvent?) -> Any? {
        let m = _Monitor(mask: mask, local: block, global: nil)
        _localMonitors.append(m)
        return m
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/alltouches()
    @available(macOS 10.12, *)
    /// Gesture events only. The backends deliver gestures without per-finger touches, so the set is empty.
    open func allTouches() -> Set<NSTouch> { _require(_isTouchEvent); return [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/associatedeventsmask
    @available(macOS 10.10, *)
    /// For a mouse button event, the down, up and dragged types of its button (macOS: 70 for
    /// a left-button event); the pressure events of a Force Touch click carry none here.
    open var associatedEventsMask: NSEvent.EventTypeMask {
        _require(_isMouseOrTablet || _type == .pressure)
        switch _type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged: return [.leftMouseDown, .leftMouseUp, .leftMouseDragged]
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged: return [.rightMouseDown, .rightMouseUp, .rightMouseDragged]
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged: return [.otherMouseDown, .otherMouseUp, .otherMouseDragged]
        default: return []
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/buttonmask
    open var buttonMask: NSEvent.ButtonMask { _require(_isMouseOrTablet); return _buttonMask }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/buttonnumber
    open var buttonNumber: Int { _buttonNumber }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/capabilitymask
    open var capabilityMask: Int { _require(_isMouseOrTablet); return _capabilityMask }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/cgevent
    open var cgEvent: CGEvent? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/characters
    open var characters: String? { _characters }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/characters(byapplyingmodifiers:)
    @available(macOS 10.15, *)
    /// The characters the key would type with `modifiers` held, from the current keyboard
    /// layout (the platform's translation; the host backend models a US layout). Function
    /// and control keys give back their own characters. Command does not change the
    /// characters; Option selects the layout's alternate level (AltGr on Windows and Linux);
    /// Control gives the control character.
    open func characters(byApplyingModifiers modifiers: NSEvent.ModifierFlags) -> String? {
        _require(_isKey)
        if let plain = _charactersIgnoringModifiers, plain.unicodeScalars.count == 1, let v = plain.unicodeScalars.first?.value,
           v < 0x20 || v == 0x7F || (0xF700...0xF8FF).contains(v) {
            return plain
        }
        let code = _keyCode
        let flags = modifiers.intersection([.shift, .option, .control, .capsLock])
        return MainActor.assumeIsolated { Platform.backend.characters(forKeyCode: code, modifierFlags: flags) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/charactersignoringmodifiers
    open var charactersIgnoringModifiers: String? { _charactersIgnoringModifiers }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/clickcount
    open var clickCount: Int { _clickCount }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/coalescedtouches(for:)
    @available(macOS 10.12, *)
    /// Gesture events only; no touches are reported (see `allTouches()`).
    open func coalescedTouches(for touch: NSTouch) -> [NSTouch] { _require(_isTouchEvent); return [] }
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
    open var deviceID: Int { _require(_isMouseOrTablet); return _deviceID }
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
    static public var foreverDuration: TimeInterval { .greatestFiniteMagnitude }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/hasprecisescrollingdeltas
    open var hasPreciseScrollingDeltas: Bool { _hasPreciseScrollingDeltas }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/isarepeat
    open var isARepeat: Bool { _isARepeat }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/isdirectioninvertedfromdevice
    open var isDirectionInvertedFromDevice: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/isenteringproximity
    open var isEnteringProximity: Bool { _require(_isMouseOrTablet); return _isEnteringProximity }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/ismousecoalescingenabled
    /// Stored. The backends deliver each move the platform reports (Windows and X11 coalesce
    /// moves themselves); false is what macOS 15 reports for a process that has not changed it.
    class public var isMouseCoalescingEnabled: Bool {
        get { _isMouseCoalescingEnabled }
        set { _isMouseCoalescingEnabled = newValue }
    }
    nonisolated(unsafe) private static var _isMouseCoalescingEnabled = false
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
    open var pointingDeviceID: Int { _require(_isMouseOrTablet); return _pointingDeviceID }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/pointingdeviceserialnumber
    open var pointingDeviceSerialNumber: Int { _require(_isMouseOrTablet); return _pointingDeviceSerialNumber }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/pointingdevicetype
    open var pointingDeviceType: NSEvent.PointingDeviceType { _require(_isMouseOrTablet); return _pointingDeviceType }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/pressedmousebuttons
    class public var pressedMouseButtons: Int { _pressedMouseButtons }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/pressure
    open var pressure: Float { _pressure }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/pressurebehavior
    @available(macOS 10.11, *)
    /// Pressure events only (macOS raises for others).
    open var pressureBehavior: NSEvent.PressureBehavior { _require(_type == .pressure); return _pressureBehavior }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/removemonitor(_:)
    /// Removing a monitor twice, or something that is not a monitor, does nothing (macOS).
    public class func removeMonitor(_ eventMonitor: Any) {
        guard let m = eventMonitor as? _Monitor else { return }
        if m.global != nil {
            _globalMonitors.removeAll { $0 === m }
            _updateGlobalMonitoring()
        } else {
            _localMonitors.removeAll { $0 === m }
        }
    }
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
    /// Pressure events only.
    open var stage: Int { _require(_type == .pressure); return _stage }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/stagetransition
    @available(macOS 10.10, *)
    /// Pressure events only.
    open var stageTransition: CGFloat { _require(_type == .pressure); return _stageTransition }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/startperiodicevents(afterdelay:withperiod:)
    /// Posts `.periodic` events to the application's queue after `delay`, then every
    /// `period`, until `stopPeriodicEvents()`. Starting twice in a thread is an error (macOS
    /// raises).
    public class func startPeriodicEvents(afterDelay delay: TimeInterval, withPeriod period: TimeInterval) {
        precondition(_periodicTimer == nil, "NSEvent.startPeriodicEvents: periodic events are already being generated")
        let timer = Timer(fire: Date(timeIntervalSinceNow: delay), interval: period, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let app = NSApplication._shared, let e = NSEvent.otherEvent(with: .periodic, location: NSEvent.mouseLocation, modifierFlags: NSEvent._currentModifierFlags,
                                                                                   timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) else { return }
                app.postEvent(e, atStart: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        _periodicTimer = timer
    }
    nonisolated(unsafe) private static var _periodicTimer: Timer?
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/stopperiodicevents()
    public class func stopPeriodicEvents() { _periodicTimer?.invalidate(); _periodicTimer = nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/subtype
    open var subtype: NSEvent.EventSubtype { _subtype }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/systemtabletid
    open var systemTabletID: Int { _require(_isMouseOrTablet); return _systemTabletID }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/tabletid
    open var tabletID: Int { _require(_isMouseOrTablet); return _tabletID }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/tangentialpressure
    open var tangentialPressure: Float { _require(_isMouseOrTablet); return _tangentialPressure }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/tilt
    open var tilt: NSPoint { _require(_isMouseOrTablet); return _tilt }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/timestamp
    open var timestamp: TimeInterval { _timestamp }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/touches(for:)
    @available(macOS 10.12, *)
    open func touches(for view: NSView) -> Set<NSTouch> { _require(_isTouchEvent); return [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/touches(matching:in:)
    open func touches(matching phase: NSTouch.Phase, in view: NSView?) -> Set<NSTouch> { _require(_isTouchEvent); return [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/trackswipeevent(options:dampenamountthresholdmin:max:usinghandler:)
    open func trackSwipeEvent(options: NSEvent.SwipeTrackingOptions = [], dampenAmountThresholdMin minDampenThreshold: CGFloat, max maxDampenThreshold: CGFloat, usingHandler trackingHandler: @escaping (CGFloat, NSEvent.Phase, Bool, UnsafeMutablePointer<ObjCBool>) -> Void) { unimplemented("NSEvent.trackSwipeEvent — the port reports isSwipeTrackingFromScrollEventsEnabled = false (no fluid-swipe scroll phases from the backends), so apps fall back to swipe(with:)") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/trackingarea
    open var trackingArea: NSTrackingArea? { _trackingArea }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/trackingnumber
    open var trackingNumber: Int { _trackingNumber }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/type
    open var type: NSEvent.EventType { _type }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/uniqueid
    open var uniqueID: UInt64 { _require(_isMouseOrTablet); return _uniqueID }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/userdata
    open var userData: UnsafeMutableRawPointer? { _userData }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/vendordefined
    /// Three vendor words, zero unless a tablet driver reports them (as on macOS).
    open var vendorDefined: Any { _require(_isMouseOrTablet); return [NSNumber(value: 0), NSNumber(value: 0), NSNumber(value: 0)] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/vendorid
    open var vendorID: Int { _require(_isMouseOrTablet); return _vendorID }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/vendorpointingdevicetype
    open var vendorPointingDeviceType: Int { _require(_isMouseOrTablet); return _vendorPointingDeviceType }
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

extension NSEvent.EventTypeMask {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsevent/eventtypemask/init(type:)
    public init(type: NSEvent.EventType) { self.init(rawValue: 1 << UInt64(type.rawValue)) }
}
