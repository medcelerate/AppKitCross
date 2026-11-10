// Printing (ADR-0022): print info, pagination, PDF output, the panels and the host
// backend's spooled jobs. Runs on the host backend on every platform; the PDF checks use
// the inspector in Support/PDFWriter.swift and, on macOS, Apple's CGPDFDocument too.

import XCTest
@testable import AppKit
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A tall view: a gradient of bars so every page draws something.
@MainActor
final class BarsView: NSView {
    var flipped = false
    var drawn: [NSRect] = []
    override var isFlipped: Bool { flipped }
    override func draw(_ dirtyRect: NSRect) {
        drawn.append(dirtyRect)
        var y: CGFloat = 0
        var i = 0
        while y < bounds.height {
            NSColor(red: CGFloat(i % 3) / 3, green: 0.4, blue: 0.7, alpha: 1).setFill()
            NSBezierPath.fill(NSRect(x: 10, y: y + 5, width: bounds.width - 20, height: 40))
            y += 50
            i += 1
        }
    }
}

/// A view that lays its own pages out.
@MainActor
final class ThreePageView: NSView {
    override func knowsPageRange(_ range: NSRangePointer) -> Bool { range.pointee = NSRange(location: 1, length: 3); return true }
    override func rectForPage(_ page: Int) -> NSRect { NSRect(x: 0, y: CGFloat(page - 1) * 100, width: 200, height: 100) }
    override func draw(_ dirtyRect: NSRect) { NSColor.red.setFill(); NSBezierPath.fill(dirtyRect) }
}

/// A document that prints its text view (what TextEdit does).
@MainActor
final class PrintableDocument: NSDocument {
    var textView: NSTextView?
    override func makeWindowControllers() {
        let w = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 400, height: 300), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Printable"
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 1600))
        tv.string = (1...90).map { "Line \($0): the quick brown fox jumps over the lazy dog." }.joined(separator: "\n")
        w.contentView?.addSubview(tv)
        textView = tv
        addWindowController(NSWindowController(window: w))
    }
    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        guard let tv = textView else { return try super.printOperation(withSettings: printSettings) }
        var attributes: [NSPrintInfo.AttributeKey: Any] = [:]
        for (key, value) in printInfo.dictionary() { if let k = key as? String { attributes[NSPrintInfo.AttributeKey(rawValue: k)] = value } }
        for (key, value) in printSettings { attributes[key] = value }
        tv.sizeToFit()   // the whole text, not the part the scroll view shows
        let op = NSPrintOperation(view: tv, printInfo: NSPrintInfo(dictionary: attributes))
        op.showsProgressPanel = false
        return op
    }
}

final class PrintTests: XCTestCase, @unchecked Sendable {
    @MainActor private var host: HostBackend { Platform.backend as! HostBackend }
    @MainActor private var printing: HostPrintBackend { host.hostPrinting }

    @MainActor private func letterInfo() -> NSPrintInfo {
        let info = NSPrintInfo()
        info.paperName = NSPrinter.PaperName("na-letter")
        info.orientation = .portrait
        info.leftMargin = 72; info.rightMargin = 72; info.topMargin = 90; info.bottomMargin = 90
        info.scalingFactor = 1
        info.horizontalPagination = .clip
        info.verticalPagination = .automatic
        info.printer = NSPrinter(name: "Host Printer")!
        return info
    }

    @MainActor private func tempPDF(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PrintTests-\(name)-\(UUID().uuidString.prefix(6)).pdf")
    }

    /// Page count through Apple's parser where available, else the inspector.
    private func pageCount(_ data: Data) -> Int {
        #if canImport(Darwin)
        if let provider = CGDataProvider(data: data as CFData), let doc = CGPDFDocument(provider) { return doc.numberOfPages }
        #endif
        return _PDFInspector.pageCount(data)
    }

    // MARK: Print info

