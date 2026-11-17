// NSResponder (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder
@MainActor open class NSResponder: NSObject, NSCoding, NSStandardKeyBindingResponding, NSUserActivityRestoring, NSTouchBarProvider {
    private weak var _nextResponder: NSResponder?
    private var _menu: NSMenu?
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/init()
    @MainActor public override init() { super.init() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/init(coder:)
    @MainActor public required init?(coder: NSCoder) { super.init() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/acceptsfirstresponder
    @MainActor open var acceptsFirstResponder: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/allowedclasses(forrestorablestatekeypath:)
    @available(macOS 12.0, *)
    @MainActor public class func allowedClasses(forRestorableStateKeyPath keyPath: String) -> [AnyClass] { [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/becomefirstresponder()
    @MainActor open func becomeFirstResponder() -> Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/begingesture(with:)
    @MainActor open func beginGesture(with event: NSEvent) { nextResponder?.beginGesture(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/changemode(with:)
    @available(macOS 10.15, *)
    @MainActor open func changeMode(with event: NSEvent) { nextResponder?.changeMode(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/contextmenukeydown(_:)
    @available(macOS 15.0, *)
    @MainActor open func contextMenuKeyDown(_ event: NSEvent) { nextResponder?.contextMenuKeyDown(event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/cursorupdate(with:)
    @MainActor open func cursorUpdate(with event: NSEvent) { nextResponder?.cursorUpdate(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/encoderestorablestate(with:)
    @MainActor open func encodeRestorableState(with coder: NSCoder) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/encoderestorablestate(with:backgroundqueue:)
    @available(macOS 10.13, *)
    /// AppKit's default encodes on the calling thread, through `encodeRestorableState(with:)`.
    @MainActor open func encodeRestorableState(with coder: NSCoder, backgroundQueue queue: OperationQueue) { encodeRestorableState(with: coder) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/endgesture(with:)
    @MainActor open func endGesture(with event: NSEvent) { nextResponder?.endGesture(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/flagschanged(with:)
    @MainActor open func flagsChanged(with event: NSEvent) { nextResponder?.flagsChanged(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/flushbufferedkeyevents()
    @MainActor open func flushBufferedKeyEvents() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/helprequested(_:)
    @MainActor open func helpRequested(_ eventPtr: NSEvent) { nextResponder?.helpRequested(eventPtr) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/interpretkeyevents(_:)
    /// Runs each key event through the standard key bindings (the table NSTextView uses):
    /// a bound key sends its command with `doCommand(by:)` — to the first text input client
    /// in the chain from the receiver, or as an action up the responder chain — and other
    /// keys insert their characters into the first text input client; with neither, beeps.
    @MainActor open func interpretKeyEvents(_ eventArray: [NSEvent]) {
        for event in eventArray where event.type == .keyDown {
            switch NSResponder._standardKeyBinding(for: event) {
            case .command(let name):
                let selector = Selector((name))
                if let client = self as? NSTextInputClient { client.doCommand(by: selector) }
                else if !tryToPerform(selector, with: nil) { Platform.backend.beep() }
            case .text(let text):
                var r: NSResponder? = self
                while let current = r, !(current is NSTextInputClient) { r = current.nextResponder }
                if let client = r as? NSTextInputClient { client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0)) }
                else { Platform.backend.beep() }
            case nil:
                Platform.backend.beep()
            }
        }
    }

    internal enum _KeyBinding: Equatable { case command(String), text(String) }
    /// The standard key bindings (StandardKeyBinding.dict's editing keys): a command selector
    /// name, the text a printable key inserts, or nil (key equivalents belong to menus).
    internal static func _standardKeyBinding(for event: NSEvent) -> _KeyBinding? {
        let flags = event.modifierFlags
        let shift = flags.contains(.shift)
        let option = flags.contains(.option)
        let command = flags.contains(.command) || flags.contains(.control)
        let plain = event.charactersIgnoringModifiers ?? ""
        var selector: String? = nil
        switch plain {
        case "\r", "\u{3}": selector = "insertNewline:"
        case "\t": selector = shift ? "insertBacktab:" : "insertTab:"
        case "\u{1B}": selector = option ? "complete:" : "cancelOperation:"
        case "\u{F708}": selector = "complete:"
        case "\u{7F}", "\u{8}": selector = option ? "deleteWordBackward:" : "deleteBackward:"
        case "\u{F728}": selector = option ? "deleteWordForward:" : "deleteForward:"
        case "\u{F702}": selector = command ? (shift ? "moveToBeginningOfLineAndModifySelection:" : "moveToBeginningOfLine:") : option ? (shift ? "moveWordLeftAndModifySelection:" : "moveWordLeft:") : (shift ? "moveLeftAndModifySelection:" : "moveLeft:")
        case "\u{F703}": selector = command ? (shift ? "moveToEndOfLineAndModifySelection:" : "moveToEndOfLine:") : option ? (shift ? "moveWordRightAndModifySelection:" : "moveWordRight:") : (shift ? "moveRightAndModifySelection:" : "moveRight:")
        case "\u{F700}": selector = command ? (shift ? "moveToBeginningOfDocumentAndModifySelection:" : "moveToBeginningOfDocument:") : (shift ? "moveUpAndModifySelection:" : "moveUp:")
        case "\u{F701}": selector = command ? (shift ? "moveToEndOfDocumentAndModifySelection:" : "moveToEndOfDocument:") : (shift ? "moveDownAndModifySelection:" : "moveDown:")
        case "\u{F729}": selector = shift ? "moveToBeginningOfDocumentAndModifySelection:" : "moveToBeginningOfDocument:"
        case "\u{F72B}": selector = shift ? "moveToEndOfDocumentAndModifySelection:" : "moveToEndOfDocument:"
        case "\u{F72C}": selector = "pageUp:"
        case "\u{F72D}": selector = "pageDown:"
        default: break
        }
        if selector == nil && command {
            switch plain.lowercased() {
            case "a": selector = "selectAll:"
            case "c": selector = "copy:"
            case "x": selector = "cut:"
            case "v": selector = "paste:"
            default: return nil
            }
        }
        if let s = selector { return .command(s) }
        guard let text = event.characters, !text.isEmpty,
              text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F && ($0.value < 0xF700 || $0.value > 0xF8FF) }) else { return nil }
        return .text(text)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/invalidaterestorablestate()
    @MainActor open func invalidateRestorableState() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/keydown(with:)
    @MainActor open func keyDown(with event: NSEvent) {
        if let next = nextResponder { next.keyDown(with: event) } else { noResponder(for: Selector("keyDown:")) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/keyup(with:)
    @MainActor open func keyUp(with event: NSEvent) { nextResponder?.keyUp(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/magnify(with:)
    @MainActor open func magnify(with event: NSEvent) { nextResponder?.magnify(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/maketouchbar()
    @available(macOS 10.12, *)
    @MainActor open func makeTouchBar() -> NSTouchBar? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/menu
    @MainActor open var menu: NSMenu? {
        get { _menu }
        set { _menu = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/mousecancelled(with:)
    @available(macOS 26.0, *)
    @MainActor open func mouseCancelled(with event: NSEvent) { nextResponder?.mouseCancelled(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/mousedown(with:)
    @MainActor open func mouseDown(with event: NSEvent) { nextResponder?.mouseDown(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/mousedragged(with:)
    @MainActor open func mouseDragged(with event: NSEvent) { nextResponder?.mouseDragged(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/mouseentered(with:)
    @MainActor open func mouseEntered(with event: NSEvent) { nextResponder?.mouseEntered(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/mouseexited(with:)
    @MainActor open func mouseExited(with event: NSEvent) { nextResponder?.mouseExited(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/mousemoved(with:)
    @MainActor open func mouseMoved(with event: NSEvent) { nextResponder?.mouseMoved(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/mouseup(with:)
    @MainActor open func mouseUp(with event: NSEvent) { nextResponder?.mouseUp(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/newwindowfortab(_:)
    @available(macOS 10.12, *)
    /// NSResponder itself does not implement this action (macOS: `respondsToSelector:` is
    /// NO and sending it raises); a responder that makes tabbed windows overrides it.
    @MainActor open func newWindowForTab(_ sender: Any?) {
        fatalError("-[\(type(of: self)) newWindowForTab:]: unrecognized selector sent to instance (NSResponder does not implement it; override it to create tabbed windows)")
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/nextresponder
    @MainActor open var nextResponder: NSResponder? {
        get { _nextResponder }
        set { _nextResponder = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/noresponder(for:)
    @MainActor open func noResponder(for eventSelector: Selector) { if eventSelector == Selector("keyDown:") { Platform.backend.beep() } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/othermousedown(with:)
    @MainActor open func otherMouseDown(with event: NSEvent) { nextResponder?.otherMouseDown(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/othermousedragged(with:)
    @MainActor open func otherMouseDragged(with event: NSEvent) { nextResponder?.otherMouseDragged(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/othermouseup(with:)
    @MainActor open func otherMouseUp(with event: NSEvent) { nextResponder?.otherMouseUp(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/performkeyequivalent(with:)
    @MainActor open func performKeyEquivalent(with event: NSEvent) -> Bool { nextResponder?.performKeyEquivalent(with: event) ?? false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/performtextfinderaction(_:)
    @MainActor open func performTextFinderAction(_ sender: Any?) { nextResponder?.performTextFinderAction(sender) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/presenterror(_:)
    @MainActor open func presentError(_ error: any Error) -> Bool { nextResponder?.presentError(error) ?? false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/presenterror(_:modalfor:delegate:didpresent:contextinfo:)
    /// AppKit's chain: the error goes through `willPresentError(_:)` here and up the
    /// responder chain to NSApplication, which shows it as a sheet on `window`; the delegate
    /// then gets `didPresentSelector` (through the target/action registry, with the
    /// "recovered" answer — always NO: the port's alert offers no recovery options — as an
    /// NSNumber sender, as NSDocument's callbacks do).
    @MainActor open func presentError(_ error: any Error, modalFor window: NSWindow, delegate: Any?, didPresent didPresentSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        let shown = willPresentError(error)
        if let next = nextResponder {
            next.presentError(shown, modalFor: window, delegate: delegate, didPresent: didPresentSelector, contextInfo: contextInfo)
            return
        }
        NSAlert(error: shown).beginSheetModal(for: window) { _ in
            if let sel = didPresentSelector, let target = delegate as AnyObject? {
                _ = ActionRegistry.perform(sel, on: target, with: NSNumber(value: false))
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/pressurechange(with:)
    @available(macOS 10.10, *)
    @MainActor open func pressureChange(with event: NSEvent) { nextResponder?.pressureChange(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/quicklook(with:)
    @MainActor open func quickLook(with event: NSEvent) { nextResponder?.quickLook(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/resignfirstresponder()
    @MainActor open func resignFirstResponder() -> Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/restorablestatekeypaths
    @MainActor class public var restorableStateKeyPaths: [String] { [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/restorestate(with:)
    @MainActor open func restoreState(with coder: NSCoder) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/rightmousedown(with:)
    @MainActor open func rightMouseDown(with event: NSEvent) { nextResponder?.rightMouseDown(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/rightmousedragged(with:)
    @MainActor open func rightMouseDragged(with event: NSEvent) { nextResponder?.rightMouseDragged(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/rightmouseup(with:)
    @MainActor open func rightMouseUp(with event: NSEvent) { nextResponder?.rightMouseUp(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/rotate(with:)
    @MainActor open func rotate(with event: NSEvent) { nextResponder?.rotate(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/scrollwheel(with:)
    @MainActor open func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/shouldbetreatedasinkevent(_:)
    /// No ink input on these platforms; macOS answers NO for a plain responder and a view too.
    @MainActor open func shouldBeTreatedAsInkEvent(_ event: NSEvent) -> Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/showcontexthelp(_:)
    @MainActor open func showContextHelp(_ sender: Any?) { nextResponder?.showContextHelp(sender) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/showwritingtools(_:)
    @available(macOS 15.2, *)
    @MainActor open func showWritingTools(_ sender: Any?) { appleOnlyUnavailable("NSResponder.showWritingTools — Writing Tools is an Apple Intelligence service with no counterpart on Windows or Linux") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/smartmagnify(with:)
    @MainActor open func smartMagnify(with event: NSEvent) { nextResponder?.smartMagnify(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/supplementaltarget(foraction:sender:)
    @MainActor open func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/swipe(with:)
    @MainActor open func swipe(with event: NSEvent) { nextResponder?.swipe(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/tabletpoint(with:)
    @MainActor open func tabletPoint(with event: NSEvent) { nextResponder?.tabletPoint(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/tabletproximity(with:)
    @MainActor open func tabletProximity(with event: NSEvent) { nextResponder?.tabletProximity(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/touchbar
    @available(macOS 10.12, *)
    /// Stored; read for the first time it is `makeTouchBar()`'s (AppKit makes it lazily).
    /// No platform shows a Touch Bar.
    @MainActor open var touchBar: NSTouchBar? {
        get {
            if !_touchBarMade { _touchBarMade = true; _touchBar = makeTouchBar() }
            return _touchBar
        }
        set { _touchBarMade = true; _touchBar = newValue }
    }
    private var _touchBar: NSTouchBar?
    private var _touchBarMade = false
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/touchesbegan(with:)
    @MainActor open func touchesBegan(with event: NSEvent) { nextResponder?.touchesBegan(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/touchescancelled(with:)
    @MainActor open func touchesCancelled(with event: NSEvent) { nextResponder?.touchesCancelled(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/touchesended(with:)
    @MainActor open func touchesEnded(with event: NSEvent) { nextResponder?.touchesEnded(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/touchesmoved(with:)
    @MainActor open func touchesMoved(with event: NSEvent) { nextResponder?.touchesMoved(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/trytoperform(_:with:)
    @MainActor open func tryToPerform(_ action: Selector, with object: Any?) -> Bool {
        if ActionRegistry.perform(action, on: self, with: object) { return true }
        return nextResponder?.tryToPerform(action, with: object) ?? false
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/undomanager
    @MainActor open var undoManager: UndoManager? { nextResponder?.undoManager }
    // SKIPPED (Foundation.NSUserActivity not in corelibs): @MainActor func updateUserActivityState(_ userActivity: NSUserActivity)
    // SKIPPED (Foundation.NSUserActivity not in corelibs): @MainActor var userActivity: NSUserActivity? { get set }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/validrequestor(forsendtype:returntype:)
    /// The next responder's answer (AppKit's default; nil at the end of the chain).
    @MainActor open func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        nextResponder?.validRequestor(forSendType: sendType, returnType: returnType)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/validateproposedfirstresponder(_:for:)
    @MainActor open func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/wantsforwardedscrollevents(for:)
    @MainActor open func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/wantsscrolleventsforswipetracking(on:)
    @MainActor open func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/willpresenterror(_:)
    @MainActor open func willPresentError(_ error: any Error) -> any Error { error }
    // Requirement of NSCoding
    @MainActor open func encode(with coder: NSCoder) { }
}
