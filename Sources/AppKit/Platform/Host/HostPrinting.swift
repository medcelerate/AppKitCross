// Printing on the host backend (ADR-0022): PDF documents through the platform's PDF
// writer (Apple's on macOS, Cairo's in the Linux container), and a fake printer whose
// jobs are kept as PDF data so tests can check what was "spooled".

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

@MainActor
final class HostPrintBackend: PlatformPrintBackend {
    /// Test hook: the printers the backend reports.
    var printers: [PlatformPrinter] = [PlatformPrinter(name: "Host Printer", type: "Host", isDefault: true)]
    /// Test hook: the last device job, once spooled.
    private(set) var lastJob: (settings: PlatformPrintJobSettings, pdf: Data, pages: Int)? = nil
    /// Test hook: what the "native" print panel answers (nil = the host has none).
    var nativePanelAnswer: Bool? = nil
    private(set) var nativePanelRuns = 0

    func makePDFDocument(title: String?) -> (any PlatformPrintDocument)? { _PlatformPDF.makeDocument(title: title) }

    func makePrintJob(_ settings: PlatformPrintJobSettings) -> (any PlatformPrintDocument)? {
        guard let pdf = _PlatformPDF.makeDocument(title: settings.jobTitle) else { return nil }
        return HostPrintJob(settings: settings, pdf: pdf) { [weak self] job, data, pages in
            self?.lastJob = (job, data, pages)
        }
    }

    func runNativePrintPanel(_ settings: inout PlatformPrintJobSettings, pageCount: Int, parent: PlatformWindow?) -> Bool? {
        nativePanelRuns += 1
        return nativePanelAnswer
    }
}

/// A job that renders to PDF and reports it to the backend when finished.
@MainActor
final class HostPrintJob: PlatformPrintDocument {
    let settings: PlatformPrintJobSettings
    private let pdf: any PlatformPrintDocument
    private let spool: (PlatformPrintJobSettings, Data, Int) -> Void
    private(set) var pages = 0
    init(settings: PlatformPrintJobSettings, pdf: any PlatformPrintDocument, spool: @escaping (PlatformPrintJobSettings, Data, Int) -> Void) {
        self.settings = settings
        self.pdf = pdf
        self.spool = spool
    }
    func beginPage(size: CGSize) -> CGContext? { pages += 1; return pdf.beginPage(size: size) }
    func endPage() { pdf.endPage() }
    func finish() -> Data? {
        if let data = pdf.finish() { spool(settings, data, pages) }
        return nil
    }
    func cancel() { pdf.cancel() }
}
