// UndoManager for platforms whose Foundation lacks it (swift-corelibs-foundation on
// Windows and Linux). Apple's Foundation provides the real one on macOS, and this file
// compiles to nothing there. The API and semantics follow Foundation's `UndoManager`
// (`NSUndoManager`): closure-based registration, nested groups, grouping by event (an
// implicit group opened by the first registration of a run-loop cycle and closed at the
// end of it), the undo/redo stacks, action names and the notifications NSDocument
// listens to for its change count.
//
// Selector-based registration (`registerUndo(withTarget:selector:object:)`,
// `prepare(withInvocationTarget:)`) needs the Objective-C runtime and is unavailable.

#if !canImport(Darwin)
import Foundation
import Dispatch

extension Notification.Name {
    public static let NSUndoManagerCheckpoint = Notification.Name("NSUndoManagerCheckpointNotification")
    public static let NSUndoManagerWillUndoChange = Notification.Name("NSUndoManagerWillUndoChangeNotification")
    public static let NSUndoManagerWillRedoChange = Notification.Name("NSUndoManagerWillRedoChangeNotification")
    public static let NSUndoManagerDidUndoChange = Notification.Name("NSUndoManagerDidUndoChangeNotification")
    public static let NSUndoManagerDidRedoChange = Notification.Name("NSUndoManagerDidRedoChangeNotification")
    public static let NSUndoManagerDidOpenUndoGroup = Notification.Name("NSUndoManagerDidOpenUndoGroupNotification")
    public static let NSUndoManagerWillCloseUndoGroup = Notification.Name("NSUndoManagerWillCloseUndoGroupNotification")
    public static let NSUndoManagerDidCloseUndoGroup = Notification.Name("NSUndoManagerDidCloseUndoGroupNotification")
}

public let NSUndoCloseGroupingRunLoopOrdering = 350000
public let NSUndoManagerGroupIsDiscardableKey = "NSUndoManagerGroupIsDiscardableKey"

open class UndoManager: NSObject {
    /// One registered undo: a closure over its (weakly held) target.
    private struct Action {
        weak var target: AnyObject?
        let perform: () -> Void
    }
    /// A group of actions recorded together; undone and redone as one.
    private final class Group {
        var actions: [Action] = []
        var children: [Group] = []
        var actionName = ""
        var isDiscardable = false
        weak var parent: Group?
        var isEmpty: Bool { actions.isEmpty && children.allSatisfy { $0.isEmpty } }
        func perform() {
            // Undo in reverse order of registration, interleaving nested groups.
            for entry in order.reversed() {
                switch entry {
                case .action(let i): actions[i].perform()
                case .group(let i): children[i].perform()
                }
            }
        }
        enum Entry { case action(Int), group(Int) }
        var order: [Entry] = []
        func add(_ action: Action) { actions.append(action); order.append(.action(actions.count - 1)) }
        func add(_ group: Group) { children.append(group); order.append(.group(children.count - 1)) }
        /// Removes every action whose target is `target` (or has gone away).
        func removeActions(for target: AnyObject?) {
            var kept: [Action] = []
            var map: [Int: Int] = [:]
            for (i, a) in actions.enumerated() {
                if a.target == nil || (target != nil && a.target === target) { continue }
                map[i] = kept.count
                kept.append(a)
            }
            actions = kept
            order = order.compactMap { e in
                if case .action(let i) = e { return map[i].map { .action($0) } }
                return e
            }
            for c in children { c.removeActions(for: target) }
        }
    }

    private var undoStack: [Group] = []
    private var redoStack: [Group] = []
    private var openGroup: Group?
    private var registrationDisabled = 0
    private var eventGroupScheduled = false
    private var undoActionNames: [String] = []

    open var groupsByEvent = true
    open var levelsOfUndo = 0 { didSet { trim() } }
    open var runLoopModes: [RunLoop.Mode] = [.default]
    open private(set) var isUndoing = false
    open private(set) var isRedoing = false

    public override init() { super.init() }

    // MARK: Groups

    open var groupingLevel: Int {
        var n = 0
        var g = openGroup
        while let cur = g { n += 1; g = cur.parent }
        return n
    }

    open func beginUndoGrouping() {
        let g = Group()
        g.parent = openGroup
        openGroup = g
        NotificationCenter.default.post(name: .NSUndoManagerCheckpoint, object: self)
        NotificationCenter.default.post(name: .NSUndoManagerDidOpenUndoGroup, object: self)
    }

    open func endUndoGrouping() {
        guard let g = openGroup else { return }
        NotificationCenter.default.post(name: .NSUndoManagerCheckpoint, object: self)
        NotificationCenter.default.post(name: .NSUndoManagerWillCloseUndoGroup, object: self)
        openGroup = g.parent
        if let parent = g.parent {
            if !g.isEmpty { parent.add(g) }
        } else {
            if !g.isEmpty {
                if isUndoing { redoStack.append(g) } else if isRedoing { undoStack.append(g) } else { undoStack.append(g) }
                trim()
            }
            NotificationCenter.default.post(name: .NSUndoManagerDidCloseUndoGroup, object: self, userInfo: [NSUndoManagerGroupIsDiscardableKey: g.isDiscardable])
        }
    }

    private func trim() {
        guard levelsOfUndo > 0 else { return }
        while undoStack.count > levelsOfUndo { undoStack.removeFirst() }
    }