    func testPaperNamesSizesAndOrientation() {
        MainActor.assumeIsolated {
            let info = NSPrintInfo()
            info.paperName = NSPrinter.PaperName("iso-a4")
            XCTAssertEqual(info.paperSize, NSSize(width: 595, height: 842))
            XCTAssertEqual(info.localizedPaperName, "A4")
            info.orientation = .landscape
            XCTAssertEqual(info.paperSize, NSSize(width: 842, height: 595), "landscape turns the paper")
            XCTAssertEqual(info.paperName, NSPrinter.PaperName("iso-a4"))
            info.orientation = .portrait
            info.paperSize = NSSize(width: 612, height: 792)
            XCTAssertEqual(info.paperName, NSPrinter.PaperName("na-letter"), "a size the table knows names the paper")
            XCTAssertEqual(NSPrinter(name: "Host Printer")?.pageSize(forPaper: NSPrinter.PaperName("na-legal")), NSSize(width: 612, height: 1008))
            XCTAssertEqual(NSPrinter.printerNames, ["Host Printer"])
            XCTAssertEqual(NSPrinter.printerTypes.map(\.rawValue), ["Host"])
            XCTAssertEqual(NSPrintInfo.defaultPrinter?.name, "Host Printer")
            XCTAssertNil(NSPrinter(name: "No Such Printer"))
            XCTAssertEqual(info.imageablePageBounds, NSRect(x: 0, y: 0, width: 612, height: 792))
            XCTAssertEqual(NSPrintInfo.shared.horizontalPagination, .clip)
            XCTAssertEqual(NSPrintInfo.shared.verticalPagination, .automatic)
            XCTAssertTrue(NSPrintInfo.shared.isHorizontallyCentered && NSPrintInfo.shared.isVerticallyCentered)
        }
    }

    func testDictionaryRoundTrip() {
        MainActor.assumeIsolated {
            let info = letterInfo()
            info.orientation = .landscape
            info.scalingFactor = 0.75
            info.horizontalPagination = .fit
            info.isVerticallyCentered = false
            info.jobDisposition = .save
            info._copies = 3
            info._pageRange = (2, 5)
            info._jobSavingURL = URL(fileURLWithPath: "/tmp/x.pdf")
            let dictionary = info.dictionary()
            XCTAssertEqual(dictionary[NSPrintInfo.AttributeKey.copies.rawValue] as? Int, 3)
            XCTAssertEqual(dictionary[NSPrintInfo.AttributeKey.printerName.rawValue] as? String, "Host Printer")
            var attributes: [NSPrintInfo.AttributeKey: Any] = [:]
            for (k, v) in dictionary { attributes[NSPrintInfo.AttributeKey(rawValue: k as! String)] = v }
            let copy = NSPrintInfo(dictionary: attributes)
            XCTAssertEqual(copy.paperSize, NSSize(width: 792, height: 612))
            XCTAssertEqual(copy.orientation, .landscape)
            XCTAssertEqual(copy.paperName, NSPrinter.PaperName("na-letter"))
            XCTAssertEqual(copy.scalingFactor, 0.75)
            XCTAssertEqual(copy.horizontalPagination, .fit)
            XCTAssertEqual(copy.verticalPagination, .automatic)
            XCTAssertFalse(copy.isVerticallyCentered)
            XCTAssertTrue(copy.isHorizontallyCentered)
            XCTAssertEqual(copy.leftMargin, 72); XCTAssertEqual(copy.topMargin, 90)
            XCTAssertEqual(copy.jobDisposition, .save)
            XCTAssertEqual(copy._copies, 3)
            XCTAssertEqual(copy._pageRange?.first, 2); XCTAssertEqual(copy._pageRange?.last, 5)
            XCTAssertEqual(copy._jobSavingURL?.path, "/tmp/x.pdf")
            XCTAssertEqual(copy.printer.name, "Host Printer")
            let cloned = info.copy() as! NSPrintInfo
            XCTAssertEqual(cloned.paperSize, info.paperSize)
            XCTAssertEqual(cloned.scalingFactor, 0.75)
            cloned.setUpPrintOperationDefaultValues()
            XCTAssertEqual(cloned._copies, 1); XCTAssertNil(cloned._pageRange); XCTAssertEqual(cloned.jobDisposition, .spool)
            XCTAssertEqual(info._copies, 3, "the copy is independent")
        }
    }

    func testCoding() throws {
        try MainActor.assumeIsolated {
            let info = letterInfo()
            info.orientation = .landscape
            info.scalingFactor = 1.5
            let archiver = NSKeyedArchiver(requiringSecureCoding: false)
            info.encode(with: archiver)
            archiver.finishEncoding()
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
            unarchiver.requiresSecureCoding = false
            let decoded = NSPrintInfo(coder: unarchiver)
            XCTAssertEqual(decoded.paperSize, NSSize(width: 792, height: 612))
            XCTAssertEqual(decoded.orientation, .landscape)
            XCTAssertEqual(decoded.scalingFactor, 1.5)
            XCTAssertEqual(decoded.topMargin, 90)
        }
    }

    // MARK: Pagination

