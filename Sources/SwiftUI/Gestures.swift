// Gestures: `Gesture`, the primitive gestures (tap, long press, drag, magnify, rotate)
// and the `.gesture`, `.highPriorityGesture` and `.simultaneousGesture` modifiers. Each
// primitive installs an AppKit gesture recognizer on the view that hosts the modified
// content; `onChanged`/`onEnded` chain callbacks on the recognizer's state changes.

import Foundation
import AppKit

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/gesture
public protocol Gesture {
    associatedtype Value
    associatedtype Body: Gesture
    var body: Self.Body { get }
}

extension Never: Gesture {
    public typealias Value = Never
}

/// Gestures the hosting layer knows how to install on a view.
protocol _PrimitiveGesture: Gesture {
    /// Creates the recognizer for `view` and wires `changed`/`ended` to its states.
    @MainActor func _install(on view: NSView, changed: @escaping (Value) -> Void, ended: @escaping (Value) -> Void) -> NSGestureRecognizer
}

extension Gesture {
    @MainActor func _installAny(on view: NSView, changed: @escaping (Value) -> Void, ended: @escaping (Value) -> Void) -> NSGestureRecognizer? {
        if let p = self as? any _PrimitiveGesture {
            func open<P: _PrimitiveGesture>(_ p: P) -> NSGestureRecognizer? {
                p._install(on: view, changed: { changed($0 as! Value) }, ended: { ended($0 as! Value) })
            }
            return open(p)
        }
        if Body.self == Never.self { return nil }
        return body._installAny(on: view, changed: { changed($0 as! Value) }, ended: { ended($0 as! Value) })
    }
}