    /// Grouping by event: the first registration of a cycle opens a group that closes
    /// when the main queue gets to run again (CFRunLoop's `NSUndoCloseGroupingRunLoopOrdering`
    /// observer on Darwin).
    private func ensureEventGroup() {
        guard groupsByEvent, openGroup == nil else { return }
        beginUndoGrouping()
        guard !eventGroupScheduled else { return }
        eventGroupScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.eventGroupScheduled = false
            self.closeEventGroupIfOpen()
        }
    }

    private func closeEventGroupIfOpen() {
        // Close only the implicit top-level group (nested explicit groups close themselves).
        if let g = openGroup, g.parent == nil { endUndoGrouping() }
    }

    // MARK: Registration

    open var isUndoRegistrationEnabled: Bool { registrationDisabled == 0 }
    open func disableUndoRegistration() { registrationDisabled += 1 }
    open func enableUndoRegistration() { registrationDisabled = max(0, registrationDisabled - 1) }

    open func registerUndo<TargetType: AnyObject>(withTarget target: TargetType, handler: @escaping (TargetType) -> Void) {
        guard isUndoRegistrationEnabled else { return }
        if !isUndoing && !isRedoing { redoStack.removeAll() }
        ensureEventGroup()
        guard let g = openGroup else { return }
        g.add(Action(target: target, perform: { [weak target] in if let t = target { handler(t) } }))
        if isUndoing && undoActionNames.last != nil { g.actionName = undoActionNames.last ?? "" }
    }

    @available(*, unavailable, message: "selector-based undo registration needs the Objective-C runtime; use registerUndo(withTarget:handler:)")
    open func registerUndo(withTarget target: Any, selector: Selector, object anObject: Any?) { }

    @available(*, unavailable, message: "invocation-based undo registration needs the Objective-C runtime; use registerUndo(withTarget:handler:)")
    open func prepare(withInvocationTarget target: Any) -> Any { target }

    open func removeAllActions() {
        undoStack.removeAll()
        redoStack.removeAll()
        openGroup = nil
    }

    open func removeAllActions(withTarget target: Any) {
        let t = target as AnyObject
        for g in undoStack + redoStack { g.removeActions(for: t) }
        openGroup?.removeActions(for: t)
        undoStack.removeAll { $0.isEmpty }
        redoStack.removeAll { $0.isEmpty }
    }

    // MARK: Undo and redo

    open var canUndo: Bool { !undoStack.isEmpty || (openGroup.map { !$0.isEmpty } ?? false) }
    open var canRedo: Bool { !redoStack.isEmpty }

    open func undo() {
        if groupingLevel == 1 { endUndoGrouping() }
        undoNestedGroup()
    }

    open func undoNestedGroup() {
        NotificationCenter.default.post(name: .NSUndoManagerCheckpoint, object: self)
        guard !isUndoing, !isRedoing, let g = undoStack.popLast() else { return }
        NotificationCenter.default.post(name: .NSUndoManagerWillUndoChange, object: self)
        isUndoing = true
        undoActionNames.append(g.actionName)
        beginUndoGrouping()
        g.perform()
        openGroup?.actionName = g.actionName
        endUndoGrouping()
        undoActionNames.removeLast()
        isUndoing = false
        NotificationCenter.default.post(name: .NSUndoManagerDidUndoChange, object: self)
    }

    open func redo() {
        NotificationCenter.default.post(name: .NSUndoManagerCheckpoint, object: self)
        guard !isUndoing, !isRedoing, let g = redoStack.popLast() else { return }
        NotificationCenter.default.post(name: .NSUndoManagerWillRedoChange, object: self)
        isRedoing = true
        undoActionNames.append(g.actionName)
        beginUndoGrouping()
        g.perform()
        openGroup?.actionName = g.actionName
        endUndoGrouping()
        undoActionNames.removeLast()
        isRedoing = false
        NotificationCenter.default.post(name: .NSUndoManagerDidRedoChange, object: self)
    }

    // MARK: Action names

    open func setActionName(_ actionName: String) {
        if let g = openGroup { g.actionName = actionName } else { ensureEventGroup(); openGroup?.actionName = actionName }
    }
    open func setActionIsDiscardable(_ discardable: Bool) { openGroup?.isDiscardable = discardable }
    open var undoActionIsDiscardable: Bool { undoStack.last?.isDiscardable ?? false }
    open var redoActionIsDiscardable: Bool { redoStack.last?.isDiscardable ?? false }
    open var undoActionName: String { (openGroup.flatMap { $0.isEmpty ? nil : $0 } ?? undoStack.last)?.actionName ?? "" }
    open var redoActionName: String { redoStack.last?.actionName ?? "" }
    open var undoMenuItemTitle: String { undoMenuTitle(forUndoActionName: undoActionName) }
    open var redoMenuItemTitle: String { redoMenuTitle(forUndoActionName: redoActionName) }
    open func undoMenuTitle(forUndoActionName actionName: String) -> String { actionName.isEmpty ? "Undo" : "Undo \(actionName)" }
    open func redoMenuTitle(forUndoActionName actionName: String) -> String { actionName.isEmpty ? "Redo" : "Redo \(actionName)" }
    open var undoCount: Int { undoStack.count }
    open var redoCount: Int { redoStack.count }
}
#endif
