// NSPrintOperation (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
//
// Runs a print job (ADR-0022): shows the print panel (the package's, or the platform's
// native dialog when `APPKITWIN_PRINT_PANEL=native`), paginates the view
// (NSPrintPagination.swift), opens a document on the platform's print backend (a PDF or
// a device job), draws every page through the view's `beginPage`/`draw`/`endPage` hooks
// into that document's CGContext, and delivers the result: the spooled job, the saved
// PDF, or the bytes of a `pdfOperation`. The progress panel is the package's.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation
@MainActor open class NSPrintOperation: NSObject {
    // MARK: Storage
    private let _view: NSView
    private var _printInfo: NSPrintInfo
    private var _printPanel: NSPrintPanel? = nil
    private var _showsPrintPanel = true
    private var _showsProgressPanel = true
    private var _canSpawnSeparateThread = false
    private var _pageOrder: NSPrintOperation.PageOrder = .ascendingPageOrder
    private var _jobTitle: String? = nil
    private var _currentPage = 0
    private var _context: NSGraphicsContext? = nil
    private var _document: (any PlatformPrintDocument)? = nil
    /// `pdfOperation(with:inside:...)`: the rect to print on one page of its own size.
    private var _fixedRect: NSRect? = nil
    private var _outputData: NSMutableData? = nil
    private var _outputURL: URL? = nil
    private var _isCopying = false
    private var _pagination: _NSPrintPagination? = nil
    private var _progress: _NSPrintProgressPanel? = nil
    private var _cancelled = false
    private var _resultData: Data? = nil
    /// The outcome of the last `run()`, for `runModal(for:...)`'s delegate.
    public private(set) var _lastRunSucceeded = false

