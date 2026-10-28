// CATransaction: groups layer property changes and parameterises their implicit animations.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/catransaction
@MainActor
open class CATransaction: NSObject {
    struct Frame {
        var duration: CFTimeInterval = 0.25
        var timingFunction: CAMediaTimingFunction? = nil
        var disableActions = false
        var completion: (() -> Void)? = nil
        var values: [String: Any] = [:]
        var pendingAnimations = 0
    }

    static var stack: [Frame] = []
    static var implicit: Frame? = nil

    static var current: Frame {
        get { stack.last ?? implicit ?? Frame() }
        set {
            if !stack.isEmpty { stack[stack.count - 1] = newValue } else { implicit = newValue }
        }
    }

    public class func begin() {
        var f = stack.last ?? implicit ?? Frame()
        f.completion = nil
        f.pendingAnimations = 0
        f.values = [:]
        stack.append(f)
    }

    public class func commit() {
        guard let f = stack.popLast() else { return }
        finish(f)
    }

    /// Commits the implicit transaction, if any.
    public class func flush() {
        if let f = implicit { implicit = nil; finish(f) }
    }

    private static func finish(_ f: Frame) {
        if let c = f.completion {
            if f.pendingAnimations == 0 { c() } else { CATransactionCompletion.pending.append((f.pendingAnimations, c)) }
        }
    }

    public class func lock() {}
    public class func unlock() {}

    public class func animationDuration() -> CFTimeInterval { current.duration }
    public class func setAnimationDuration(_ dur: CFTimeInterval) { current.duration = dur }
    public class func animationTimingFunction() -> CAMediaTimingFunction? { current.timingFunction }
    public class func setAnimationTimingFunction(_ function: CAMediaTimingFunction?) { current.timingFunction = function }
    public class func disableActions() -> Bool { current.disableActions }
    public class func setDisableActions(_ flag: Bool) { current.disableActions = flag }
    public class func completionBlock() -> (() -> Void)? { current.completion }
    public class func setCompletionBlock(_ block: (() -> Void)?) { current.completion = block }

    #if canImport(ObjectiveC)
    public override class func value(forKey key: String) -> Any? { MainActor.assumeIsolated { _value(forKey: key) } }
    public override class func setValue(_ anObject: Any?, forKey key: String) { MainActor.assumeIsolated { _setValue(anObject, forKey: key) } }
    #else
    public class func value(forKey key: String) -> Any? { _value(forKey: key) }
    public class func setValue(_ anObject: Any?, forKey key: String) { _setValue(anObject, forKey: key) }
    #endif

    static func _value(forKey key: String) -> Any? {
        switch key {
        case kCATransactionAnimationDuration: return current.duration
        case kCATransactionDisableActions: return current.disableActions
        case kCATransactionAnimationTimingFunction: return current.timingFunction
        case kCATransactionCompletionBlock: return current.completion
        default: return current.values[key]
        }
    }

    static func _setValue(_ anObject: Any?, forKey key: String) {
        switch key {
        case kCATransactionAnimationDuration: if let d = anObject as? CFTimeInterval { current.duration = d }
        case kCATransactionDisableActions: if let b = anObject as? Bool { current.disableActions = b }
        case kCATransactionAnimationTimingFunction: current.timingFunction = anObject as? CAMediaTimingFunction
        case kCATransactionCompletionBlock: current.completion = anObject as? () -> Void
        default: current.values[key] = anObject
        }
    }

    /// Records that an animation was created under the current transaction so the
    /// completion block waits for it.
    static func noteAnimationAdded() -> Bool {
        guard current.completion != nil || !stack.isEmpty else { return false }
        current.pendingAnimations += 1
        return true
    }
}

public let kCATransactionAnimationDuration = "animationDuration"
public let kCATransactionDisableActions = "disableActions"
public let kCATransactionAnimationTimingFunction = "animationTimingFunction"
public let kCATransactionCompletionBlock = "completionBlock"

/// Completion blocks of committed transactions that still wait on running animations.
@MainActor
enum CATransactionCompletion {
    static var pending: [(remaining: Int, block: () -> Void)] = []

    /// Called when an animation created under a transaction finishes.
    static func animationFinished() {
        guard !pending.isEmpty else { return }
        pending[0].remaining -= 1
        if pending[0].remaining <= 0 {
            let b = pending.removeFirst().block
            b()
        }
    }
}
