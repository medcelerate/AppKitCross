// NSTextInputContext (hand-written; seeded from the generated stub, see tools/apigen)
//
// The input method side of a text input client (ADR-0045). On macOS the context talks to
// the Text Input Sources; here the window backend runs the platform's input method (Text
// Services Framework or IMM32 on Windows, text-input-v3 on Wayland, XIM on X11) and every
// one of them edits the client through `_TextInputSession`, so the composition reaches the
// view as marked text exactly as an input method's does on macOS. The context decides which
// client the platform composes into: `activate()` hands it the keyboard focus,
// `deactivate()` takes it away, and the invalidation calls tell it to read the text or the
// caret rectangle again.
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextinputcontext
open class NSTextInputContext: NSObject {
    /// The client, held weakly when it is an object (the view owns its context).
    private weak var _clientObject: AnyObject?
    private var _clientValue: (any NSTextInputClient)?
    private var _acceptsGlyphInfo = false
    private var _allowedInputSourceLocales: [String]? = nil
    nonisolated(unsafe) private static var _current: NSTextInputContext?

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextinputcontext/init(client:)
    public init(client: any NSTextInputClient) {
        if type(of: client) is AnyClass { _clientObject = client as AnyObject } else { _clientValue = client }
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextinputcontext/acceptsglyphinfo
    open var acceptsGlyphInfo: Bool {
        get { _acceptsGlyphInfo }
        set { _acceptsGlyphInfo = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextinputcontext/activate()
    /// Makes this the current context: the window's input method composes into its client.
    open func activate() {
        if NSTextInputContext._current === self { return }
        NSTextInputContext._current?.deactivate()
        NSTextInputContext._current = self
        _TextInputTrace.log("context activate \(_clientDescription)")
        _notifyPlatform(.activated)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextinputcontext/allowedinputsourcelocales
    open var allowedInputSourceLocales: [String]? {
        get { _allowedInputSourceLocales }
        set { _allowedInputSourceLocales = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextinputcontext/client
    open var client: any NSTextInputClient {
        if let c = _clientValue { return c }
        guard let object = _clientObject, let c = object as? NSTextInputClient else {
            preconditionFailure("NSTextInputContext: the client was deallocated")
        }
        return c
    }
    /// The client if it is still alive.
    internal var _liveClient: (any NSTextInputClient)? { _clientValue ?? (_clientObject as? NSTextInputClient) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextinputcontext/current
    class public var current: NSTextInputContext? { _current }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextinputcontext/deactivate()
    /// Takes the keyboard focus away from this context's client; a composition in progress
    /// is committed first (the window or field editor is going away from the text).
    open func deactivate() {
        guard NSTextInputContext._current === self else { return }
        _TextInputTrace.log("context deactivate \(_clientDescription)")
        _notifyPlatform(.deactivated)
        NSTextInputContext._current = nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextinputcontext/discardmarkedtext()
    /// The input method drops its composition; the client keeps the marked text as ordinary
    /// text (`unmarkText()`), as macOS input methods do.
    open func discardMarkedText() {
        _TextInputTrace.log("context discard marked text")
        _notifyPlatform(.discardComposition)
        if let c = _liveClient, c.hasMarkedText() { _TextInputSession.applying { c.unmarkText() } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextinputcontext/handleevent(_:)
    /// The platform input method sees keys before they become events (the window backend
    /// routes them through it), so what is left here is the key-binding half of
    /// `interpretKeyEvents`: a bound key becomes `doCommand(by:)`, a typed key `insertText`.
    open func handleEvent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, let c = _liveClient else { return false }
        return MainActor.assumeIsolated {
            switch NSResponder._standardKeyBinding(for: event) {
            case .command(let name): c.doCommand(by: Selector((name))); return true
            case .text(let text): c.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0)); return true
            case nil: return false
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextinputcontext/invalidatecharactercoordinates()
    open func invalidateCharacterCoordinates() { _notifyPlatform(.layoutChanged) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextinputcontext/keyboardinputsources
    /// Input sources are the platform's keyboard layouts and input methods; listing them by
    /// macOS input source identifiers is not mapped (ADR-0045).
    open var keyboardInputSources: [NSTextInputSourceIdentifier]? { unimplemented("NSTextInputContext.keyboardInputSources — platform input sources are not mapped to macOS identifiers (ADR-0045)") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextinputcontext/keyboardselectiondidchangenotification
    static public var keyboardSelectionDidChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSTextInputContextKeyboardSelectionDidChangeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextinputcontext/localizedname(forinputsource:)
    public class func localizedName(forInputSource inputSourceIdentifier: NSTextInputSourceIdentifier) -> String? { unimplemented("NSTextInputContext.localizedName(forInputSource:) — platform input sources are not mapped to macOS identifiers (ADR-0045)") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextinputcontext/selectedkeyboardinputsource
    open var selectedKeyboardInputSource: NSTextInputSourceIdentifier? {
        get { unimplemented("NSTextInputContext.selectedKeyboardInputSource — platform input sources are not mapped to macOS identifiers (ADR-0045)") }
        set { unimplemented("NSTextInputContext.selectedKeyboardInputSource — platform input sources are not mapped to macOS identifiers (ADR-0045)") }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextinputcontext/textinputclientdidendscrollingorzooming()
    @available(macOS 14.0, *)
    open func textInputClientDidEndScrollingOrZooming() { _notifyPlatform(.layoutChanged) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextinputcontext/textinputclientdidscroll()
    @available(macOS 15.4, *)
    open func textInputClientDidScroll() { _notifyPlatform(.layoutChanged) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextinputcontext/textinputclientdidupdateselection()
    @available(macOS 15.4, *)
    open func textInputClientDidUpdateSelection() { _notifyPlatform(.selectionChanged) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextinputcontext/textinputclientwillstartscrollingorzooming()
    @available(macOS 14.0, *)
    open func textInputClientWillStartScrollingOrZooming() { }

    // MARK: Platform

    /// The client's text or selection changed outside the input method (typing, a click, a
    /// programmatic edit). Ignored while the input method's own edit is being applied.
    internal func _clientDidChange() {
        guard NSTextInputContext._current === self, !_TextInputSession.isApplying else { return }
        _notifyPlatform(.textChanged)
    }

    private var _clientDescription: String {
        guard let c = _liveClient else { return "(gone)" }
        return String(describing: type(of: c))
    }

    /// Tells the client's window backend; text input reaches the platform only from a window.
    private func _notifyPlatform(_ change: PlatformTextInputChange) {
        MainActor.assumeIsolated {
            guard let view = _liveClient as? NSView, let window = view.window else { return }
            window._platformWindow?.textInputChanged(change)
        }
    }
}