    func testAutomaticVerticalPaginationSplitsTheBoundsFromTheTop() {
        MainActor.assumeIsolated {
            let view = BarsView(frame: NSRect(x: 0, y: 0, width: 500, height: 2000))
            let info = letterInfo()
            let p = _NSPrintPagination(view: view, info: info)
            // Printable area: 612-144 = 468 wide, 792-180 = 612 tall.
            XCTAssertEqual(p.printableRect, NSRect(x: 72, y: 90, width: 468, height: 612))
            XCTAssertEqual(p.pageCount, 4, "2000 / 612 → 4 pages")
            XCTAssertEqual(p.scale, 1)
            let first = p.rect(forPage: 1)!
            XCTAssertEqual(first.maxY, 2000, "page 1 is the top of a non-flipped view")
            XCTAssertEqual(first.height, 612)
            XCTAssertEqual(first.width, 468, "clip pagination keeps one page width and clips the rest")
            XCTAssertEqual(p.rect(forPage: 4)!.maxY, 2000 - 3 * 612, accuracy: 0.001)
            XCTAssertEqual(p.pageRange, NSRange(location: 1, length: 4))
            // Placement: horizontally centred (468 wide content in a 468 area → x 72), vertically centred.
            let loc = p.location(for: first)
            XCTAssertEqual(loc.x, 72, accuracy: 0.001)
            XCTAssertEqual(loc.y, 90, accuracy: 0.001)
            // A narrow, short view sits centred on its single page.
            let small = BarsView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
            let sp = _NSPrintPagination(view: small, info: info)
            XCTAssertEqual(sp.pageCount, 1)
            XCTAssertEqual(sp.rect(forPage: 1), NSRect(x: 0, y: 0, width: 200, height: 100))
            let sl = sp.location(for: sp.rect(forPage: 1)!)
            XCTAssertEqual(sl.x, 72 + (468 - 200) / 2, accuracy: 0.001)
            XCTAssertEqual(sl.y, 90 + (612 - 100) / 2, accuracy: 0.001)
        }
    }

    func testFitAndScalingAndAcrossThenDown() {
        MainActor.assumeIsolated {
            let view = BarsView(frame: NSRect(x: 0, y: 0, width: 936, height: 1224))
            let info = letterInfo()
            info.horizontalPagination = .fit
            let p = _NSPrintPagination(view: view, info: info)
            XCTAssertEqual(p.scale, 0.5, accuracy: 0.0001, "468 / 936")
            XCTAssertEqual(p.pageCount, 1, "at half scale the 1224 height fits the 612 page")
            XCTAssertEqual(p.rect(forPage: 1), view.bounds)
            // Automatic in both directions numbers pages across, then down.
            info.horizontalPagination = .automatic
            info.scalingFactor = 1
            let q = _NSPrintPagination(view: view, info: info)
            XCTAssertEqual(q.pageCount, 4, "2 across × 2 down")
            XCTAssertEqual(q.rect(forPage: 1)!.minX, 0)
            XCTAssertEqual(q.rect(forPage: 2)!.minX, 468)
            XCTAssertEqual(q.rect(forPage: 2)!.maxY, 1224)
            XCTAssertEqual(q.rect(forPage: 3)!.minX, 0)
            XCTAssertEqual(q.rect(forPage: 3)!.maxY, 612)
            // A scaling factor enlarges the content: fewer points per page.
            info.horizontalPagination = .clip
            info.scalingFactor = 2
            let r = _NSPrintPagination(view: view, info: info)
            XCTAssertEqual(r.rect(forPage: 1)!.height, 306)
            XCTAssertEqual(r.pageCount, 4)
        }
    }

    func testFlippedViewAndPageBreakAdjustment() {
        MainActor.assumeIsolated {
            let view = BarsView(frame: NSRect(x: 0, y: 0, width: 400, height: 1000))
            view.flipped = true
            // A subview straddling the first break at y = 612 (flipped: from the top).
            let child = NSView(frame: NSRect(x: 0, y: 580, width: 400, height: 70))
            view.addSubview(child)
            let info = letterInfo()
            let p = _NSPrintPagination(view: view, info: info)
            XCTAssertEqual(p.rect(forPage: 1)!.minY, 0, "page 1 is the top of a flipped view")
            XCTAssertEqual(p.rect(forPage: 1)!.maxY, 580, accuracy: 0.001, "the break moved above the subview")
            XCTAssertEqual(p.rect(forPage: 2)!.minY, 580, accuracy: 0.001)
            XCTAssertEqual(p.pageCount, 2)
            // A subview taller than the adjust limit is cut at the limit instead.
            child.frame = NSRect(x: 0, y: 400, width: 400, height: 300)
            let q = _NSPrintPagination(view: view, info: info)
            XCTAssertEqual(q.rect(forPage: 1)!.maxY, 612 - 0.2 * 612, accuracy: 0.001)
            // The same in a non-flipped view: the subview sits across y = 1000 - 612 = 388.
            view.flipped = false
            child.frame = NSRect(x: 0, y: 350, width: 400, height: 70)
            let r = _NSPrintPagination(view: view, info: info)
            XCTAssertEqual(r.rect(forPage: 1)!.minY, 420, accuracy: 0.001, "the break moved up to the subview's top edge")
        }
    }

