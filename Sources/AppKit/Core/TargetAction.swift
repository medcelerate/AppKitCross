// Target/action without the Objective-C runtime.
//
// AppKit dispatches `Selector`s with objc_msgSend. Here a target receives an action in one
// of two ways: it adopts `NSSelectorHandling` and switches on the selector, or a closure
// is registered per selector with `NSObject.setActionHandler(for:_:)` (additive API; on
// macOS `#selector` values are ordinary `Selector`s and work the same way). NSResponder's
// `tryToPerform` consults both before walking to the next responder.

import Foundation

public protocol NSSelectorHandling: AnyObject {
    /// Return true when the action was handled.
    @MainActor func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool
}

@MainActor
enum ActionRegistry {
    private final class Entry {
        weak var object: AnyObject?
        var handlers: [Selector: (Any?) -> Void] = [:]
        init(_ object: AnyObject) { self.object = object }
    }
    private static var entries: [ObjectIdentifier: Entry] = [:]

    static func set(_ handler: ((Any?) -> Void)?, for selector: Selector, on object: AnyObject) {
        let id = ObjectIdentifier(object)
        if let e = entries[id], e.object !== object { entries[id] = nil }   // identifier reused
        if let handler {
            let e = entries[id] ?? Entry(object)
            e.handlers[selector] = handler
            entries[id] = e
        } else {
            entries[id]?.handlers[selector] = nil
        }
    }

    /// Whether `target` has a registered handler or declares selector handling. Objects that
    /// adopt `NSSelectorHandling` decide at call time, so they count as able.
    static func canPerform(_ action: Selector, on target: AnyObject) -> Bool {
        if let e = entries[ObjectIdentifier(target)], e.object === target, e.handlers[action] != nil { return true }
        return target is NSSelectorHandling
    }

    /// Delivers `action` to `target` alone (no responder-chain walk). True if handled.
    static func perform(_ action: Selector, on target: AnyObject, with sender: Any?) -> Bool {
        if let e = entries[ObjectIdentifier(target)], e.object === target, let h = e.handlers[action] {
            h(sender)
            return true
        }
        if let t = target as? NSSelectorHandling, t.performSelectorAction(action, with: sender) {
            return true
        }
        return false
    }
}

extension NSObject {
    /// Registers (or with nil removes) a closure that handles `selector` when this object
    /// is the target of an action or reached through the responder chain.
    @MainActor public func setActionHandler(for selector: Selector, _ handler: ((Any?) -> Void)?) {
        ActionRegistry.set(handler, for: selector, on: self)
    }
}
