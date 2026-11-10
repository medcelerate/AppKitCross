// NSPrintPanel (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
//
// The package-drawn print panel (ADR-0022): printer, copies, page range, paper size,
// orientation, scale, a page preview with paging, accessory views, "Save as PDF…",
// Cancel and Print. Run modally or as a sheet. The platform's native dialog is used
// instead when `APPKITWIN_PRINT_PANEL=native` (NSPrintOperation decides that).

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintpanel
@MainActor open class NSPrintPanel: NSObject {
    // MARK: Storage
    private var _accessoryControllers: [NSViewController] = []
    private var _options: NSPrintPanel.Options = [.showsCopies, .showsPageRange, .showsPreview]
    private var _jobStyleHint: NSPrintPanel.JobStyleHint? = nil
    private var _helpAnchor: NSHelpManager.AnchorName? = nil
    private var _defaultButtonTitle: String? = nil
    private var _printInfo: NSPrintInfo = NSPrintInfo.shared
    private var _form: _NSPrintPanelForm? = nil
    /// The code the last run ended with (`printPanelDidEnd:returnCode:contextInfo:`).
    public private(set) var _lastReturnCode: Int = NSApplication.ModalResponse.cancel.rawValue

    public override init() { super.init() }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintpanel/accessorycontrollers
    @MainActor open var accessoryControllers: [NSViewController] { _accessoryControllers }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintpanel/addaccessorycontroller(_:)
    @MainActor open func addAccessoryController(_ accessoryController: any NSViewController & NSPrintPanelAccessorizing) {
        guard !_accessoryControllers.contains(where: { $0 === accessoryController }) else { return }
        _accessoryControllers.append(accessoryController)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintpanel/beginsheet(using:on:)
    @available(macOS 14.0, *)
    @MainActor open func beginSheet(using printInfo: NSPrintInfo, on parentWindow: NSWindow) async -> NSPrintPanel.Result {
        await withCheckedContinuation { c in
            _beginSheet(with: printInfo, modalFor: parentWindow) { c.resume(returning: $0 == .OK ? .printed : .cancelled) }
        }
    }
    // DUPLICATE: @MainActor open func beginSheet(using printInfo: NSPrintInfo, on parentWindow: NSWindow) async -> NSPrintPanel.Result
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintpanel/beginsheet(with:modalfor:delegate:didend:contextinfo:)
    /// Ends by sending `didEndSelector` to `delegate` with the panel as the sender;
    /// `_lastReturnCode` is the return code.
    @MainActor open func beginSheet(with printInfo: NSPrintInfo, modalFor docWindow: NSWindow, delegate: Any?, didEnd didEndSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        _beginSheet(with: printInfo, modalFor: docWindow) { [weak self] _ in
            guard let self, let delegate = delegate as AnyObject?, let sel = didEndSelector else { return }
            _ = ActionRegistry.perform(sel, on: delegate, with: self)
        }
    }
    /// The closure form; `NSPrintOperation.runModal(for:...)` uses it.
    @MainActor internal func _beginSheet(with printInfo: NSPrintInfo, modalFor docWindow: NSWindow, completion: @escaping @MainActor (NSApplication.ModalResponse) -> Void) {
        _printInfo = printInfo
        let form = _makeForm()
        form.onEnd = { [self, weak docWindow] response in   // keeps the panel alive until the sheet ends
            self._lastReturnCode = response.rawValue
            if let w = docWindow { w.endSheet(form.panel, returnCode: response) } else { form.panel.orderOut(nil) }
            self._form = nil
            completion(response)
        }
        docWindow.beginSheet(form.panel)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintpanel/defaultbuttontitle()
    @MainActor open func defaultButtonTitle() -> String? { _defaultButtonTitle }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintpanel/helpanchor
    @MainActor open var helpAnchor: NSHelpManager.AnchorName? {
        get { _helpAnchor }
        set { _helpAnchor = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintpanel/jobstylehint
    @MainActor open var jobStyleHint: NSPrintPanel.JobStyleHint? {
        get { _jobStyleHint }
        set { _jobStyleHint = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintpanel/options
    @MainActor open var options: NSPrintPanel.Options {
        get { _options }
        set { _options = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintpanel/printinfo
    @MainActor open var printInfo: NSPrintInfo { _printInfo }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintpanel/removeaccessorycontroller(_:)
    @MainActor open func removeAccessoryController(_ accessoryController: any NSViewController & NSPrintPanelAccessorizing) {
        _accessoryControllers.removeAll { $0 === accessoryController }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintpanel/runmodal()
    @MainActor open func runModal() -> Int { runModal(with: NSPrintInfo.shared) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintpanel/runmodal(with:)
    /// `NSApplication.ModalResponse.OK.rawValue` (1) to print, `.cancel.rawValue` (0) otherwise.
    @MainActor open func runModal(with printInfo: NSPrintInfo) -> Int {
        _printInfo = printInfo
        let form = _makeForm()
        form.onEnd = { response in NSApplication.shared.stopModal(withCode: response) }
        form.panel.center()
        let response = NSApplication.shared.runModal(for: form.panel)
        form.panel.orderOut(nil)
        _form = nil
        _lastReturnCode = response == .OK ? NSApplication.ModalResponse.OK.rawValue : NSApplication.ModalResponse.cancel.rawValue
        return _lastReturnCode
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintpanel/setdefaultbuttontitle(_:)
    @MainActor open func setDefaultButtonTitle(_ defaultButtonTitle: String?) { _defaultButtonTitle = defaultButtonTitle }

    /// The panel's window and controls (built per run; tests inspect it).
    @MainActor internal var _currentForm: _NSPrintPanelForm? { _form }

    private func _makeForm() -> _NSPrintPanelForm {
        let form = _NSPrintPanelForm(printInfo: _printInfo, options: _options, accessories: _accessoryControllers.map(\.view),
                                     defaultButtonTitle: _defaultButtonTitle ?? "Print", operation: NSPrintOperation.current)
        _form = form
        return form
    }
}





// MARK: - The form

/// Builds the panel's window: a preview column (optional) and a column of labelled rows.
/// Edits go to the print info as they are made (the preview follows); Cancel restores
/// the values the panel opened with.
@MainActor
internal final class _NSPrintPanelForm {
    let panel: NSPanel
    let printInfo: NSPrintInfo
    private let original: [NSPrintInfo.AttributeKey: Any]
    private let originalPrinter: NSPrinter
    private weak var operation: NSPrintOperation?
    var onEnd: ((NSApplication.ModalResponse) -> Void)?

    // Controls, by what they show (nil when the option is off).
    private(set) var printers: NSPopUpButton?
    private(set) var copies: NSTextField?
    private(set) var allPages: NSButton?
    private(set) var somePages: NSButton?
    private(set) var fromPage: NSTextField?
    private(set) var toPage: NSTextField?
    private(set) var papers: NSPopUpButton?
    private(set) var portrait: NSButton?
    private(set) var landscape: NSButton?
    private(set) var scale: NSTextField?
    private(set) var preview: _NSPrintPreviewView?
    private(set) var pageLabel: NSTextField?
    private(set) var previousPage: NSButton?
    private(set) var nextPage: NSButton?
    private(set) var printButton: NSButton!
    private(set) var cancelButton: NSButton!
    private(set) var pdfButton: NSButton!
    private let rows: _NSPrintFormRows
    private var previewPage = 0   // 0-based index into the pages

    static let labelWidth: CGFloat = 96
    static let rowHeight: CGFloat = 26

    init(printInfo: NSPrintInfo, options: NSPrintPanel.Options, accessories: [NSView], defaultButtonTitle: String, operation: NSPrintOperation?) {
        self.printInfo = printInfo
        self.operation = operation
        original = printInfo._attributes()
        originalPrinter = printInfo.printer
        let showsSetup = options.contains(.showsPageSetupAccessory)
        let showsPreview = options.contains(.showsPreview)
        // 20 + 260 + 20 + 320 + 20 = 640 with the preview: the width of TextEdit's window, so
        // the sheet attaches without overhanging it.
        let formWidth: CGFloat = 320
        let previewWidth: CGFloat = showsPreview ? 260 : 0
        let margin: CGFloat = 20
        let width = margin + previewWidth + (showsPreview ? margin : 0) + formWidth + margin
        rows = _NSPrintFormRows(width: formWidth)

        // Printer
        let printerPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        let names = NSPrinter.printerNames
        let allNames = names.isEmpty ? [NSPrinter.genericName] : names
        printerPopUp.addItems(withTitles: allNames)
        if let i = allNames.firstIndex(of: printInfo.printer.name) { printerPopUp.selectItem(at: i) }
        printers = printerPopUp
        rows.add(label: "Printer:", [(printerPopUp, formWidth - _NSPrintPanelForm.labelWidth - 8)])

        if options.contains(.showsCopies) {
            let f = NSTextField(string: "\(printInfo._copies)")
            f.alignment = .right
            copies = f
            rows.add(label: "Copies:", [(f, 60)])
        }
        if options.contains(.showsPageRange) {
            let all = NSButton(radioButtonWithTitle: "All", target: nil, action: nil)
            let some = NSButton(radioButtonWithTitle: "From:", target: nil, action: nil)
            let from = NSTextField(string: "1"), to = NSTextField(string: "1")
            from.alignment = .right; to.alignment = .right
            let toLabel = NSTextField(labelWithString: "to:")
            let range = printInfo._pageRange
            all.state = range == nil ? .on : .off
            some.state = range == nil ? .off : .on
            if let r = range { from.stringValue = "\(r.first)"; to.stringValue = r.last == Int.max ? "" : "\(r.last)" }
            allPages = all; somePages = some; fromPage = from; toPage = to
            rows.add(label: "Pages:", [(all, 60)])
            rows.add(label: "", [(some, 70), (from, 50), (toLabel, 24), (to, 50)])
        }
        if options.contains(.showsPaperSize) || showsSetup {
            let p = NSPopUpButton(frame: .zero, pullsDown: false)
            p.addItems(withTitles: NSPrinter.papers.map { "\($0.localized)  \(Int($0.size.width.rounded())) × \(Int($0.size.height.rounded())) pt" })
            if let name = printInfo.paperName, let i = NSPrinter.papers.firstIndex(where: { $0.name == name }) { p.selectItem(at: i) }
            papers = p
            rows.add(label: "Paper Size:", [(p, formWidth - _NSPrintPanelForm.labelWidth - 8)])
        }
        if options.contains(.showsOrientation) || showsSetup {
            let po = NSButton(radioButtonWithTitle: "Portrait", target: nil, action: nil)
            let la = NSButton(radioButtonWithTitle: "Landscape", target: nil, action: nil)
            po.state = printInfo.orientation == .portrait ? .on : .off
            la.state = printInfo.orientation == .landscape ? .on : .off
            portrait = po; landscape = la
            rows.add(label: "Orientation:", [(po, 90), (la, 110)])
        }
        if options.contains(.showsScaling) || showsSetup {
            let s = NSTextField(string: "\(Int((printInfo.scalingFactor * 100).rounded()))")
            s.alignment = .right
            scale = s
            rows.add(label: "Scale:", [(s, 60), (NSTextField(labelWithString: "%"), 20)])
        }
        for accessory in accessories {
            rows.add(view: accessory)
        }

        let buttonsHeight: CGFloat = 26
        let contentHeight = max(rows.height, showsPreview ? 400 : 0)
        let height = margin + contentHeight + 16 + buttonsHeight + margin
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Print"
        let content = panel.contentView!

        if showsPreview {
            let pageCount = operation?._paginate().pageCount ?? 1
            let pv = _NSPrintPreviewView(frame: NSRect(x: margin, y: height - margin - (contentHeight - 30), width: previewWidth, height: contentHeight - 30))
            pv.form = self
            preview = pv
            content.addSubview(pv)
            let prev = NSButton(title: "\u{25C0}", target: nil, action: nil)
            let next = NSButton(title: "\u{25B6}", target: nil, action: nil)
            let label = NSTextField(labelWithString: "1 of \(pageCount)")
            label.alignment = .center
            let y = height - margin - contentHeight + 2
            prev.frame = NSRect(x: margin + previewWidth / 2 - 90, y: y, width: 36, height: 24)
            label.frame = NSRect(x: margin + previewWidth / 2 - 50, y: y + 3, width: 100, height: 18)
            next.frame = NSRect(x: margin + previewWidth / 2 + 54, y: y, width: 36, height: 24)
            content.addSubview(prev); content.addSubview(label); content.addSubview(next)
            previousPage = prev; nextPage = next; pageLabel = label
            prev.setActionHandler(for: Selector(("previousPage:"))) { [weak self] _ in self?.step(-1) }
            prev.action = Selector(("previousPage:")); prev.target = prev
            next.setActionHandler(for: Selector(("nextPage:"))) { [weak self] _ in self?.step(1) }
            next.action = Selector(("nextPage:")); next.target = next
        }
        let formX = margin + previewWidth + (showsPreview ? margin : 0)
        rows.place(in: content, x: formX, top: height - margin)

        pdfButton = NSButton(title: "Save as PDF\u{2026}", target: nil, action: nil)
        pdfButton.frame = NSRect(x: margin, y: margin, width: 130, height: buttonsHeight)
        content.addSubview(pdfButton)
        printButton = NSButton(title: defaultButtonTitle, target: nil, action: nil)
        printButton.keyEquivalent = "\r"
        printButton.frame = NSRect(x: width - margin - 90, y: margin, width: 90, height: buttonsHeight)
        content.addSubview(printButton)
        cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        cancelButton.keyEquivalent = "\u{1B}"
        cancelButton.frame = NSRect(x: width - margin - 90 - 12 - 90, y: margin, width: 90, height: buttonsHeight)
        content.addSubview(cancelButton)
        wire()
        if let pv = preview { pv.needsDisplay = true }
    }

    private func wire() {
        func handle(_ button: NSButton, _ name: String, _ body: @escaping () -> Void) {
            let sel = Selector((name))
            button.setActionHandler(for: sel) { _ in body() }
            button.action = sel
            button.target = button
        }
        handle(printButton, "printPanelPrint:") { [weak self] in self?.end(.OK) }
        handle(cancelButton, "printPanelCancel:") { [weak self] in self?.cancel() }
        handle(pdfButton, "printPanelSavePDF:") { [weak self] in self?.saveAsPDF() }
        if let printers { handle(printers, "printPanelPrinter:") { [weak self] in self?.apply() } }
        if let papers { handle(papers, "printPanelPaper:") { [weak self] in self?.apply() } }
        if let allPages, let somePages {
            handle(allPages, "printPanelAllPages:") { [weak self] in allPages.state = .on; somePages.state = .off; self?.apply() }
            handle(somePages, "printPanelSomePages:") { [weak self] in somePages.state = .on; allPages.state = .off; self?.apply() }
        }
        if let portrait, let landscape {
            handle(portrait, "printPanelPortrait:") { [weak self] in portrait.state = .on; landscape.state = .off; self?.apply() }
            handle(landscape, "printPanelLandscape:") { [weak self] in landscape.state = .on; portrait.state = .off; self?.apply() }
        }
        for field in [copies, fromPage, toPage, scale].compactMap({ $0 }) {
            field.setActionHandler(for: Selector(("printPanelField:"))) { [weak self] _ in self?.apply() }
            field.action = Selector(("printPanelField:"))
            field.target = field
        }
    }

    /// Reads the controls into the print info and refreshes the preview.
    func apply() {
        if let printers, let title = printers.titleOfSelectedItem, let p = NSPrinter(name: title) { printInfo.printer = p }
        if let copies { printInfo._copies = max(1, copies.integerValue) }
        if let somePages, let fromPage, let toPage {
            if somePages.state == .on {
                let first = max(1, fromPage.integerValue)
                let last = toPage.stringValue.isEmpty ? Int.max : max(first, toPage.integerValue)
                printInfo._pageRange = (first, last)
            } else {
                printInfo._pageRange = nil
            }
        }
        if let papers, papers.indexOfSelectedItem >= 0, papers.indexOfSelectedItem < NSPrinter.papers.count {
            let paper = NSPrinter.papers[papers.indexOfSelectedItem]
            if printInfo.paperName != paper.name { printInfo.paperName = paper.name }
        }
        if let landscape { printInfo.orientation = landscape.state == .on ? .landscape : .portrait }
        if let scale, scale.doubleValue > 0 { printInfo.scalingFactor = CGFloat(scale.doubleValue) / 100 }
        operation?._invalidatePagination()
        if let count = operation?._paginate().pageCount { previewPage = min(previewPage, max(0, count - 1)); updatePageLabel(count) }
        preview?.needsDisplay = true
    }

    private func updatePageLabel(_ count: Int) { pageLabel?.stringValue = "\(min(previewPage + 1, max(count, 1))) of \(max(count, 1))" }

    private func step(_ delta: Int) {
        let count = operation?._paginate().pageCount ?? 1
        previewPage = max(0, min(count - 1, previewPage + delta))
        updatePageLabel(count)
        preview?.needsDisplay = true
    }

    /// The page the preview shows (`firstPageNumber`-based) and its image.
    func previewImage(scale: CGFloat) -> CGImage? {
        guard let op = operation else { return nil }
        let p = op._paginate()
        return op._previewImage(page: p.firstPageNumber + previewPage, scale: scale)
    }
    var previewPaperSize: NSSize { printInfo.paperSize }

    private func commitFields() { panel.makeFirstResponder(nil) }

    private func end(_ response: NSApplication.ModalResponse) {
        commitFields()
        apply()
        onEnd?(response)
    }

    private func cancel() {
        printInfo._apply(original)
        printInfo.printer = originalPrinter
        operation?._invalidatePagination()
        onEnd?(.cancel)
    }

    /// "Save as PDF…": a save panel for the file, then the job runs with `.save`.
    private func saveAsPDF() {
        commitFields()
        apply()
        let save = NSSavePanel()
        save.allowedFileTypes = ["pdf"]
        save.nameFieldStringValue = ((operation?.jobTitle ?? "Untitled") as NSString).appendingPathExtension("pdf") ?? "Untitled.pdf"
        save.title = "Save as PDF"
        guard save.runModal() == .OK, let url = save.url else { return }
        printInfo.jobDisposition = .save
        printInfo._jobSavingURL = url
        onEnd?(.OK)
    }
}

/// Labelled rows of controls laid out top to bottom.
@MainActor
internal final class _NSPrintFormRows {
    private var rows: [(label: String?, views: [(NSView, CGFloat)], height: CGFloat)] = []
    let width: CGFloat
    init(width: CGFloat) { self.width = width }
    var height: CGFloat { rows.reduce(0) { $0 + $1.height + 8 } }
    func add(label: String, _ views: [(NSView, CGFloat)]) { rows.append((label, views, _NSPrintPanelForm.rowHeight)) }
    func add(view: NSView) { rows.append((nil, [(view, min(width, max(view.frame.width, 100)))], max(view.frame.height, _NSPrintPanelForm.rowHeight))) }
    func place(in content: NSView, x: CGFloat, top: CGFloat) {
        var y = top
        for row in rows {
            y -= row.height
            var cx = x
            if let label = row.label {
                let l = NSTextField(labelWithString: label)
                l.alignment = .right
                l.frame = NSRect(x: x, y: y + (row.height - 20) / 2, width: _NSPrintPanelForm.labelWidth, height: 20)
                content.addSubview(l)
                cx = x + _NSPrintPanelForm.labelWidth + 8
            }
            for (view, w) in row.views {
                let h = row.label == nil ? row.height : (view is NSTextField && (view as! NSTextField).isEditable ? 22 : row.height - 2)
                view.frame = NSRect(x: cx, y: y + (row.height - h) / 2, width: w, height: h)
                content.addSubview(view)
                cx += w + 6
            }
            y -= 8
        }
    }
}

/// The page preview: the paper scaled to fit, with the page rendered through the print
/// operation's pagination.
@MainActor
internal final class _NSPrintPreviewView: NSView {
    weak var form: _NSPrintPanelForm?
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath.fill(bounds)
        guard let form else { return }
        let paper = form.previewPaperSize
        guard paper.width > 0, paper.height > 0 else { return }
        let inset = bounds.insetBy(dx: 12, dy: 12)
        let s = min(inset.width / paper.width, inset.height / paper.height)
        let size = NSSize(width: paper.width * s, height: paper.height * s)
        let origin = NSPoint(x: inset.midX - size.width / 2, y: inset.midY - size.height / 2)
        let page = NSRect(origin: origin, size: size)
        NSColor.black.withAlphaComponent(0.15).setFill()
        NSBezierPath.fill(page.offsetBy(dx: 2, dy: -2))
        NSColor.white.setFill()
        NSBezierPath.fill(page)
        if let cg = NSGraphicsContext.current?.cgContext {
            let scale = (window?.backingScaleFactor ?? 1) * s
            if let image = form.previewImage(scale: scale) {
                cg.saveGState()
                cg.draw(image, in: page)
                cg.restoreGState()
            }
        }
        NSColor.separatorColor.setStroke()
        NSBezierPath.stroke(page)
    }
}
