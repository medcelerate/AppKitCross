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
    @MainActor public class func allowedClasses(forRestorableStateKeyPath keyPath: String) -> [AnyClass] { unimplemented() }
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
    @MainActor open func encodeRestorableState(with coder: NSCoder, backgroundQueue queue: OperationQueue) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/endgesture(with:)
    @MainActor open func endGesture(with event: NSEvent) { nextResponder?.endGesture(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/flagschanged(with:)
    @MainActor open func flagsChanged(with event: NSEvent) { nextResponder?.flagsChanged(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/flushbufferedkeyevents()
    @MainActor open func flushBufferedKeyEvents() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/helprequested(_:)
    @MainActor open func helpRequested(_ eventPtr: NSEvent) { nextResponder?.helpRequested(eventPtr) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/interpretkeyevents(_:)
    @MainActor open func interpretKeyEvents(_ eventArray: [NSEvent]) { unimplemented() }
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
    @MainActor open func makeTouchBar() -> NSTouchBar? { unimplemented() }
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
    @MainActor open func newWindowForTab(_ sender: Any?) { unimplemented() }
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
    @MainActor open func performTextFinderAction(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/presenterror(_:)
    @MainActor open func presentError(_ error: any Error) -> Bool { nextResponder?.presentError(error) ?? false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/presenterror(_:modalfor:delegate:didpresent:contextinfo:)
    @MainActor open func presentError(_ error: any Error, modalFor window: NSWindow, delegate: Any?, didPresent didPresentSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/pressurechange(with:)
    @available(macOS 10.10, *)
    @MainActor open func pressureChange(with event: NSEvent) { nextResponder?.pressureChange(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/quicklook(with:)
    @MainActor open func quickLook(with event: NSEvent) { nextResponder?.quickLook(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/resignfirstresponder()
    @MainActor open func resignFirstResponder() -> Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/restorablestatekeypaths
    @MainActor class public var restorableStateKeyPaths: [String] { unimplemented() }
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
    @MainActor open func shouldBeTreatedAsInkEvent(_ event: NSEvent) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/showcontexthelp(_:)
    @MainActor open func showContextHelp(_ sender: Any?) { nextResponder?.showContextHelp(sender) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/showwritingtools(_:)
    @available(macOS 15.2, *)
    @MainActor open func showWritingTools(_ sender: Any?) { unimplemented() }
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
    @MainActor open var touchBar: NSTouchBar? {
        get { unimplemented() }
        set { unimplemented() }
    }
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
    // SKIPPED (Foundation.UndoManager not in corelibs): @MainActor var undoManager: UndoManager? { get }
    // SKIPPED (Foundation.NSUserActivity not in corelibs): @MainActor func updateUserActivityState(_ userActivity: NSUserActivity)
    // SKIPPED (Foundation.NSUserActivity not in corelibs): @MainActor var userActivity: NSUserActivity? { get set }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/validrequestor(forsendtype:returntype:)
    @MainActor open func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/validateproposedfirstresponder(_:for:)
    @MainActor open func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/wantsforwardedscrollevents(for:)
    @MainActor open func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/wantsscrolleventsforswipetracking(on:)
    @MainActor open func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/willpresenterror(_:)
    @MainActor open func willPresentError(_ error: any Error) -> any Error { error }
    // Requirement of NSCoding
    @MainActor open func encode(with coder: NSCoder) { }
}
