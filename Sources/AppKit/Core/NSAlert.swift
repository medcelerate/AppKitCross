// NSAlert (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsalert
@MainActor open class NSAlert: NSObject {
    // MARK: Storage
    private var _messageText = ""
    private var _informativeText = ""
    private var _buttons: [NSButton] = []
    private var _alertStyle: NSAlert.Style = .warning
    private var _accessoryView: NSView? = nil
    private weak var _delegate: (any NSAlertDelegate)?
    private var _icon: NSImage? = nil
    private var _showsHelp = false
    private var _helpAnchor: NSHelpManager.AnchorName? = nil
    private var _showsSuppressionButton = false
    private var _suppressionButton: NSButton? = nil
    private var _window: NSPanel? = nil
    private var _response: NSApplication.ModalResponse = .cancel
    private var _sheetCompletion: ((NSApplication.ModalResponse) -> Void)? = nil
    /// A sheet keeps its alert alive until a button ends it (the buttons only hold their
    /// target weakly, and callers rarely keep the alert themselves).
    private var _retainedWhileSheetIsUp: NSAlert? = nil

    @MainActor public override init() { super.init() }

    private static let buttonAction = Selector(("_alertButton:"))

    private func _responseForButton(_ index: Int) -> NSApplication.ModalResponse {
        NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + index)
    }

    /// The compact alert of macOS 11 and later: 260 points wide, the icon (the
    /// application's, unless `icon` is set) centred at the top, the bold message and the
    /// informative text centred under it, then the buttons across the full width. Two
    /// buttons sit side by side (the first, the default, on the right) when their titles
    /// fit and neither is destructive; otherwise they stack, the first on top.
    @MainActor private func _buildWindow() -> NSPanel {
        if let w = _window { return w }
        let width = NSAlert._width
        let margin: CGFloat = 16
        let innerWidth = width - 2 * margin
        let textWidth = innerWidth - 8
        if _buttons.isEmpty { _ = addButton(withTitle: "OK") }
        let iconImage: NSImage? = _icon ?? NSApplication.shared.applicationIconImage
        let iconSize: CGFloat = 64
        let message = NSTextField(wrappingLabelWithString: _messageText)
        message.font = NSFont.boldSystemFont(ofSize: 13)
        message.alignment = .center
        message.preferredMaxLayoutWidth = textWidth
        let info = NSTextField(wrappingLabelWithString: _informativeText)
        info.font = NSFont.systemFont(ofSize: 11)
        info.alignment = .center
        info.preferredMaxLayoutWidth = textWidth
        let msgHeight = _messageText.isEmpty ? 0 : message.intrinsicContentSize.height
        let infoHeight = _informativeText.isEmpty ? 0 : info.intrinsicContentSize.height
        let accessoryHeight = _accessoryView?.frame.height ?? 0
        let suppression = _showsSuppressionButton ? _suppressionButton : nil
        suppression?.sizeToFit()
        let buttonHeight: CGFloat = 28, buttonGap: CGFloat = 8
        let halfWidth = (innerWidth - buttonGap) / 2
        for b in _buttons { b.sizeToFit() }
        let stacked = _buttons.count > 2 || _buttons.contains { $0.hasDestructiveAction }
            || _buttons.contains { $0.frame.width + 16 > halfWidth }
        let rows = stacked ? _buttons.count : 1
        let buttonsHeight = CGFloat(rows) * buttonHeight + CGFloat(rows - 1) * buttonGap
        var height: CGFloat = 20
        if iconImage != nil { height += iconSize + 12 }
        height += msgHeight
        if infoHeight > 0 { height += 6 + infoHeight }
        if accessoryHeight > 0 { height += 12 + accessoryHeight }
        if let s = suppression { height += 12 + s.frame.height }
        height += 18 + buttonsHeight + margin
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = ""
        panel._sheetCentresInParent = true
        let content = panel.contentView!
        var y = height - 20
        if let image = iconImage {
            y -= iconSize
            let iv = NSImageView(image: image)
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.frame = NSRect(x: ((width - iconSize) / 2).rounded(), y: y, width: iconSize, height: iconSize)
            content.addSubview(iv)
            y -= 12
        }
        if msgHeight > 0 {
            y -= msgHeight
            message.frame = NSRect(x: (width - textWidth) / 2, y: y, width: textWidth, height: msgHeight)
            content.addSubview(message)
        }
        if infoHeight > 0 {
            y -= 6 + infoHeight
            info.frame = NSRect(x: (width - textWidth) / 2, y: y, width: textWidth, height: infoHeight)
            content.addSubview(info)
        }
        if let accessory = _accessoryView {
            y -= 12 + accessoryHeight
            accessory.frame.origin = NSPoint(x: ((width - accessory.frame.width) / 2).rounded(), y: y)
            content.addSubview(accessory)
        }
        if let s = suppression {
            y -= 12 + s.frame.height
            s.frame.origin = NSPoint(x: margin, y: y)
            content.addSubview(s)
        }
        for (i, b) in _buttons.enumerated() {
            if stacked {
                let top = margin + buttonsHeight - CGFloat(i) * (buttonHeight + buttonGap)
                b.frame = NSRect(x: margin, y: top - buttonHeight, width: innerWidth, height: buttonHeight)
            } else if _buttons.count == 1 {
                b.frame = NSRect(x: margin, y: margin, width: innerWidth, height: buttonHeight)
            } else {
                // The default (first) button on the right, the other on the left.
                let x = i == 0 ? margin + halfWidth + buttonGap : margin
                b.frame = NSRect(x: x, y: margin, width: halfWidth, height: buttonHeight)
            }
            b.tag = i
            b.target = self
            b.action = NSAlert.buttonAction
            content.addSubview(b)
        }
        setActionHandler(for: NSAlert.buttonAction) { [weak self] sender in
            guard let self, let b = sender as? NSButton else { return }
            self._finish(with: self._responseForButton(b.tag))
        }
        panel.center()
        _window = panel
        return panel
    }

    /// The alert's width (macOS 11 and later).
    internal static let _width: CGFloat = 260

    @MainActor private func _finish(with response: NSApplication.ModalResponse) {
        _response = response
        if _sheetCompletion != nil {
            // A sheet: the parent ends it, and its completion (below) reports the code.
            if let w = _window, let parent = w.sheetParent {
                parent.endSheet(w, returnCode: response)
            } else {
                _sheetDidEnd(response)
            }
        } else {
            NSApplication.shared.stopModal(withCode: response)
        }
    }

    @MainActor private func _sheetDidEnd(_ response: NSApplication.ModalResponse) {
        guard let completion = _sheetCompletion else { return }
        _sheetCompletion = nil
        let keepAlive = _retainedWhileSheetIsUp
        _retainedWhileSheetIsUp = nil
        completion(response)
        _ = keepAlive
    }

    @MainActor open func beginSheetModal(for sheetWindow: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        // The panel is attached to the window as a sheet (ADR-0019); a button ends it with
        // its response, Escape or closing the parent with `.cancel`.
        let panel = _buildWindow()
        panel._closesAfterSheetEnds = true      // the panel goes with the session; `window` rebuilds it
        _sheetCompletion = { handler?($0) }
        _retainedWhileSheetIsUp = self
        sheetWindow.beginSheet(panel) { [weak self] response in self?._sheetDidEnd(response) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsalert/init(error:)
    @MainActor public init(error: any Error) {
        super.init()
        let ns = error as NSError
        _messageText = ns.localizedDescription
        _informativeText = (ns.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String) ?? ""
        for title in (ns.userInfo[NSLocalizedRecoveryOptionsErrorKey] as? [String]) ?? [] { _ = addButton(withTitle: title) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsalert/accessoryview
    @MainActor open var accessoryView: NSView? {
        get { _accessoryView }
        set { _accessoryView = newValue; _window = nil }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsalert/addbutton(withtitle:)
    /// As in AppKit, the first button's key equivalent is Return, a button titled
    /// "Cancel" takes Escape and one titled "Don't Save" Command-D; change them after adding.
    @MainActor open func addButton(withTitle title: String) -> NSButton {
        let b: NSButton = _NSAlertButton(title: title, target: nil, action: nil)
        if _buttons.isEmpty {
            b.keyEquivalent = "\r"
        } else if title == "Cancel" {
            b.keyEquivalent = "\u{1B}"
        } else if title == "Don't Save" || title == "Don\u{2019}t Save" {
            b.keyEquivalent = "d"
            b.keyEquivalentModifierMask = [.command]
        }
        _buttons.append(b)
        _window = nil
        return b
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsalert/alertstyle
    @MainActor open var alertStyle: NSAlert.Style {
        get { _alertStyle }
        set { _alertStyle = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsalert/beginsheetmodal(for:)
    @MainActor open func beginSheetModal(for sheetWindow: NSWindow) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { c in beginSheetModal(for: sheetWindow) { c.resume(returning: $0) } }
    }
    // DUPLICATE: @MainActor open func beginSheetModal(for sheetWindow: NSWindow) async -> NSApplication.ModalResponse
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsalert/beginsheetmodal(for:modaldelegate:didend:contextinfo:)
    /// The sheet; when it ends the delegate gets `didEndSelector` through the target/action
    /// registry with the return code as an NSNumber sender (the three-argument callback needs
    /// the runtime; NSApplication's legacy beginSheet does the same, ADR-0038).
    @MainActor open func beginSheetModal(for window: NSWindow, modalDelegate delegate: Any?, didEnd didEndSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        beginSheetModal(for: window) { response in
            if let sel = didEndSelector, let target = delegate as AnyObject? {
                _ = ActionRegistry.perform(sel, on: target, with: NSNumber(value: response.rawValue))
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsalert/buttons
    @MainActor open var buttons: [NSButton] { _buttons }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsalert/delegate
    @MainActor open var delegate: (any NSAlertDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsalert/helpanchor
    @MainActor open var helpAnchor: NSHelpManager.AnchorName? {
        get { _helpAnchor }
        set { _helpAnchor = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsalert/icon
    @MainActor open var icon: NSImage! {
        get { _icon }
        set { _icon = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsalert/informativetext
    @MainActor open var informativeText: String {
        get { _informativeText }
        set { _informativeText = newValue; _window = nil }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsalert/layout()
    @MainActor open func layout() { _ = _buildWindow() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsalert/messagetext
    @MainActor open var messageText: String {
        get { _messageText }
        set { _messageText = newValue; _window = nil }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsalert/runmodal()
    @MainActor open func runModal() -> NSApplication.ModalResponse {
        let panel = _buildWindow()
        let response = NSApplication.shared.runModal(for: panel)
        panel.orderOut(nil)
        return response
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsalert/showshelp
    @MainActor open var showsHelp: Bool {
        get { _showsHelp }
        set { _showsHelp = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsalert/showssuppressionbutton
    @MainActor open var showsSuppressionButton: Bool {
        get { _showsSuppressionButton }
        set { _showsSuppressionButton = newValue; if newValue && _suppressionButton == nil { _suppressionButton = NSButton(checkboxWithTitle: "Do not show this message again", target: nil, action: nil) } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsalert/suppressionbutton
    @MainActor open var suppressionButton: NSButton? { _suppressionButton }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsalert/window
    @MainActor open var window: NSWindow { _buildWindow() }
}

/// An alert's button: a destructive one (`hasDestructiveAction`) draws its title in red,
/// as macOS alerts do.
@MainActor final class _NSAlertButton: NSButton {
    override class func _makeDefaultCell() -> NSCell? { _NSAlertButtonCell(textCell: "") }
}

@MainActor final class _NSAlertButtonCell: NSButtonCell {
    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        let pressed = isHighlighted && highlightsBy.contains(.pushInCellMask)
        guard let b = controlView as? NSButton, b.hasDestructiveAction, isEnabled, !pressed, b.keyEquivalent != "\r" else {
            return super.drawTitle(title, withFrame: frame, in: controlView)
        }
        var attrs = _textAttributes
        attrs[.foregroundColor] = NSColor.systemRed
        _drawText(title.string, attributes: attrs, in: frame, alignment: alignment, flipped: controlView.isFlipped)
        let size = title.string.size(withAttributes: attrs)
        return NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
    }
}