    func testViewThatKnowsItsPages() {
        MainActor.assumeIsolated {
            let view = ThreePageView(frame: NSRect(x: 0, y: 0, width: 200, height: 300))
            let p = _NSPrintPagination(view: view, info: letterInfo())
            XCTAssertTrue(p.viewKnowsPages)
            XCTAssertEqual(p.pageCount, 3)
            XCTAssertEqual(p.rect(forPage: 2), NSRect(x: 0, y: 100, width: 200, height: 100))
            let op = NSPrintOperation(view: view, printInfo: letterInfo())
            XCTAssertEqual(op.pageRange, NSRange(location: 1, length: 3))
        }
    }

    // MARK: PDF

    func testDataWithPDFIsAOnePagePDFOfTheRect() {
        MainActor.assumeIsolated {
            let view = BarsView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            let data = view.dataWithPDF(inside: NSRect(x: 0, y: 0, width: 300, height: 200))
            XCTAssertFalse(data.isEmpty)
            XCTAssertTrue(_PDFInspector.isPDF(data))
            XCTAssertEqual(pageCount(data), 1)
            XCTAssertEqual(_PDFInspector.pageCount(data), 1)
            XCTAssertEqual(_PDFInspector.mediaBox(data), CGRect(x: 0, y: 0, width: 300, height: 200))
            XCTAssertEqual(view.drawn.count, 1)
            XCTAssertEqual(view.drawn[0], NSRect(x: 0, y: 0, width: 300, height: 200))
            let part = view.dataWithPDF(inside: NSRect(x: 50, y: 50, width: 100, height: 80))
            XCTAssertEqual(_PDFInspector.mediaBox(part), CGRect(x: 0, y: 0, width: 100, height: 80))
            // A copying operation shows no panels and reports itself as one.
            let op = NSPrintOperation.pdfOperation(with: view, inside: view.bounds, to: NSMutableData())
            XCTAssertTrue(op.isCopyingOperation)
            XCTAssertFalse(op.showsPrintPanel)
            XCTAssertFalse(op.showsProgressPanel)
            XCTAssertEqual(op.view, view)
        }
    }

