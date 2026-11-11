// Printing on Windows (ADR-0022): PDF through the recording CGContext and the package's
// PDF writer (PDFDocument.swift); device jobs through Direct2D's print control, each page
// a command list drawn by the same CGContext the window uses, delivered to the spooler as
// an XPS document package by the CD2D shim; the system print dialog (PrintDlgEx) when
// `APPKITWIN_PRINT_PANEL=native`.

#if os(Windows)
import Foundation
import CoreGraphics
import CD2D

@MainActor
final class Win32PrintBackend: PlatformPrintBackend {
    private unowned let backend: Win32Backend
    init(backend: Win32Backend) { self.backend = backend }

    /// Installed printers from the spooler, the default first; the type is the spooler's
    /// queue kind until the driver name is read (follow-up).
    var printers: [PlatformPrinter] {
        var out: UnsafeMutablePointer<UInt16>? = nil
        var length: UInt32 = 0
        guard cd2d_printer_names(&out, &length), let out else { return [] }
        defer { cd2d_file_dialog_free(out) }
        let all = String(decoding: UnsafeBufferPointer(start: out, count: Int(length)), as: UTF16.self)
        let names = all.split(separator: "\u{0}", omittingEmptySubsequences: true).map(String.init)
        return names.enumerated().map { PlatformPrinter(name: $1, type: $1.contains("PDF") ? "Print to PDF" : "Windows printer", isDefault: $0 == 0) }
    }

    func makePDFDocument(title: String?) -> (any PlatformPrintDocument)? { _PlatformPDF.makeDocument(title: title) }

    func makePrintJob(_ settings: PlatformPrintJobSettings) -> (any PlatformPrintDocument)? {
        guard let factory = backend.d2dFactory else { return nil }
        let printer = Array((settings.printerName ?? "").utf16) + [0]
        let title = Array(settings.jobTitle.utf16) + [0]
        let driver = settings.driverSettings ?? Data()
        let job = printer.withUnsafeBufferPointer { p in title.withUnsafeBufferPointer { t in driver.withUnsafeBytes { d in
            cd2d_print_job_create(factory, settings.printerName == nil ? nil : p.baseAddress, t.baseAddress,
                                  driver.isEmpty ? nil : d.baseAddress, UInt32(driver.count))
        } } }
        guard let job else { NSLog("NSPrintOperation: cannot start a print job on \(settings.printerName ?? "the default printer")"); return nil }
        return Win32PrintJob(job: job, factory: factory)
    }

    func runNativePrintPanel(_ settings: inout PlatformPrintJobSettings, pageCount: Int, parent: PlatformWindow?) -> Bool? {
        var s = CD2DPrintDialogSettings()
        s.copies = UInt32(max(1, settings.copies))
        s.collate = settings.collates
        s.fromPage = UInt32(settings.firstPage ?? 0)
        s.toPage = UInt32(settings.lastPage ?? 0)
        s.pageCount = UInt32(max(1, pageCount))
        s.landscape = settings.landscape
        let portrait = settings.landscape ? CGSize(width: settings.paperSize.height, height: settings.paperSize.width) : settings.paperSize
        s.paperWidth = Float(portrait.width)
        s.paperHeight = Float(portrait.height)
        let name = Array((settings.printerName ?? "").utf16) + [0]
        var chosen: UnsafeMutablePointer<UInt16>? = nil
        var chosenLength: UInt32 = 0
        let hwnd = (parent as? Win32Window)?.hwnd
        let ok = name.withUnsafeBufferPointer { n in
            cd2d_print_dialog(hwnd.map { UnsafeMutableRawPointer($0) }, n.baseAddress, &s, &chosen, &chosenLength)
        }
        guard ok else { return false }
        settings.copies = Int(s.copies)
        settings.collates = s.collate
        settings.firstPage = s.fromPage > 0 ? Int(s.fromPage) : nil
        settings.lastPage = s.toPage > 0 ? Int(s.toPage) : nil
        settings.landscape = s.landscape
        if s.paperWidth > 0, s.paperHeight > 0 {
            let w = CGFloat(s.paperWidth), h = CGFloat(s.paperHeight)
            settings.paperSize = s.landscape ? CGSize(width: max(w, h), height: min(w, h)) : CGSize(width: min(w, h), height: max(w, h))
        }
        if let chosen {
            settings.printerName = String(decoding: UnsafeBufferPointer(start: chosen, count: Int(chosenLength)), as: UTF16.self)
            cd2d_file_dialog_free(chosen)
        }
        if let dm = s.driverSettings, s.driverSettingsSize > 0 {
            settings.driverSettings = Data(bytes: dm, count: Int(s.driverSettingsSize))
            cd2d_print_free(dm)
        } else {
            settings.driverSettings = nil
        }
        return true
    }
}

/// A Direct2D print job: one command list per page.
@MainActor
final class Win32PrintJob: PlatformPrintDocument {
    private var job: OpaquePointer?
    private let factory: OpaquePointer
    private var context: CGContext?
    private var target: OpaquePointer?

    init(job: OpaquePointer, factory: OpaquePointer) {
        self.job = job
        self.factory = factory
    }

    /// Direct2D's print pages are in DIPs (1/96 inch); the operation draws in points.
    private static let dipsPerPoint: CGFloat = 96 / 72

    func beginPage(size: CGSize) -> CGContext? {
        let k = Win32PrintJob.dipsPerPoint
        let dips = CGSize(width: size.width * k, height: size.height * k)
        guard let job, context == nil, let t = cd2d_print_job_begin_page(job, Float(dips.width), Float(dips.height)) else { return nil }
        target = t
        // Flip to bottom-left and scale points to DIPs, so a Letter page is 8.5 by 11 inches
        // on paper rather than 612 by 792 DIPs (6.4 by 8.3 inches).
        let flip = CGAffineTransform(a: k, b: 0, c: 0, d: -k, tx: 0, ty: dips.height)
        let ctx = CGContext(target: t, factory: factory, baseTransform: flip, width: Int(dips.width.rounded(.up)), height: Int(dips.height.rounded(.up)))
        context = ctx
        return ctx
    }

    func endPage() {
        context = nil                       // releases its brushes and bitmaps on the device context
        if let target { cd2d_target_release(target) }
        target = nil
        if let job { _ = cd2d_print_job_end_page(job) }
    }

    func finish() -> Data? {
        if context != nil { endPage() }
        guard let job else { return nil }
        self.job = nil
        if !cd2d_print_job_close(job) { NSLog("NSPrintOperation: the print control refused the job") }
        return nil
    }

    func cancel() {
        context = nil
        if let target { cd2d_target_release(target) }
        target = nil
        guard let job else { return }
        self.job = nil
        cd2d_print_job_abort(job)
    }
}
#endif
