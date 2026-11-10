// Printing seam (ADR-0022). The core paginates a view and draws each page into a
// CGContext; a backend supplies the printers, the PDF documents and the device jobs those
// pages go into, and (where the platform has one) a native print dialog.
//
// Page contexts are in CoreGraphics' convention: points, origin at the bottom-left of the
// page, y up. The core places the view's page rect on the paper itself, so a backend only
// has to hand out a context for a page of the given size.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A printer the platform knows about.
public struct PlatformPrinter: Sendable, Equatable {
    public var name: String
    /// The driver, model or queue type ("Microsoft Print to PDF", "HP LaserJet", "Generic PDF").
    public var type: String
    public var isDefault: Bool
    public init(name: String, type: String, isDefault: Bool) {
        self.name = name
        self.type = type
        self.isDefault = isDefault
    }
}

/// What a device job needs from `NSPrintInfo`.
public struct PlatformPrintJobSettings: Sendable {
    public var printerName: String?
    public var jobTitle: String
    public var copies = 1
    public var collates = true
    /// 1-based inclusive page range the user asked for; nil = all pages.
    public var firstPage: Int? = nil
    public var lastPage: Int? = nil
    /// Paper size in points, already oriented (landscape papers are wider than tall).
    public var paperSize: CGSize
    public var landscape = false
    /// The scaling factor shown to a native dialog (1 = 100%).
    public var scalingFactor: CGFloat = 1
    /// Where a "print to file" driver should write (Microsoft Print to PDF without its prompt).
    public var outputURL: URL? = nil
    public init(printerName: String?, jobTitle: String, paperSize: CGSize) {
        self.printerName = printerName
        self.jobTitle = jobTitle
        self.paperSize = paperSize
    }
}

/// A document under construction: a PDF file or a job on a device. Pages are begun and
/// ended in order; `finish` closes it.
@MainActor
public protocol PlatformPrintDocument: AnyObject {
    /// Begins a page of `size` points. The context's origin is the page's bottom-left
    /// corner, y up, one unit per point. Nil when the page cannot be started.
    func beginPage(size: CGSize) -> CGContext?
    func endPage()
    /// Closes the document. A PDF document returns its bytes; a device job returns nil
    /// once spooled. Nil from a PDF document means the writer failed.
    func finish() -> Data?
    /// Abandons the document (the user cancelled from the progress panel).
    func cancel()
}

@MainActor
public protocol PlatformPrintBackend: AnyObject {
    /// The printers the platform knows, the default one first when it has one.
    var printers: [PlatformPrinter] { get }
    /// A PDF document (`NSPrintOperation.pdfOperation`, "Save as PDF", `dataWithPDF`).
    func makePDFDocument(title: String?) -> PlatformPrintDocument?
    /// A job on `settings.printerName` (nil = the default printer).
    func makePrintJob(_ settings: PlatformPrintJobSettings) -> PlatformPrintDocument?
    /// The platform's own print dialog, when `APPKITWIN_PRINT_PANEL=native` asks for it
    /// and the platform has one: updates `settings` from the user's choices and returns
    /// true, false when cancelled, nil when there is no native dialog (the package draws
    /// its own panel then).
    func runNativePrintPanel(_ settings: inout PlatformPrintJobSettings, pageCount: Int, parent: PlatformWindow?) -> Bool?
}

extension PlatformBackend {
    /// Printing (Printing.swift, ADR-0022); nil when the platform cannot print at all.
    public var printing: (any PlatformPrintBackend)? { nil }
}