    func testSaveJobWritesAMultiPagePDF() throws {
        try MainActor.assumeIsolated {
            let view = BarsView(frame: NSRect(x: 0, y: 0, width: 500, height: 2000))
            let info = letterInfo()
            info.jobDisposition = .save
            let url = tempPDF("save")
            info._jobSavingURL = url
            let op = NSPrintOperation(view: view, printInfo: info)
            op.showsPrintPanel = false
            op.showsProgressPanel = false
            op.jobTitle = "Bars"
            XCTAssertTrue(op.run())
            let data = try Data(contentsOf: url)
            XCTAssertTrue(_PDFInspector.isPDF(data))
            XCTAssertEqual(pageCount(data), 4)
            XCTAssertEqual(_PDFInspector.mediaBox(data), CGRect(x: 0, y: 0, width: 612, height: 792))
            XCTAssertEqual(view.drawn.count, 4, "each page drew once")
            XCTAssertNil(NSPrintOperation.current, "cleaned up")
            try? FileManager.default.removeItem(at: url)
            // The path form of pdfOperation.
            let path = tempPDF("path").path
            let pdfOp = NSPrintOperation.pdfOperation(with: view, inside: NSRect(x: 0, y: 0, width: 100, height: 50), toPath: path, printInfo: letterInfo())
            XCTAssertTrue(pdfOp.run())
            XCTAssertEqual(_PDFInspector.pageCount(try Data(contentsOf: URL(fileURLWithPath: path))), 1)
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    func testSpoolJobReachesThePrinterWithCopiesAndRange() {
        MainActor.assumeIsolated {
            let view = BarsView(frame: NSRect(x: 0, y: 0, width: 500, height: 2000))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            window.title = "Bars Window"
            window.contentView!.addSubview(view)   // a content view would take the window's size
            let info = letterInfo()
            let op = NSPrintOperation(view: view, printInfo: info)
            op.showsPrintPanel = false
            op.showsProgressPanel = false
            XCTAssertEqual(op.jobTitle, "Bars Window", "the window's title names the job")
            XCTAssertTrue(op.run())
            let job = printing.lastJob
            XCTAssertEqual(job?.pages, 4)
            XCTAssertEqual(job?.settings.jobTitle, "Bars Window")
            XCTAssertEqual(job?.settings.printerName, "Host Printer")
            XCTAssertEqual(job?.settings.paperSize, CGSize(width: 612, height: 792))
            XCTAssertEqual(pageCount(job!.pdf), 4)
            // Two collated copies of pages 2 to 3.
            info._copies = 2
            info._pageRange = (2, 3)
            let op2 = NSPrintOperation(view: view, printInfo: info)
            op2.showsPrintPanel = false
            op2.showsProgressPanel = false
            XCTAssertTrue(op2.run())
            XCTAssertEqual(printing.lastJob?.pages, 4, "2 pages × 2 copies")
            XCTAssertEqual(printing.lastJob?.settings.copies, 2)
            XCTAssertEqual(printing.lastJob?.settings.firstPage, 2)
            XCTAssertEqual(op2._pagesToPrint(), [2, 3])
            op2.pageOrder = .descendingPageOrder
            XCTAssertEqual(op2._pagesToPrint(), [3, 2])
            // The progress panel: one update per page, closed afterwards.
            let op3 = NSPrintOperation(view: view, printInfo: letterInfo())
            op3.showsPrintPanel = false
            XCTAssertTrue(op3.showsProgressPanel)
            XCTAssertTrue(op3.run())
            XCTAssertEqual(printing.lastJob?.pages, 4)
            XCTAssertFalse(NSApp.windows.contains { $0.title == "Print" && $0.isVisible }, "the progress panel is closed")
        }
    }

    func testHeaderAndFooterAndCancelDisposition() {
        MainActor.assumeIsolated {
            let view = BarsView(frame: NSRect(x: 0, y: 0, width: 400, height: 700))
            let info = letterInfo()
            info[.headerAndFooter] = NSNumber(value: true)
            let op = NSPrintOperation(view: view, printInfo: info)
            op.showsPrintPanel = false
            op.showsProgressPanel = false
            op.jobTitle = "With header"
            XCTAssertTrue(op.run())
            XCTAssertEqual(printing.lastJob?.pages, 2)
            XCTAssertTrue(view.pageHeader.string.hasPrefix("Untitled") || view.pageHeader.string.hasPrefix("With header") || !view.pageHeader.string.isEmpty)
            info.jobDisposition = .cancel
            let cancelled = NSPrintOperation(view: view, printInfo: info)
            cancelled.showsPrintPanel = false
            XCTAssertFalse(cancelled.run())
        }
    }

    func testTextViewPrintsItsTextAcrossPages() throws {
        try MainActor.assumeIsolated {
            let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 1600))
            text.string = (1...90).map { "Line \($0): the quick brown fox jumps over the lazy dog." }.joined(separator: "\n")
            text.layoutSubtreeIfNeeded()
            let info = letterInfo()
            info.jobDisposition = .save
            let url = tempPDF("text")
            info._jobSavingURL = url
            let op = NSPrintOperation(view: text, printInfo: info)
            op.showsPrintPanel = false
            op.showsProgressPanel = false
            XCTAssertTrue(op.run())
            let data = try Data(contentsOf: url)
            XCTAssertEqual(pageCount(data), 3, "1600 points of text on 612-point pages")
            XCTAssertGreaterThan(data.count, 1000)
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testPDFWriterProducesParseablePages() {
        MainActor.assumeIsolated {
            let w = _PDFWriter()
            w.title = "Writer (test)"
            w.beginPage(width: 200, height: 100)
            w.saveState()
            w.setFillColor(red: 1, green: 0, blue: 0)
            w.setAlpha(fill: 0.5, stroke: 1)
            w.fill([.move(CGPoint(x: 10, y: 10)), .line(CGPoint(x: 100, y: 10)), .line(CGPoint(x: 100, y: 60)), .close])
            w.setStrokeColor(red: 0, green: 0, blue: 1)
            w.setLineWidth(2)
            w.setDash(phase: 0, lengths: [4, 2])
            w.stroke([.move(CGPoint(x: 0, y: 0)), .quad(CGPoint(x: 50, y: 100), CGPoint(x: 100, y: 0)), .curve(CGPoint(x: 120, y: 30), CGPoint(x: 150, y: 30), CGPoint(x: 200, y: 0))])
            w.clipRect(CGRect(x: 0, y: 0, width: 50, height: 50))
            w.concatenate(CGAffineTransform(scaleX: 2, y: 2))
            w.restoreState()
            w.drawImage(width: 2, height: 2, rgb: Data([255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255]), alpha: Data([255, 128, 64, 0]), in: CGRect(x: 120, y: 20, width: 40, height: 40))
            w.endPage()
            w.beginPage(width: 300, height: 150)
            w.fillRect(CGRect(x: 1, y: 1, width: 10, height: 10))
            let data = w.finish()
            XCTAssertTrue(_PDFInspector.isPDF(data))
            XCTAssertEqual(_PDFInspector.pageCount(data), 2)
            XCTAssertEqual(_PDFInspector.mediaBox(data), CGRect(x: 0, y: 0, width: 200, height: 100))
            XCTAssertEqual(pageCount(data), 2, "a real parser agrees")
            #if canImport(Darwin)
            let doc = CGPDFDocument(CGDataProvider(data: data as CFData)!)!
            XCTAssertEqual(doc.page(at: 2)!.getBoxRect(.mediaBox), CGRect(x: 0, y: 0, width: 300, height: 150))
            XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("/Title (Writer \\(test\\))"), "the title is escaped")
            #endif
            let text = String(decoding: data, as: UTF8.self)
            XCTAssertTrue(text.contains("/ca 0.5"), "the ExtGState carries the fill alpha")
            XCTAssertTrue(text.contains("/SMask"), "the image got its soft mask")
            XCTAssertTrue(text.contains("[4 2] 0 d"), "the dash pattern")
        }
    }

    // MARK: Panels

    func testPrintPanelOptionsDecideWhatIsShown() {
        MainActor.assumeIsolated {
            let info = letterInfo()
            let view = BarsView(frame: NSRect(x: 0, y: 0, width: 400, height: 1300))
            let op = NSPrintOperation(view: view, printInfo: info)
            NSPrintOperation.current = op
            defer { NSPrintOperation.current = nil }
            let panel = NSPrintPanel()
            XCTAssertEqual(panel.options, [.showsCopies, .showsPageRange, .showsPreview])
            XCTAssertNil(panel.defaultButtonTitle())
            let basic = _NSPrintPanelForm(printInfo: info, options: panel.options, accessories: [], defaultButtonTitle: "Print", operation: op)
            XCTAssertNotNil(basic.copies); XCTAssertNotNil(basic.allPages); XCTAssertNotNil(basic.fromPage); XCTAssertNotNil(basic.preview)
            XCTAssertNil(basic.papers); XCTAssertNil(basic.portrait); XCTAssertNil(basic.scale)
            XCTAssertEqual(basic.pageLabel?.stringValue, "1 of 3")
            XCTAssertEqual(basic.printButton.title, "Print")
            let full = _NSPrintPanelForm(printInfo: info, options: [.showsCopies, .showsPageRange, .showsPaperSize, .showsOrientation, .showsScaling], accessories: [], defaultButtonTitle: "Go", operation: op)
            XCTAssertNotNil(full.papers); XCTAssertNotNil(full.portrait); XCTAssertNotNil(full.landscape); XCTAssertNotNil(full.scale)
            XCTAssertNil(full.preview)
            XCTAssertEqual(full.printButton.title, "Go")
            XCTAssertEqual(full.papers?.titleOfSelectedItem?.hasPrefix("US Letter"), true)
            XCTAssertEqual(full.portrait?.state, .on)
            XCTAssertEqual(full.scale?.stringValue, "100")
            XCTAssertEqual(full.printers?.titleOfSelectedItem, "Host Printer")
            // The page-setup accessory option brings paper, orientation and scale together.
            let setup = _NSPrintPanelForm(printInfo: info, options: [.showsPageSetupAccessory], accessories: [], defaultButtonTitle: "OK", operation: nil)
            XCTAssertNotNil(setup.papers); XCTAssertNotNil(setup.landscape); XCTAssertNotNil(setup.scale); XCTAssertNil(setup.copies)
            // An accessory controller's view is placed in the panel.
            final class Accessory: NSViewController, NSPrintPanelAccessorizing {
                func localizedSummaryItems() -> [[NSPrintPanel.AccessorySummaryKey: String]] { [[.itemName: "Colour", .itemDescription: "On"]] }
            }
            let accessory = Accessory()
            accessory.view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 44))
            panel.addAccessoryController(accessory)
            XCTAssertEqual(panel.accessoryControllers.count, 1)
            let withAccessory = _NSPrintPanelForm(printInfo: info, options: [], accessories: panel.accessoryControllers.map(\.view), defaultButtonTitle: "Print", operation: nil)
            XCTAssertTrue(withAccessory.panel.contentView!.subviews.contains { $0 === accessory.view })
            panel.removeAccessoryController(accessory)
            XCTAssertTrue(panel.accessoryControllers.isEmpty)
        }
    }

    func testPrintPanelAppliesEditsAndCancelRestores() {
        MainActor.assumeIsolated {
            let info = letterInfo()
            let view = BarsView(frame: NSRect(x: 0, y: 0, width: 400, height: 1300))
            let op = NSPrintOperation(view: view, printInfo: info)
            let form = _NSPrintPanelForm(printInfo: info, options: [.showsCopies, .showsPageRange, .showsPaperSize, .showsOrientation, .showsScaling], accessories: [], defaultButtonTitle: "Print", operation: op)
            var ended: NSApplication.ModalResponse? = nil
            form.onEnd = { ended = $0 }
            form.copies!.stringValue = "3"
            form.somePages!.performClick(nil)
            form.fromPage!.stringValue = "2"
            form.toPage!.stringValue = "2"
            form.landscape!.performClick(nil)
            form.scale!.stringValue = "50"
            form.papers!.selectItem(at: NSPrinter.papers.firstIndex { $0.name == NSPrinter.PaperName("iso-a4") }!)
            form.printButton.performClick(nil)
            XCTAssertEqual(ended, .OK)
            XCTAssertEqual(info._copies, 3)
            XCTAssertEqual(info._pageRange?.first, 2); XCTAssertEqual(info._pageRange?.last, 2)
            XCTAssertEqual(info.orientation, .landscape)
            XCTAssertEqual(info.paperName, NSPrinter.PaperName("iso-a4"))
            XCTAssertEqual(info.paperSize, NSSize(width: 842, height: 595))
            XCTAssertEqual(info.scalingFactor, 0.5, accuracy: 0.0001)
            XCTAssertEqual(op._paginate().pageCount, 2, "A4 landscape at 50%: 415-point printable height holds 830 view points per page, 1300 need 2")
            // Cancel puts everything back.
            let again = _NSPrintPanelForm(printInfo: info, options: [.showsCopies, .showsOrientation], accessories: [], defaultButtonTitle: "Print", operation: op)
            again.onEnd = { ended = $0 }
            again.copies!.stringValue = "9"
            again.portrait!.performClick(nil)
            XCTAssertEqual(info.orientation, .portrait, "edits apply as they are made (the preview follows)")
            again.cancelButton.performClick(nil)
            XCTAssertEqual(ended, .cancel)
            XCTAssertEqual(info._copies, 3)
            XCTAssertEqual(info.orientation, .landscape)
            XCTAssertEqual(info.paperSize, NSSize(width: 842, height: 595))
        }
    }

    func testPrintPanelAsSheetRunsTheOperationWhenPrintIsPressed() {
        MainActor.assumeIsolated {
            let view = BarsView(frame: NSRect(x: 0, y: 0, width: 500, height: 700))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Sheet Host"
            window.contentView!.addSubview(view)
            window.makeKeyAndOrderFront(nil)
            let op = NSPrintOperation(view: view, printInfo: letterInfo())
            op.showsProgressPanel = false
            var result: Bool? = nil
            op._runModal(for: window) { result = $0 }
            XCTAssertNil(result, "the sheet is up; nothing printed yet")
            XCTAssertNotNil(window.attachedSheet)
            let form = op.printPanel._currentForm!
            XCTAssertTrue(form.panel.isVisible)
            XCTAssertEqual(form.panel.sheetParent, window)
            form.printButton.performClick(nil)
            XCTAssertEqual(result, true)
            XCTAssertNil(window.attachedSheet)
            XCTAssertEqual(printing.lastJob?.settings.jobTitle, "Sheet Host")
            XCTAssertEqual(printing.lastJob?.pages, 2)
            // Cancel from the sheet: nothing printed, the delegate still hears about it.
            let before = printing.lastJob?.pages
            printing.printers = [PlatformPrinter(name: "Host Printer", type: "Host", isDefault: true)]
            let op2 = NSPrintOperation(view: view, printInfo: letterInfo())
            final class Delegate: NSObject, NSSelectorHandling {
                var ran: NSPrintOperation? = nil
                func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
                    guard NSStringFromSelector(action) == "printOperationDidRun:success:contextInfo:" else { return false }
                    ran = sender as? NSPrintOperation
                    return true
                }
            }
            let delegate = Delegate()
            op2.runModal(for: window, delegate: delegate, didRun: Selector(("printOperationDidRun:success:contextInfo:")), contextInfo: nil)
            op2.printPanel._currentForm!.cancelButton.performClick(nil)
            XCTAssertTrue(delegate.ran === op2)
            XCTAssertFalse(op2._lastRunSucceeded)
            XCTAssertEqual(printing.lastJob?.pages, before)
            window.close()
        }
    }

    func testPageLayoutSheetChangesTheSharedInfo() {
        MainActor.assumeIsolated {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            window.makeKeyAndOrderFront(nil)
            let info = letterInfo()
            let layout = NSPageLayout()
            var result: NSApplication.ModalResponse? = nil
            layout._beginSheet(with: info, modalFor: window) { result = $0 }
            let form = layout._currentForm!
            XCTAssertEqual(form.panel.title, "Page Setup")
            XCTAssertTrue(form.pdfButton.isHidden)
            XCTAssertNil(form.copies)
            form.landscape!.performClick(nil)
            form.printButton.performClick(nil)
            XCTAssertEqual(result, .OK)
            XCTAssertEqual(layout._lastReturnCode, NSApplication.ModalResponse.OK.rawValue)
            XCTAssertEqual(info.orientation, .landscape)
            XCTAssertEqual(layout.printInfo, info)
            window.close()
        }
    }

    func testPrintActionsReachTheWindowThroughTheResponderChain() {
        MainActor.assumeIsolated {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            XCTAssertTrue(window.respondsToSelectorAction(Selector(("print:"))))
            XCTAssertTrue(window.respondsToSelectorAction(Selector(("runPageLayout:"))))
            XCTAssertFalse(NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false).contentView == nil && window.contentView == nil)
        }
    }

    func testNativePanelIsAskedForWhenTheEnvironmentSaysSo() {
        MainActor.assumeIsolated {
            setenv("APPKITWIN_PRINT_PANEL", "native", 1)
            defer { unsetenv("APPKITWIN_PRINT_PANEL") }
            guard ProcessInfo.processInfo.environment["APPKITWIN_PRINT_PANEL"] == "native" else { return }   // the environment is cached on some Foundations
            let view = BarsView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
            printing.nativePanelAnswer = false
            let runs = printing.nativePanelRuns
            let op = NSPrintOperation(view: view, printInfo: letterInfo())
            op.showsProgressPanel = false
            XCTAssertFalse(op.run(), "the native dialog was cancelled")
            XCTAssertEqual(printing.nativePanelRuns, runs + 1)
            printing.nativePanelAnswer = true
            let op2 = NSPrintOperation(view: view, printInfo: letterInfo())
            op2.showsProgressPanel = false
            XCTAssertTrue(op2.run())
            XCTAssertEqual(printing.lastJob?.pages, 1)
            printing.nativePanelAnswer = nil
        }
    }

    func testDocumentPrintsItsTextViewToPDFAndAsASheet() throws {
        try MainActor.assumeIsolated {
            let doc = PrintableDocument()
            doc.makeWindowControllers()
            doc.printInfo.paperName = NSPrinter.PaperName("na-letter")
            doc.printInfo.orientation = .portrait
            doc.printInfo.printer = NSPrinter(name: "Host Printer")!
            // The TextEdit route: the document's own print operation, saved to a file.
            let url = tempPDF("document")
            doc.print(withSettings: [.jobDisposition: NSPrintInfo.JobDisposition.save.rawValue, .jobSavingURL: url], showPrintPanel: false, delegate: nil, didPrint: nil, contextInfo: nil)
            let data = try Data(contentsOf: url)
            XCTAssertTrue(_PDFInspector.isPDF(data))
            XCTAssertEqual(pageCount(data), 3, "1600 points of text on 612-point pages")
            try? FileManager.default.removeItem(at: url)
            // A document without a print operation presents an error instead of crashing.
            final class Plain: NSDocument {}
            XCTAssertThrowsError(try Plain().printOperation(withSettings: [:]))
            // File > Print… on a visible document window: the panel as a sheet, Print spools.
            doc.showWindows()
            let window = doc.windowForSheet!
            XCTAssertTrue(window.isVisible)
            XCTAssertFalse(window.respondsToSelectorAction(Selector(("print:"))), "a document's window leaves print: to the document")
            XCTAssertTrue(doc.respondsToSelectorAction(Selector(("printDocument:"))))
            XCTAssertTrue(window.tryToPerform(Selector(("print:")), with: nil), "print: walks the chain to the document")
            XCTAssertNotNil(window.attachedSheet)
            let op = NSPrintOperation.current!
            XCTAssertEqual(op.jobTitle, "Untitled", "the controller names the window after the document")
            op.printPanel._currentForm!.printButton.performClick(nil)
            XCTAssertNil(window.attachedSheet)
            XCTAssertEqual(printing.lastJob?.pages, 3)
            XCTAssertEqual(printing.lastJob?.settings.jobTitle, "Untitled")
            // Page Setup as a sheet changes the document's print info.
            doc.runPageLayout(nil)
            XCTAssertNotNil(window.attachedSheet)
            let layoutForm = (window.attachedSheet!.contentView!.subviews.compactMap { $0 as? NSButton }).first { $0.title == "Landscape" }
            layoutForm!.performClick(nil)
            (window.attachedSheet!.contentView!.subviews.compactMap { $0 as? NSButton }).first { $0.title == "OK" }!.performClick(nil)
            XCTAssertNil(window.attachedSheet)
            XCTAssertEqual(doc.printInfo.orientation, .landscape)
            XCTAssertEqual(doc.printInfo.paperSize, NSSize(width: 792, height: 612))
            doc.close()
        }
    }
}