// MARK: Callbacks

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/_changedgesture
public struct _ChangedGesture<Content: Gesture>: Gesture, _PrimitiveGesture {
    public typealias Value = Content.Value
    public typealias Body = Never
    let content: Content
    let action: (Value) -> Void
    public var body: Never { fatalError() }
    @MainActor func _install(on view: NSView, changed: @escaping (Value) -> Void, ended: @escaping (Value) -> Void) -> NSGestureRecognizer {
        content._installAny(on: view, changed: { [action] v in action(v); changed(v) }, ended: ended) ?? NSGestureRecognizer(target: nil, action: nil)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/_endedgesture
public struct _EndedGesture<Content: Gesture>: Gesture, _PrimitiveGesture {
    public typealias Value = Content.Value
    public typealias Body = Never
    let content: Content
    let action: (Value) -> Void
    public var body: Never { fatalError() }
    @MainActor func _install(on view: NSView, changed: @escaping (Value) -> Void, ended: @escaping (Value) -> Void) -> NSGestureRecognizer {
        content._installAny(on: view, changed: changed, ended: { [action] v in action(v); ended(v) }) ?? NSGestureRecognizer(target: nil, action: nil)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/_mapgesture
public struct _MapGesture<Content: Gesture, Value>: Gesture, _PrimitiveGesture {
    public typealias Body = Never
    let content: Content
    let transform: (Content.Value) -> Value
    public var body: Never { fatalError() }
    @MainActor func _install(on view: NSView, changed: @escaping (Value) -> Void, ended: @escaping (Value) -> Void) -> NSGestureRecognizer {
        content._installAny(on: view, changed: { [transform] v in changed(transform(v)) }, ended: { [transform] v in ended(transform(v)) }) ?? NSGestureRecognizer(target: nil, action: nil)
    }
}

extension Gesture {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/gesture/onchanged(_:)
    public func onChanged(_ action: @escaping (Self.Value) -> Void) -> _ChangedGesture<Self> { _ChangedGesture(content: self, action: action) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/gesture/onended(_:)
    public func onEnded(_ action: @escaping (Self.Value) -> Void) -> _EndedGesture<Self> { _EndedGesture(content: self, action: action) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/gesture/map(_:)
    public func map<T>(_ body: @escaping (Self.Value) -> T) -> _MapGesture<Self, T> { _MapGesture(content: self, transform: body) }
}

// MARK: Primitive gestures

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/tapgesture
public struct TapGesture: Gesture, _PrimitiveGesture {
    public typealias Value = Void
    public typealias Body = Never
    public var count: Int
    public init(count: Int = 1) { self.count = count }
    public var body: Never { fatalError() }
    @MainActor func _install(on view: NSView, changed: @escaping (Void) -> Void, ended: @escaping (Void) -> Void) -> NSGestureRecognizer {
        let r = NSClickGestureRecognizer(target: nil, action: nil)
        r.numberOfClicksRequired = count
        r._actionHandler = { r in if r.state == .ended { ended(()) } }
        return r
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/longpressgesture
public struct LongPressGesture: Gesture, _PrimitiveGesture {
    public typealias Value = Bool
    public typealias Body = Never
    public var minimumDuration: Double
    public var maximumDistance: CGFloat
    public init(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10) {
        self.minimumDuration = minimumDuration
        self.maximumDistance = maximumDistance
    }
    public var body: Never { fatalError() }
    @MainActor func _install(on view: NSView, changed: @escaping (Bool) -> Void, ended: @escaping (Bool) -> Void) -> NSGestureRecognizer {
        let r = NSPressGestureRecognizer(target: nil, action: nil)
        r.minimumPressDuration = minimumDuration
        r.allowableMovement = maximumDistance
        r._actionHandler = { r in
            switch r.state {
            case .began: changed(true); ended(true)      // the press is recognized once it lasts long enough
            default: break
            }
        }
        return r
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/draggesture
public struct DragGesture: Gesture, _PrimitiveGesture {
    public typealias Body = Never
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/draggesture/value
    public struct Value: Equatable, Sendable {
        public var time: Date
        public var location: CGPoint
        public var startLocation: CGPoint
        public var velocity: CGSize
        public var translation: CGSize { CGSize(width: location.x - startLocation.x, height: location.y - startLocation.y) }
        public var predictedEndLocation: CGPoint { CGPoint(x: location.x + velocity.width / 4, y: location.y + velocity.height / 4) }
        public var predictedEndTranslation: CGSize { CGSize(width: predictedEndLocation.x - startLocation.x, height: predictedEndLocation.y - startLocation.y) }
    }
    public var minimumDistance: CGFloat
    public var coordinateSpace: CoordinateSpace
    public init(minimumDistance: CGFloat = 10, coordinateSpace: CoordinateSpace = .local) {
        self.minimumDistance = minimumDistance
        self.coordinateSpace = coordinateSpace
    }
    public var body: Never { fatalError() }
    @MainActor func _install(on view: NSView, changed: @escaping (Value) -> Void, ended: @escaping (Value) -> Void) -> NSGestureRecognizer {
        let r = NSPanGestureRecognizer(target: nil, action: nil)
        var start = CGPoint.zero
        let space = coordinateSpace
        r._actionHandler = { [weak view] r in
            guard let view, let pan = r as? NSPanGestureRecognizer else { return }
            let local = pan.location(in: view)
            let location: CGPoint
            switch space {
            case .global: location = view.convert(local, to: nil)
            default: location = local
            }
            let v = pan.velocity(in: view)
            if pan.state == .began {
                let t = pan.translation(in: view)
                start = CGPoint(x: location.x - t.x, y: location.y - t.y)
            }
            let value = Value(time: Date(), location: location, startLocation: start, velocity: CGSize(width: v.x, height: v.y))
            switch pan.state {
            case .began, .changed: changed(value)
            case .ended: ended(value)
            case .cancelled: ended(value)
            default: break
            }
        }
        return r
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/magnifygesture
@available(macOS 14.0, *)
public struct MagnifyGesture: Gesture, _PrimitiveGesture {
    public typealias Body = Never
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/magnifygesture/value
    public struct Value: Equatable, Sendable {
        public var time: Date
        public var magnification: CGFloat
        public var velocity: CGFloat
        public var startAnchor: UnitPoint
        public var startLocation: CGPoint
    }
    public var minimumScaleDelta: CGFloat
    public init(minimumScaleDelta: CGFloat = 0.01) { self.minimumScaleDelta = minimumScaleDelta }
    public var body: Never { fatalError() }
    @MainActor func _install(on view: NSView, changed: @escaping (Value) -> Void, ended: @escaping (Value) -> Void) -> NSGestureRecognizer {
        let r = NSMagnificationGestureRecognizer(target: nil, action: nil)
        var start = CGPoint.zero, anchor = UnitPoint.center, last: (CGFloat, Date)? = nil
        r._actionHandler = { [weak view] r in
            guard let view, let m = r as? NSMagnificationGestureRecognizer else { return }
            let scale = 1 + m.magnification
            let now = Date()
            if m.state == .began {
                start = m.location(in: view)
                let b = view.bounds
                anchor = UnitPoint(x: b.width > 0 ? start.x / b.width : 0.5, y: b.height > 0 ? start.y / b.height : 0.5)
                last = nil
            }
            var velocity: CGFloat = 0
            if let (s, t) = last, now.timeIntervalSince(t) > 0 { velocity = (scale - s) / now.timeIntervalSince(t) }
            last = (scale, now)
            let value = Value(time: now, magnification: scale, velocity: velocity, startAnchor: anchor, startLocation: start)
            switch m.state {
            case .began, .changed: changed(value)
            case .ended, .cancelled: ended(value)
            default: break
            }
        }
        return r
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/magnificationgesture
public struct MagnificationGesture: Gesture, _PrimitiveGesture {
    public typealias Value = CGFloat
    public typealias Body = Never
    public var minimumScaleDelta: CGFloat
    public init(minimumScaleDelta: CGFloat = 0.01) { self.minimumScaleDelta = minimumScaleDelta }
    public var body: Never { fatalError() }
    @MainActor func _install(on view: NSView, changed: @escaping (CGFloat) -> Void, ended: @escaping (CGFloat) -> Void) -> NSGestureRecognizer {
        let r = NSMagnificationGestureRecognizer(target: nil, action: nil)
        r._actionHandler = { r in
            guard let m = r as? NSMagnificationGestureRecognizer else { return }
            switch m.state {
            case .began, .changed: changed(1 + m.magnification)
            case .ended, .cancelled: ended(1 + m.magnification)
            default: break
            }
        }
        return r
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/rotategesture
@available(macOS 14.0, *)
public struct RotateGesture: Gesture, _PrimitiveGesture {
    public typealias Body = Never
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/rotategesture/value
    public struct Value: Equatable, Sendable {
        public var time: Date
        public var rotation: Angle
        public var velocity: Angle
        public var startAnchor: UnitPoint
        public var startLocation: CGPoint
    }
    public var minimumAngleDelta: Angle
    public init(minimumAngleDelta: Angle = .degrees(1)) { self.minimumAngleDelta = minimumAngleDelta }
    public var body: Never { fatalError() }
    @MainActor func _install(on view: NSView, changed: @escaping (Value) -> Void, ended: @escaping (Value) -> Void) -> NSGestureRecognizer {
        let r = NSRotationGestureRecognizer(target: nil, action: nil)
        var start = CGPoint.zero, anchor = UnitPoint.center, last: (Double, Date)? = nil
        r._actionHandler = { [weak view] r in
            guard let view, let g = r as? NSRotationGestureRecognizer else { return }
            // SwiftUI's angle is clockwise-positive in its y-down space; AppKit's rotation is counterclockwise.
            let radians = -Double(g.rotation)
            let now = Date()
            if g.state == .began {
                start = g.location(in: view)
                let b = view.bounds
                anchor = UnitPoint(x: b.width > 0 ? start.x / b.width : 0.5, y: b.height > 0 ? start.y / b.height : 0.5)
                last = nil
            }
            var velocity = 0.0
            if let (s, t) = last, now.timeIntervalSince(t) > 0 { velocity = (radians - s) / now.timeIntervalSince(t) }
            last = (radians, now)
            let value = Value(time: now, rotation: .radians(radians), velocity: .radians(velocity), startAnchor: anchor, startLocation: start)
            switch g.state {
            case .began, .changed: changed(value)
            case .ended, .cancelled: ended(value)
            default: break
            }
        }
        return r
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/rotationgesture
public struct RotationGesture: Gesture, _PrimitiveGesture {
    public typealias Value = Angle
    public typealias Body = Never
    public var minimumAngleDelta: Angle
    public init(minimumAngleDelta: Angle = .degrees(1)) { self.minimumAngleDelta = minimumAngleDelta }
    public var body: Never { fatalError() }
    @MainActor func _install(on view: NSView, changed: @escaping (Angle) -> Void, ended: @escaping (Angle) -> Void) -> NSGestureRecognizer {
        let r = NSRotationGestureRecognizer(target: nil, action: nil)
        r._actionHandler = { r in
            guard let g = r as? NSRotationGestureRecognizer else { return }
            let angle = Angle.radians(-Double(g.rotation))
            switch g.state {
            case .began, .changed: changed(angle)
            case .ended, .cancelled: ended(angle)
            default: break
            }
        }
        return r
    }
}

// MARK: Modifiers

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/gesturemask
public struct GestureMask: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let none = GestureMask([])
    public static let gesture = GestureMask(rawValue: 1)
    public static let subviews = GestureMask(rawValue: 2)
    public static let all: GestureMask = [.gesture, .subviews]
}

/// A gesture the decoration view installs: type-erased to its installer.
struct _GestureInstaller {
    let install: @MainActor (NSView) -> NSGestureRecognizer?
    let mask: GestureMask
    init<G: Gesture>(_ gesture: G, mask: GestureMask) {
        install = { view in gesture._installAny(on: view, changed: { _ in }, ended: { _ in }) }
        self.mask = mask
    }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/gesture(_:including:)
    public func gesture<T: Gesture>(_ gesture: T, including mask: GestureMask = .all) -> some View {
        var d = _Decorated(content: self)
        d.style.gestures = [_GestureInstaller(gesture, mask: mask)]
        return d
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/highprioritygesture(_:including:)
    public func highPriorityGesture<T: Gesture>(_ gesture: T, including mask: GestureMask = .all) -> some View {
        var d = _Decorated(content: self)
        d.style.gestures = [_GestureInstaller(gesture, mask: mask)]
        d.style.gesturesDelayEvents = true
        return d
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/simultaneousgesture(_:including:)
    public func simultaneousGesture<T: Gesture>(_ gesture: T, including mask: GestureMask = .all) -> some View {
        self.gesture(gesture, including: mask)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/onlongpressgesture(minimumduration:maximumdistance:perform:onpressingchanged:)
    public func onLongPressGesture(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10, perform action: @escaping () -> Void, onPressingChanged: ((Bool) -> Void)? = nil) -> some View {
        var d = _Decorated(content: self)
        d.style.gestures = [_GestureInstaller(LongPressGesture(minimumDuration: minimumDuration, maximumDistance: maximumDistance).onEnded { _ in action() }, mask: .all)]
        d.style.pressingChanged = onPressingChanged
        return d
    }
}
