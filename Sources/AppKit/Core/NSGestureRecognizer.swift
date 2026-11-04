// NSGestureRecognizer: the base class of AppKit's gesture recognizers. A recognizer
// attached to a view receives the mouse and gesture events the window routes to that
// view (and to its subviews: the window walks the hit view's superview chain), tracks
// them, and reports through `state`: every change to began, changed, ended or
// cancelled sends the action to the target, as AppKit does. The `delays*` switches are
// stored and honoured for the primary mouse button only in this port; views receive
// the events as well, which is AppKit's default behaviour.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgesturerecognizer
@available(macOS 10.10, *)
@MainActor open class NSGestureRecognizer: NSObject, NSCoding {
    private var _target: AnyObject?
    private var _action: Selector?
    private var _state: NSGestureRecognizer.State = .possible
    private weak var _view: NSView?
    private var _enabled = true
    private weak var _delegate: (any NSGestureRecognizerDelegate)?
    private var _delaysPrimary = false, _delaysSecondary = false, _delaysOther = false, _delaysKey = false, _delaysMagnification = false, _delaysRotation = false
    private var _allowedTouchTypes: NSTouch.TouchTypeMask = [.direct, .indirect]
    private var _pressureConfiguration: NSPressureConfiguration?
    private var _name: String?
    /// The last event's location in the window, for `location(in:)`.
    internal var _locationInWindow: NSPoint = .zero
    internal var _modifierFlags: NSEvent.ModifierFlags = []
    /// Additive hook for hosts without a selector target (SwiftUI): called on every state
    /// change that would send the action, before the action itself.
    public var _actionHandler: ((NSGestureRecognizer) -> Void)?

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgesturerecognizer/init(target:action:)
    @MainActor public init(target: Any?, action: Selector?) {
        _target = target as AnyObject?
        _action = action
        super.init()
    }
    @MainActor public required init?(coder: NSCoder) { nil }
    open func encode(with coder: NSCoder) { }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgesturerecognizer/target
    @MainActor open var target: AnyObject? {
        get { _target }
        set { _target = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgesturerecognizer/action
    @MainActor open var action: Selector? {
        get { _action }
        set { _action = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgesturerecognizer/view
    @MainActor open var view: NSView? { _view }
    internal func _setView(_ view: NSView?) { _view = view }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgesturerecognizer/isenabled
    @MainActor open var isEnabled: Bool {
        get { _enabled }
        set {
            _enabled = newValue
            if !newValue, _state == .began || _state == .changed { state = .cancelled }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgesturerecognizer/delegate
    @MainActor open var delegate: (any NSGestureRecognizerDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgesturerecognizer/name
    @available(macOS 26.0, *)
    @MainActor open var name: String? {
        get { _name }
        set { _name = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgesturerecognizer/modifierflags
    @available(macOS 26.0, *)
    @MainActor open var modifierFlags: NSEvent.ModifierFlags { _modifierFlags }

    /// The recognizer's state. Setting it to began, changed, ended or cancelled sends the
    /// action; ended, cancelled and failed reset the recognizer afterwards.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgesturerecognizer/state
    @MainActor open var state: NSGestureRecognizer.State {
        get { _state }
        set {
            let old = _state
            _state = newValue
            switch newValue {
            case .began, .changed, .ended, .cancelled:
                if newValue != old || newValue == .changed { _sendAction() }
            default: break
            }
            if newValue == .ended || newValue == .cancelled || newValue == .failed {
                // AppKit resets the recognizer once the action has run for the final state.
                _state = .possible
                reset()
            }
        }
    }

    private func _sendAction() {
        _actionHandler?(self)
        guard let action = _action else { return }
        if let t = _target {
            _ = ActionRegistry.perform(action, on: t, with: self)
        } else {
            _ = NSApplication.shared.sendAction(action, to: nil, from: self)
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgesturerecognizer/location(in:)
    @MainActor open func location(in view: NSView?) -> NSPoint {
        guard let view else { return _locationInWindow }
        return view.convert(_locationInWindow, from: nil)
    }

    /// Resets any state a subclass tracks. Called after a gesture ends, is cancelled or fails.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgesturerecognizer/reset()
    @MainActor open func reset() { }

    // MARK: Delays and prevention

    @MainActor open var delaysPrimaryMouseButtonEvents: Bool { get { _delaysPrimary } set { _delaysPrimary = newValue } }
    @MainActor open var delaysSecondaryMouseButtonEvents: Bool { get { _delaysSecondary } set { _delaysSecondary = newValue } }
    @MainActor open var delaysOtherMouseButtonEvents: Bool { get { _delaysOther } set { _delaysOther = newValue } }
    @MainActor open var delaysKeyEvents: Bool { get { _delaysKey } set { _delaysKey = newValue } }
    @MainActor open var delaysMagnificationEvents: Bool { get { _delaysMagnification } set { _delaysMagnification = newValue } }
    @MainActor open var delaysRotationEvents: Bool { get { _delaysRotation } set { _delaysRotation = newValue } }
    @MainActor open func canBePrevented(by preventingGestureRecognizer: NSGestureRecognizer) -> Bool { true }
    @MainActor open func canPrevent(_ preventedGestureRecognizer: NSGestureRecognizer) -> Bool { true }
    @MainActor open func shouldBeRequiredToFail(by otherGestureRecognizer: NSGestureRecognizer) -> Bool { false }
    @MainActor open func shouldRequireFailure(of otherGestureRecognizer: NSGestureRecognizer) -> Bool { false }
    @available(macOS 10.12, *)
    @MainActor open var allowedTouchTypes: NSTouch.TouchTypeMask { get { _allowedTouchTypes } set { _allowedTouchTypes = newValue } }
    @available(macOS 10.11, *)
    @MainActor open var pressureConfiguration: NSPressureConfiguration {
        get { guard let c = _pressureConfiguration else { unimplemented() }; return c }   // no pressure-sensitive input on these platforms
        set { _pressureConfiguration = newValue }
    }

    // MARK: Event entry points (subclasses override; the base records the location)

    /// Feeds one event. Returns false when the recognizer refused it (disabled, or the
    /// delegate declined), so the window can skip it.
    @discardableResult
    internal func _receive(_ event: NSEvent) -> Bool {
        guard _enabled else { return false }
        if _state == .possible, let d = _delegate, !d.gestureRecognizer(self, shouldAttemptToRecognizeWith: event) { return false }
        _locationInWindow = event.locationInWindow
        _modifierFlags = event.modifierFlags
        switch event.type {
        case .leftMouseDown: mouseDown(with: event)
        case .leftMouseDragged: mouseDragged(with: event)
        case .leftMouseUp: mouseUp(with: event)
        case .rightMouseDown: rightMouseDown(with: event)
        case .rightMouseDragged: rightMouseDragged(with: event)
        case .rightMouseUp: rightMouseUp(with: event)
        case .otherMouseDown: otherMouseDown(with: event)
        case .otherMouseDragged: otherMouseDragged(with: event)
        case .otherMouseUp: otherMouseUp(with: event)
        case .magnify: magnify(with: event)
        case .rotate: rotate(with: event)
        case .pressure: pressureChange(with: event)
        case .keyDown: keyDown(with: event)
        case .keyUp: keyUp(with: event)
        case .flagsChanged: flagsChanged(with: event)
        case .tabletPoint: tabletPoint(with: event)
        case .beginGesture: _beginGesture(with: event)
        case .endGesture: _endGesture(with: event)
        default: break
        }
        return true
    }

    /// Whether this recognizer can move from possible to began (the delegate's veto).
    internal func _mayBegin() -> Bool {
        _delegate?.gestureRecognizerShouldBegin(self) ?? true
    }

    /// Whether a recognizer that was or is tracking wants the view not to see this event
    /// (`tracking` is the state before the event; the event that ends a gesture is withheld too).
    internal func _delays(_ event: NSEvent, tracking: Bool) -> Bool {
        guard tracking || _state == .began || _state == .changed else { return false }
        switch event.type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp: return _delaysPrimary
        case .rightMouseDown, .rightMouseDragged, .rightMouseUp: return _delaysSecondary
        case .otherMouseDown, .otherMouseDragged, .otherMouseUp: return _delaysOther
        case .magnify: return _delaysMagnification
        case .rotate: return _delaysRotation
        case .keyDown, .keyUp: return _delaysKey
        default: return false
        }
    }

    internal func _beginGesture(with event: NSEvent) { }
    internal func _endGesture(with event: NSEvent) { }

    @MainActor open func mouseDown(with event: NSEvent) { }
    @MainActor open func mouseDragged(with event: NSEvent) { }
    @MainActor open func mouseUp(with event: NSEvent) { }
    @available(macOS 26.0, *)
    @MainActor open func mouseCancelled(with event: NSEvent) { if state == .began || state == .changed { state = .cancelled } }
    @MainActor open func rightMouseDown(with event: NSEvent) { }
    @MainActor open func rightMouseDragged(with event: NSEvent) { }
    @MainActor open func rightMouseUp(with event: NSEvent) { }
    @MainActor open func otherMouseDown(with event: NSEvent) { }
    @MainActor open func otherMouseDragged(with event: NSEvent) { }
    @MainActor open func otherMouseUp(with event: NSEvent) { }
    @MainActor open func magnify(with event: NSEvent) { }
    @MainActor open func rotate(with event: NSEvent) { }
    @MainActor open func pressureChange(with event: NSEvent) { }
    @MainActor open func keyDown(with event: NSEvent) { }
    @MainActor open func keyUp(with event: NSEvent) { }
    @MainActor open func flagsChanged(with event: NSEvent) { }
    @MainActor open func tabletPoint(with event: NSEvent) { }
    @available(macOS 10.12, *)
    @MainActor open func touchesBegan(with event: NSEvent) { }
    @available(macOS 10.12, *)
    @MainActor open func touchesMoved(with event: NSEvent) { }
    @available(macOS 10.12, *)
    @MainActor open func touchesEnded(with event: NSEvent) { }
    @available(macOS 10.12, *)
    @MainActor open func touchesCancelled(with event: NSEvent) { }
}

@available(macOS 10.10, *)
extension NSGestureRecognizer {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgesturerecognizer/state-swift.enum
    public enum State: Int, Sendable, Equatable, Hashable {
        case possible = 0
        case began = 1
        case changed = 2
        case ended = 3
        case cancelled = 4
        case failed = 5
        public static var recognized: NSGestureRecognizer.State { .ended }
    }
}

/// Mouse-button bookkeeping shared by the click, pan and press recognizers: AppKit's
/// `buttonMask` bit 0 is the primary button, bit 1 secondary, bit 2 the others.
@MainActor
internal enum _NSGestureButtons {
    static func mask(for event: NSEvent) -> Int {
        switch event.type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp: return 0x1
        case .rightMouseDown, .rightMouseDragged, .rightMouseUp: return 0x2
        case .otherMouseDown, .otherMouseDragged, .otherMouseUp: return 0x4
        default: return 0
        }
    }
    static func isDown(_ event: NSEvent) -> Bool { [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) }
    static func isDrag(_ event: NSEvent) -> Bool { [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(event.type) }
    static func isUp(_ event: NSEvent) -> Bool { [.leftMouseUp, .rightMouseUp, .otherMouseUp].contains(event.type) }
}
