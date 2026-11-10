// NSPageLayout (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
//
// The Page Setup panel (ADR-0022): paper size, orientation and scale for a print info,
// drawn by the package and run modally or as a sheet.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagelayout
@MainActor open class NSPageLayout: NSObject {
    private var _accessoryControllers: [NSViewController] = []
    private var _printInfo: NSPrintInfo? = nil
    private var _form: _NSPrintPanelForm? = nil
    /// The code the last run ended with (`pageLayoutDidEnd:returnCode:contextInfo:`).
    public private(set) var _lastReturnCode: Int = NSApplication.ModalResponse.cancel.rawValue

    public override init() { super.init() }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagelayout/accessorycontrollers
    @MainActor open var accessoryControllers: [NSViewController] { _accessoryControllers }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagelayout/addaccessorycontroller(_:)
    @MainActor open func addAccessoryController(_ accessoryController: NSViewController) {
        guard !_accessoryControllers.contains(where: { $0 === accessoryController }) else { return }
        _accessoryControllers.append(accessoryController)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagelayout/beginsheet(using:on:)
    @available(macOS 14.0, *)
    @MainActor open func beginSheet(using printInfo: NSPrintInfo, on parentWindow: NSWindow) async -> NSPageLayout.Result {
        await withCheckedContinuation { c in
            _beginSheet(with: printInfo, modalFor: parentWindow) { c.resume(returning: $0 == .OK ? .changed : .cancelled) }
        }
    }
    // DUPLICATE: @MainActor open func beginSheet(using printInfo: NSPrintInfo, on parentWindow: NSWindow) async -> NSPageLayout.Result
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagelayout/beginsheet(with:modalfor:delegate:didend:contextinfo:)
    @MainActor open func beginSheet(with printInfo: NSPrintInfo, modalFor docWindow: NSWindow, delegate: Any?, didEnd didEndSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        _beginSheet(with: printInfo, modalFor: docWindow) { [weak self] _ in
            guard let self, let delegate = delegate as AnyObject?, let sel = didEndSelector else { return }
            _ = ActionRegistry.perform(sel, on: delegate, with: self)
        }
    }
    @MainActor internal func _beginSheet(with printInfo: NSPrintInfo, modalFor docWindow: NSWindow, completion: @escaping @MainActor (NSApplication.ModalResponse) -> Void) {
        _printInfo = printInfo
        let form = _makeForm(printInfo)
        form.onEnd = { [weak self, weak docWindow] response in
            guard let self else { return }
            self._lastReturnCode = response.rawValue
            if let w = docWindow { w.endSheet(form.panel, returnCode: response) } else { form.panel.orderOut(nil) }
            self._form = nil
            completion(response)
        }
        docWindow.beginSheet(form.panel)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagelayout/printinfo
    @MainActor open var printInfo: NSPrintInfo? { _printInfo }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagelayout/removeaccessorycontroller(_:)
    @MainActor open func removeAccessoryController(_ accessoryController: NSViewController) {
        _accessoryControllers.removeAll { $0 === accessoryController }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagelayout/runmodal()
    @MainActor open func runModal() -> Int { runModal(with: NSPrintInfo.shared) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagelayout/runmodal(with:)
    /// `NSApplication.ModalResponse.OK.rawValue` (1) when the info changed, `.cancel.rawValue` (0) otherwise.
    @MainActor open func runModal(with printInfo: NSPrintInfo) -> Int {
        _printInfo = printInfo
        let form = _makeForm(printInfo)
        form.onEnd = { response in NSApplication.shared.stopModal(withCode: response) }
        form.panel.center()
        let response = NSApplication.shared.runModal(for: form.panel)
        form.panel.orderOut(nil)
        _form = nil
        _lastReturnCode = response == .OK ? NSApplication.ModalResponse.OK.rawValue : NSApplication.ModalResponse.cancel.rawValue
        return _lastReturnCode
    }

    @MainActor internal var _currentForm: _NSPrintPanelForm? { _form }

    private func _makeForm(_ info: NSPrintInfo) -> _NSPrintPanelForm {
        let form = _NSPrintPanelForm(printInfo: info, options: [.showsPageSetupAccessory], accessories: _accessoryControllers.map(\.view),
                                     defaultButtonTitle: "OK", operation: nil)
        form.panel.title = "Page Setup"
        form.pdfButton.isHidden = true
        _form = form
        return form
    }
}

@available(macOS 14.0, *)
extension NSPageLayout {
    @available(macOS 14.0, *)
    public enum Result: Int, Sendable, Equatable, Hashable {
        case cancelled = 0
        case changed = 1
    }
}
