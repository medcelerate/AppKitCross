// Pagination (ADR-0022): how a view's bounds become pages, shared by every backend.
//
// A view that answers `knowsPageRange(_:)` supplies its own page rects through
// `rectForPage(_:)`; otherwise the bounds are split by the paper's printable area (paper
// minus margins, within the imageable bounds) at the print info's scaling factor, with
// `.fit` shrinking the scale so the whole extent fits one page in that direction, `.clip`
// keeping one page and clipping, and `.automatic` making as many as needed, the view
// moving each break through `adjustPageHeightNew`/`adjustPageWidthNew`. Pages are
// numbered across then down, from the top of the view.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The result of paginating a view for a print info.
@MainActor
internal struct _NSPrintPagination {
    /// The page rects, in the view's bounds coordinates, in page order.
    var pageRects: [NSRect]
    /// The number of the first page (1 unless the view's `knowsPageRange` says otherwise).
    var firstPageNumber: Int
    /// The scale applied when a page is drawn (the scaling factor, reduced by `.fit`).
    var scale: CGFloat
    /// The printable area of the paper: margins applied, within the imageable bounds.
    var printableRect: NSRect
    var paperSize: NSSize
    var horizontallyCentered: Bool
    var verticallyCentered: Bool
    /// The view's own page rects (`knowsPageRange` answered true).
    var viewKnowsPages: Bool

    var pageCount: Int { pageRects.count }
    var pageRange: NSRange { NSRange(location: firstPageNumber, length: pageRects.count) }

    /// The rect of a page by its number (`firstPageNumber`-based).
    func rect(forPage page: Int) -> NSRect? {
        let i = page - firstPageNumber
        guard i >= 0, i < pageRects.count else { return nil }
        return pageRects[i]
    }

    /// Where the page's bottom-left corner lands on the paper (paper coordinates, points):
    /// the default `locationOfPrintRect` placement.
    func location(for rect: NSRect) -> NSPoint {
        let w = rect.width * scale, h = rect.height * scale
        let x = horizontallyCentered ? printableRect.minX + (printableRect.width - w) / 2 : printableRect.minX
        let y = verticallyCentered ? printableRect.minY + (printableRect.height - h) / 2 : printableRect.maxY - h
        return NSPoint(x: x, y: y)
    }

    /// The printable area for `info`: paper minus margins, inside the imageable bounds.
    static func printableRect(for info: NSPrintInfo) -> NSRect {
        let paper = info.paperSize
        let margins = NSRect(x: info.leftMargin, y: info.bottomMargin,
                             width: max(0, paper.width - info.leftMargin - info.rightMargin),
                             height: max(0, paper.height - info.topMargin - info.bottomMargin))
        let r = margins.intersection(info.imageablePageBounds)
        return r.isNull ? NSRect(origin: .zero, size: paper) : r
    }

    /// Paginates `view` for `info`. `fixedRect` prints exactly that rect on a paper of its
    /// size at scale 1 (`pdfOperation(with:inside:)`).
    init(view: NSView, info: NSPrintInfo, fixedRect: NSRect? = nil) {
        paperSize = info.paperSize
        horizontallyCentered = info.isHorizontallyCentered
        verticallyCentered = info.isVerticallyCentered
        if let fixed = fixedRect {
            paperSize = fixed.size
            printableRect = NSRect(origin: .zero, size: fixed.size)
            scale = 1
            pageRects = [fixed]
            firstPageNumber = 1
            viewKnowsPages = false
            horizontallyCentered = false
            verticallyCentered = false
            return
        }
        let printable = _NSPrintPagination.printableRect(for: info)
        printableRect = printable
        var range = NSRange(location: 1, length: 0)
        if view.knowsPageRange(&range), range.length > 0 {
            viewKnowsPages = true
            scale = info.scalingFactor
            firstPageNumber = range.location
            pageRects = (0..<range.length).map { view.rectForPage(range.location + $0) }
            return
        }
        viewKnowsPages = false
        firstPageNumber = 1
        let bounds = view.bounds
        var s = max(info.scalingFactor, 0.01)
        if info.horizontalPagination == .fit, bounds.width > 0 { s = min(s, printable.width / bounds.width) }
        if info.verticalPagination == .fit, bounds.height > 0 { s = min(s, printable.height / bounds.height) }
        scale = s
        let pageWidth = printable.width / s, pageHeight = printable.height / s
        guard pageWidth > 0, pageHeight > 0, bounds.width > 0, bounds.height > 0 else { pageRects = [bounds]; return }

        // Column breaks (left to right) and row breaks (top to bottom), in bounds coordinates.
        let columns = _NSPrintPagination.breaks(from: bounds.minX, to: bounds.maxX, page: pageWidth, automatic: info.horizontalPagination == .automatic,
                                                 limit: view.widthAdjustLimit) { proposed, top, limit in
            var next = proposed
            view.adjustPageWidthNew(&next, left: top, right: proposed, limit: limit)
            return next
        }
        let flipped = view.isFlipped
        let rows: [(CGFloat, CGFloat)]   // (minY, maxY) in bounds coordinates, top row first
        if flipped {
            rows = _NSPrintPagination.breaks(from: bounds.minY, to: bounds.maxY, page: pageHeight, automatic: info.verticalPagination == .automatic,
                                             limit: view.heightAdjustLimit) { proposed, top, limit in
                var next = proposed
                view.adjustPageHeightNew(&next, top: top, bottom: proposed, limit: limit)
                return next
            }
        } else {
            // Non-flipped: the top of the view is maxY; walk downwards.
            let down = _NSPrintPagination.breaks(from: -bounds.maxY, to: -bounds.minY, page: pageHeight, automatic: info.verticalPagination == .automatic,
                                                 limit: view.heightAdjustLimit) { proposed, top, limit in
                var next = -proposed
                view.adjustPageHeightNew(&next, top: -top, bottom: -proposed, limit: -limit)
                return -next
            }
            rows = down.map { (-$0.1, -$0.0) }
        }
        var rects: [NSRect] = []
        for row in rows {
            for col in columns {
                rects.append(NSRect(x: col.0, y: row.0, width: col.1 - col.0, height: row.1 - row.0))
            }
        }
        pageRects = rects
    }

    /// Splits `from..<to` into pages of `page` length. One page when not automatic (its
    /// extent is the content's when that is shorter than a page, so a small view centres,
    /// otherwise a whole page, clipping the rest). Automatic pages are whole pages except
    /// where `adjust` moves a break back, at most `limit` (a fraction of the page) from
    /// the proposed one, so a subview is not cut in two.
    static func breaks(from start: CGFloat, to end: CGFloat, page: CGFloat, automatic: Bool, limit fraction: CGFloat,
                       adjust: (_ proposed: CGFloat, _ top: CGFloat, _ limit: CGFloat) -> CGFloat) -> [(CGFloat, CGFloat)] {
        let extent = end - start
        guard automatic, extent > page + 0.001 else {
            return [(start, start + (extent < page ? extent : page))]
        }
        var out: [(CGFloat, CGFloat)] = []
        var top = start
        var guardCount = 0
        while top < end - 0.001 && guardCount < 10_000 {
            guardCount += 1
            var bottom = top + page
            if bottom < end {
                let limit = bottom - page * min(max(fraction, 0), 1)
                let adjusted = adjust(bottom, top, limit)
                if adjusted > top + 1, adjusted <= bottom, adjusted >= limit { bottom = adjusted }
            }
            out.append((top, bottom))
            top = bottom
        }
        return out
    }
}