    nonisolated(unsafe) private static var _current: NSPrintOperation? = nil

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/init(view:)
    @MainActor public init(view: NSView) {
        _view = view
        _printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/init(view:printinfo:)
    @MainActor public init(view: NSView, printInfo: NSPrintInfo) {
        _view = view
        _printInfo = printInfo
        super.init()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/canspawnseparatethread
    @MainActor open var canSpawnSeparateThread: Bool {
        get { _canSpawnSeparateThread }
        set { _canSpawnSeparateThread = newValue }   // Printing stays on the main actor here.
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/cleanup()
    @MainActor open func cleanUp() {
        _progress?.close()
        _progress = nil
        if NSPrintOperation._current === self { NSPrintOperation._current = nil }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/context
    @MainActor open var context: NSGraphicsContext? { _context }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/createcontext()
    /// Opens the platform document the pages go into and returns the first page's context
    /// once a page is begun; the operation calls this itself from `run()`.
    @MainActor open func createContext() -> NSGraphicsContext? {
        guard _document == nil else { return _context }
        guard let backend = Platform.backend.printing else { return nil }
        let disposition = _printInfo.jobDisposition
        if _isCopying || disposition == .save || disposition == .preview || _printInfo.printer.type == NSPrinter.genericTypeName {
            _document = backend.makePDFDocument(title: jobTitle)
        } else {
            _document = backend.makePrintJob(_jobSettings())
        }
        return nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/current
    @MainActor class public var current: NSPrintOperation? {
        get { _current }
        set { _current = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/currentpage
    @MainActor open var currentPage: Int { _currentPage }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/deliverresult()
    /// Writes a `.save` job to its URL and a copying operation's bytes to its data or path.
    @MainActor open func deliverResult() -> Bool {
        guard !_cancelled else { return false }
        if let data = _resultData {
            if let out = _outputData { out.append(data) }
            if let url = _outputURL ?? (_printInfo.jobDisposition == .save ? _printInfo._jobSavingURL : nil) {
                do { try data.write(to: url) } catch { NSLog("NSPrintOperation: cannot write \(url.path): \(error)"); return false }
            }
            if _printInfo.jobDisposition == .preview, !_isCopying { _openPreview(data) }
            return true
        }
        return _document != nil || _isCopying
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/destroycontext()
    @MainActor open func destroyContext() {
        _context = nil
        _document = nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/epsoperation(with:inside:to:)
    @MainActor public class func epsOperation(with view: NSView, inside rect: NSRect, to data: NSMutableData?) -> NSPrintOperation { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/epsoperation(with:inside:to:printinfo:)
    @MainActor public class func epsOperation(with view: NSView, inside rect: NSRect, to data: NSMutableData, printInfo: NSPrintInfo) -> NSPrintOperation { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/epsoperation(with:inside:topath:printinfo:)
    @MainActor public class func epsOperation(with view: NSView, inside rect: NSRect, toPath path: String, printInfo: NSPrintInfo) -> NSPrintOperation { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/iscopyingoperation
    @MainActor open var isCopyingOperation: Bool { _isCopying }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/jobtitle
    @MainActor open var jobTitle: String? {
        get { _jobTitle ?? _view.printJobTitle }
        set { _jobTitle = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/pageorder
    @MainActor open var pageOrder: NSPrintOperation.PageOrder {
        get { _pageOrder }
        set { _pageOrder = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/pagerange
    /// The pages the view produces for the current print info (the whole document, not
    /// the user's selection of it).
    @MainActor open var pageRange: NSRange { _paginate().pageRange }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/pdfoperation(with:inside:to:)
    @MainActor public class func pdfOperation(with view: NSView, inside rect: NSRect, to data: NSMutableData) -> NSPrintOperation {
        pdfOperation(with: view, inside: rect, to: data, printInfo: NSPrintInfo.shared.copy() as! NSPrintInfo)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/pdfoperation(with:inside:to:printinfo:)
    @MainActor public class func pdfOperation(with view: NSView, inside rect: NSRect, to data: NSMutableData, printInfo: NSPrintInfo) -> NSPrintOperation {
        let op = NSPrintOperation(view: view, printInfo: printInfo)
        op._configureCopying(rect: rect)
        op._outputData = data
        return op
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/pdfoperation(with:inside:topath:printinfo:)
    @MainActor public class func pdfOperation(with view: NSView, inside rect: NSRect, toPath path: String, printInfo: NSPrintInfo) -> NSPrintOperation {
        let op = NSPrintOperation(view: view, printInfo: printInfo)
        op._configureCopying(rect: rect)
        op._outputURL = URL(fileURLWithPath: path)
        return op
    }
    private func _configureCopying(rect: NSRect) {
        _isCopying = true
        _fixedRect = rect
        _showsPrintPanel = false
        _showsProgressPanel = false
        _printInfo.jobDisposition = .save
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/pdfpanel
    @MainActor open var pdfPanel: NSPDFPanel {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/preferredrenderingquality
    @MainActor open var preferredRenderingQuality: NSPrintOperation.RenderingQuality { .best }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/printinfo
    @MainActor open var printInfo: NSPrintInfo {
        get { _printInfo }
        set { _printInfo = newValue; _pagination = nil }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/printpanel
    @MainActor open var printPanel: NSPrintPanel {
        get {
            if let p = _printPanel { return p }
            let p = NSPrintPanel()
            _printPanel = p
            return p
        }
        set { _printPanel = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/run()
    @MainActor open func run() -> Bool {
        let previous = NSPrintOperation._current
        NSPrintOperation._current = self
        defer { NSPrintOperation._current = previous; cleanUp() }
        _lastRunSucceeded = false
        _cancelled = false
        if _showsPrintPanel && !_isCopying {
            guard _runPanel(parent: nil) else { return false }
        }
        if _printInfo.jobDisposition == .cancel { return false }
        let ok = _runJob()
        _lastRunSucceeded = ok
        return ok
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/runmodal(for:delegate:didrun:contextinfo:)
    /// Shows the print panel as a sheet on `docWindow`, prints when it ends with Print,
    /// then sends `didRunSelector` to `delegate` with this operation as the sender
    /// (`printOperationDidRun:success:contextInfo:`; `_lastRunSucceeded` holds `success`).
    @MainActor open func runModal(for docWindow: NSWindow, delegate: Any?, didRun didRunSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        _runModal(for: docWindow) { [weak self] _ in
            guard let self, let delegate = delegate as AnyObject?, let sel = didRunSelector else { return }
            _ = ActionRegistry.perform(sel, on: delegate, with: self)
        }
    }
    /// The closure form of `runModal(for:...)`; `NSDocument` and SwiftUI use it.
    @MainActor public func _runModal(for docWindow: NSWindow, completion: @escaping @MainActor (Bool) -> Void) {
        NSPrintOperation._current = self
        _lastRunSucceeded = false
        _cancelled = false
        guard _showsPrintPanel && !_isCopying else {
            let ok = _printInfo.jobDisposition != .cancel && _runJob()
            _lastRunSucceeded = ok
            cleanUp()
            completion(ok)
            return
        }
        if _wantsNativePanel {
            let ok = _runPanel(parent: docWindow)
            let printed = ok && _printInfo.jobDisposition != .cancel && _runJob()
            _lastRunSucceeded = printed
            cleanUp()
            completion(printed)
            return
        }
        printPanel._beginSheet(with: _printInfo, modalFor: docWindow) { [self] response in
            var printed = false
            if response == .OK, _printInfo.jobDisposition != .cancel {
                NSPrintOperation._current = self
                printed = _runJob()
            }
            _lastRunSucceeded = printed
            cleanUp()
            completion(printed)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/showsprintpanel
    @MainActor open var showsPrintPanel: Bool {
        get { _showsPrintPanel }
        set { _showsPrintPanel = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/showsprogresspanel
    @MainActor open var showsProgressPanel: Bool {
        get { _showsProgressPanel }
        set { _showsProgressPanel = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprintoperation/view
    @MainActor open var view: NSView? { _view }

    // MARK: The panel

    /// `APPKITWIN_PRINT_PANEL=native` asks for the platform's own dialog where it has one.
    private var _wantsNativePanel: Bool {
        ProcessInfo.processInfo.environment["APPKITWIN_PRINT_PANEL"]?.lowercased() == "native"
    }

    /// Runs the print panel modally (or the native dialog); false when cancelled.
    private func _runPanel(parent: NSWindow?) -> Bool {
        if _wantsNativePanel, let backend = Platform.backend.printing {
            var settings = _jobSettings()
            if let answer = backend.runNativePrintPanel(&settings, pageCount: _paginate().pageCount, parent: parent?._platformWindow) {
                guard answer else { return false }
                _apply(settings)
                return true
            }
        }
        return printPanel.runModal(with: _printInfo) == NSApplication.ModalResponse.OK.rawValue
    }

    /// The device job's settings from the print info.
    internal func _jobSettings() -> PlatformPrintJobSettings {
        let printers = NSPrinter._platformPrinters()
        var s = PlatformPrintJobSettings(printerName: printers.contains { $0.name == _printInfo.printer.name } ? _printInfo.printer.name : nil,
                                         jobTitle: jobTitle ?? "Untitled", paperSize: _printInfo.paperSize)
        s.copies = _printInfo._copies
        s.collates = _printInfo._bool(.mustCollate) ?? true
        if let r = _printInfo._pageRange { s.firstPage = r.first; s.lastPage = r.last == Int.max ? nil : r.last }
        s.landscape = _printInfo.orientation == .landscape
        s.scalingFactor = _printInfo.scalingFactor
        s.outputURL = _printInfo.jobDisposition == .save ? _printInfo._jobSavingURL : nil
        return s
    }

    /// What a native dialog changed: printer, copies, range, paper, orientation.
    private func _apply(_ s: PlatformPrintJobSettings) {
        if let name = s.printerName, let p = NSPrinter(name: name) { _printInfo.printer = p }
        _printInfo._copies = s.copies
        _printInfo[.mustCollate] = NSNumber(value: s.collates)
        if let first = s.firstPage { _printInfo._pageRange = (first, s.lastPage ?? Int.max) } else { _printInfo._pageRange = nil }
        if s.landscape != (_printInfo.orientation == .landscape) { _printInfo.orientation = s.landscape ? .landscape : .portrait }
        let paper = s.landscape ? NSSize(width: max(s.paperSize.width, s.paperSize.height), height: min(s.paperSize.width, s.paperSize.height)) : s.paperSize
        if abs(paper.width - _printInfo.paperSize.width) > 1 || abs(paper.height - _printInfo.paperSize.height) > 1 { _printInfo.paperSize = paper }
        _printInfo.scalingFactor = s.scalingFactor
        if let url = s.outputURL { _printInfo.jobDisposition = .save; _printInfo._jobSavingURL = url }
        _pagination = nil
    }

    // MARK: Pages

    /// The pagination for the current print info (recomputed when the info changes).
    internal func _paginate() -> _NSPrintPagination {
        if let p = _pagination { return p }
        _view.layoutSubtreeIfNeeded()
        let p = _NSPrintPagination(view: _view, info: _printInfo, fixedRect: _fixedRect)
        _pagination = p
        return p
    }
    /// Forgets the pagination (the panel changed the paper, orientation or scale).
    internal func _invalidatePagination() { _pagination = nil }

    /// The pages `run()` draws, in order: the user's range, reversed for descending order.
    internal func _pagesToPrint() -> [Int] {
        let p = _paginate()
        var pages = Array(p.firstPageNumber..<(p.firstPageNumber + p.pageCount))
        if let r = _printInfo._pageRange, !_isCopying {
            let first = p.firstPageNumber + r.first - 1
            let last = r.last == Int.max ? Int.max : p.firstPageNumber + r.last - 1
            pages = pages.filter { $0 >= first && $0 <= last }
        }
        let reversed = _pageOrder == .descendingPageOrder || (_printInfo._bool(.reversePageOrder) ?? false)
        return reversed ? pages.reversed() : pages
    }

    /// Draws page `page` into `cg`, a context for a paper of the pagination's size
    /// (bottom-left origin, points): the view's `beginPage`, its hierarchy, the page
    /// border with header and footer when `NSPrintHeaderAndFooter` is set, `endPage`.
    internal func _drawPage(_ page: Int, into cg: CGContext) {
        let pagination = _paginate()
        guard let rect = pagination.rect(forPage: page) else { return }
        _currentPage = page
        let gc = NSGraphicsContext(cgContext: cg, flipped: false)
        _context = gc
        let previous = NSGraphicsContext.current
        let wasPrinting = NSGraphicsContext._printing
        let wasCaching = NSView._cachingDisplay
        NSGraphicsContext.current = gc
        NSGraphicsContext._printing = true
        NSView._cachingDisplay = true
        defer {
            NSView._cachingDisplay = wasCaching
            NSGraphicsContext._printing = wasPrinting
            NSGraphicsContext.current = previous
        }
        let location = pagination.viewKnowsPages ? _view.locationOfPrintRect(rect) : pagination.location(for: rect)
        _view.beginPage(in: rect, atPlacement: location)
        let superviewRect = _view._rectInSuperviewSpace(rect)
        _view._displayHierarchy(in: cg, dirtyRect: superviewRect)
        _view.endPage()
        if _printInfo._bool(.headerAndFooter) ?? false {
            cg.saveGState()
            _view.drawPageBorder(with: pagination.paperSize)
            cg.restoreGState()
        }
    }

    /// The effective scale of the current pagination (`beginPage` uses it).
    internal var _pageScale: CGFloat { _paginate().scale }

    /// A rendering of page `page` for the print panel's preview, `scale` pixels per point.
    internal func _previewImage(page: Int, scale: CGFloat) -> CGImage? {
        let pagination = _paginate()
        guard pagination.rect(forPage: page) != nil,
              let surface = Platform.backend.image.makeOffscreen(size: pagination.paperSize, scale: scale) else { return nil }
        let cg = surface.context
        cg.saveGState()
        cg.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        cg.fill(NSRect(origin: .zero, size: pagination.paperSize))
        cg.restoreGState()
        _drawPage(page, into: cg)
        return surface.makeImage()
    }

    // MARK: The job

    /// Opens the document, draws the pages, closes it and delivers the result.
    private func _runJob() -> Bool {
        _pagination = nil
        // Without a device (the generic PDF printer) a spool job is a PDF file: ask where.
        if !_isCopying, _printInfo.jobDisposition == .spool, _printInfo.printer.type == NSPrinter.genericTypeName {
            _printInfo.jobDisposition = .save
            if _printInfo._jobSavingURL == nil {
                let save = NSSavePanel()
                save.allowedFileTypes = ["pdf"]
                save.title = "Save as PDF"
                save.nameFieldStringValue = ((jobTitle ?? "Untitled") as NSString).appendingPathExtension("pdf") ?? "Untitled.pdf"
                guard save.runModal() == .OK, let url = save.url else { return false }
                _printInfo._jobSavingURL = url
            }
        }
        _ = createContext()
        guard let document = _document else {
            NSLog("NSPrintOperation: the platform has no print backend")
            return false
        }
        let pages = _pagesToPrint()
        guard !pages.isEmpty else { destroyContext(); return false }
        let pagination = _paginate()
        // Device copies are repeated here (collated), so every backend behaves the same.
        let copies = (_isCopying || _printInfo.jobDisposition != .spool) ? 1 : _printInfo._copies
        let total = pages.count * copies
        if _showsProgressPanel && !_isCopying {
            let panel = _NSPrintProgressPanel(title: jobTitle ?? "Untitled", pageCount: total) { [weak self] in self?._cancelled = true }
            _progress = panel
            panel.show()
        }
        _view.beginDocument()
        var done = 0
        copyLoop: for _ in 0..<copies {
            for page in pages {
                if _cancelled { break copyLoop }
                guard let cg = document.beginPage(size: pagination.paperSize) else { _cancelled = true; break copyLoop }
                _drawPage(page, into: cg)
                document.endPage()
                done += 1
                _progress?.update(page: done)
            }
        }
        _view.endDocument()
        if _cancelled {
            document.cancel()
            destroyContext()
            return false
        }
        _resultData = document.finish()
        let delivered = deliverResult()
        destroyContext()
        return delivered
    }

    /// `.preview`: hand the PDF to the platform's viewer.
    private func _openPreview(_ data: Data) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(jobTitle ?? "Preview")-\(UUID().uuidString.prefix(8)).pdf")
        do { try data.write(to: url) } catch { return }
        #if os(Linux)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["xdg-open", url.path]
        try? p.run()
        #elseif os(Windows)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "C:\\Windows\\System32\\cmd.exe")
        p.arguments = ["/c", "start", "", url.path.replacingOccurrences(of: "/", with: "\\")]
        try? p.run()
        #else
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = [url.path]
        try? p.run()
        #endif
    }
}



// MARK: - Progress panel

/// "Printing 'title'…", the page count, a bar and Cancel. Shown while the pages are
/// drawn; the event loop is pumped once per page so it repaints and Cancel can be clicked.
@MainActor
final class _NSPrintProgressPanel {
    let panel: NSPanel
    private let status: NSTextField
    private let bar: _NSPrintProgressBar
    private let pageCount: Int
    private let onCancel: () -> Void

    init(title: String, pageCount: Int, onCancel: @escaping () -> Void) {
        self.pageCount = pageCount
        self.onCancel = onCancel
        let width: CGFloat = 360, height: CGFloat = 120
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Print"
        let content = panel.contentView!
        let heading = NSTextField(labelWithString: "Printing \u{201C}\(title)\u{201D}\u{2026}")
        heading.font = NSFont.boldSystemFont(ofSize: 13)
        heading.frame = NSRect(x: 20, y: height - 40, width: width - 40, height: 20)
        content.addSubview(heading)
        status = NSTextField(labelWithString: "Preparing\u{2026}")
        status.font = NSFont.systemFont(ofSize: 11)
        status.frame = NSRect(x: 20, y: height - 62, width: width - 40, height: 16)
        content.addSubview(status)
        bar = _NSPrintProgressBar(frame: NSRect(x: 20, y: height - 82, width: width - 40, height: 10))
        content.addSubview(bar)
        let cancel = NSButton(title: "Cancel", target: nil, action: nil)
        cancel.frame = NSRect(x: width - 20 - 84, y: 14, width: 84, height: 26)
        cancel.keyEquivalent = "\u{1B}"
        cancel.setActionHandler(for: Selector(("cancelPrinting:"))) { [weak self] _ in self?.onCancel() }
        cancel.action = Selector(("cancelPrinting:"))
        cancel.target = cancel
        content.addSubview(cancel)
        panel.center()
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
        pump()
    }

    func update(page: Int) {
        status.stringValue = "Page \(page) of \(pageCount)"
        bar.fraction = pageCount > 0 ? CGFloat(page) / CGFloat(pageCount) : 1
        panel.displayIfNeeded()
        pump()
    }

    /// Services the event loop once so the panel repaints and clicks arrive.
    private func pump() {
        var once = false
        Platform.backend.runNested { defer { once = true }; return once }
    }

    func close() { panel.orderOut(nil) }
}

/// A determinate bar for the progress panel (`NSProgressIndicator` arrives with ADR-0021).
@MainActor
final class _NSPrintProgressBar: NSView {
    var fraction: CGFloat = 0 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.quaternaryLabelColor.setFill()
        track.fill()
        var filled = bounds
        filled.size.width = bounds.width * max(0, min(1, fraction))
        if filled.width > 0 {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: filled, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        }
    }
}
