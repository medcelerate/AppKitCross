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

    @MainActor public override init() { super.init() }

    private static let buttonAction = Selector(("_alertButton:"))

    private func _responseForButton(_ index: Int) -> NSApplication.ModalResponse {
        NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + index)
    }

    /// Builds the panel: message (bold), informative text, accessory view, buttons right-aligned.
    @MainActor private func _buildWindow() -> NSPanel {
        if let w = _window { return w }
        let width: CGFloat = 420
        let margin: CGFloat = 20
        let textWidth = width - 2 * margin
        let message = NSTextField(wrappingLabelWithString: _messageText)
        message.font = NSFont.boldSystemFont(ofSize: 13)
        message.preferredMaxLayoutWidth = textWidth
        let info = NSTextField(wrappingLabelWithString: _informativeText)
        info.font = NSFont.systemFont(ofSize: 11)
        info.preferredMaxLayoutWidth = textWidth
        let msgSize = message.intrinsicContentSize, infoSize = _informativeText.isEmpty ? NSSize.zero : info.intrinsicContentSize
        let accessoryHeight = _accessoryView?.frame.height ?? 0
        if _buttons.isEmpty { _ = addButton(withTitle: "OK") }
        let buttonHeight: CGFloat = 28
        let height = margin + msgSize.height + 8 + infoSize.height + (accessoryHeight > 0 ? accessoryHeight + 12 : 0) + 16 + buttonHeight + margin
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = ""
        let content = panel.contentView!
        var y = height - margin - msgSize.height
        message.frame = NSRect(x: margin, y: y, width: textWidth, height: msgSize.height)
        content.addSubview(message)
        if !_informativeText.isEmpty {
            y -= 8 + infoSize.height
            info.frame = NSRect(x: margin, y: y, width: textWidth, height: infoSize.height)
            content.addSubview(info)
        }
        if let accessory = _accessoryView {
            y -= 12 + accessoryHeight
            accessory.frame.origin = NSPoint(x: margin, y: y)
            content.addSubview(accessory)
        }
        var x = width - margin
        for (i, b) in _buttons.enumerated() {
            b.sizeToFit()
            let w = max(84, b.frame.width + 24)
            x -= w
            b.frame = NSRect(x: x, y: margin, width: w, height: buttonHeight)
            b.tag = i
            b.target = self
            b.action = NSAlert.buttonAction
            if i == 0 { b.keyEquivalent = "\r" }
            if i == 1 && _buttons.count > 1 { b.keyEquivalent = "\u{1B}" }
            content.addSubview(b)
            x -= 12
        }
        setActionHandler(for: NSAlert.buttonAction) { [weak self] sender in
            guard let self, let b = sender as? NSButton else { return }
            self._finish(with: self._responseForButton(b.tag))
        }
        panel.center()
        _window = panel
        return panel
    }

    @MainActor private func _finish(with response: NSApplication.ModalResponse) {
        _response = response
        if let completion = _sheetCompletion {
            _sheetCompletion = nil
            _window?.orderOut(nil)
            completion(response)
        } else {
            NSApplication.shared.stopModal(withCode: response)
        }
    }

    @MainActor open func beginSheetModal(for sheetWindow: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        // Sheets are shown as a centred modal panel for now (no sheet animation/attachment).
        let panel = _buildWindow()
        _sheetCompletion = { handler?($0) }
        let parent = sheetWindow.frame
        panel.setFrameOrigin(NSPoint(x: parent.midX - panel.frame.width / 2, y: parent.maxY - panel.frame.height - 40))
        panel.makeKeyAndOrderFront(nil)
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
    @MainActor open func addButton(withTitle title: String) -> NSButton {
        let b = NSButton(title: title, target: nil, action: nil)
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
    @MainActor open func beginSheetModal(for window: NSWindow, modalDelegate delegate: Any?, didEnd didEndSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) { unimplemented() }
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
