# ADR-0022: Printing

Date: 2026-11-10. Status: accepted, awaiting verification on the Windows PC.

## Context

AppKit prints through four objects: `NSPrintInfo` (paper, orientation, margins, scaling,
pagination, the printer, the job's disposition and its attribute dictionary),
`NSPrintOperation` (which paginates a view, shows the print panel, draws every page into a
printing `NSGraphicsContext` and delivers the job), `NSPrintPanel` and `NSPageLayout` (the
Print and Page Setup panels, run modally or as sheets), with `NSPrinter` naming the
devices. A view takes part through `knowsPageRange(_:)`/`rectForPage(_:)` when it lays its
own pages out, the `adjustPageHeightNew`/`adjustPageWidthNew` break hooks otherwise, and
`beginDocument`/`beginPage`/`endPage`/`endDocument`, `pageHeader`/`pageFooter` and
`drawPageBorder` around the drawing. `dataWithPDF(inside:)` and
`NSPrintOperation.pdfOperation` make PDF of a rect; `NSDocument.printDocument` and
`NSApplication.runPageLayout` are the menu's ends.

On macOS all of that sits on Core Printing and CUPS. Windows has the spooler, device
contexts, the `PrintDlgEx` dialog, the XPS print path and Direct2D's print control; Linux
has CUPS (`lp`, `lpstat`, libcups) and no system print dialog outside the toolkits. Neither
has a PDF writer in the platform: Cairo has one on Linux; Windows has XPS, and the only
XPS-to-PDF converter ships as a printer driver.

## Decision

### One pagination, one page-drawing path

`_NSPrintPagination` (NSPrintPagination.swift) is pure code shared by every backend. A view
that answers `knowsPageRange` supplies its rects; otherwise the bounds are split by the
paper's printable area (margins applied, inside the printer's imageable bounds) at the
scaling factor: `.clip` keeps one page and clips, `.fit` lowers the scale until the extent
fits one page in that direction, `.automatic` makes as many pages as needed, and each
automatic break is offered to `adjustPageHeightNew`/`adjustPageWidthNew` (the default
implementation moves a break above a subview it would cut, as far as `heightAdjustLimit`
allows, and asks the subview the same in its own coordinates). Pages are numbered across,
then down, from the top of the view whether or not it is flipped; a view smaller than a
page keeps its own extent so centring places it as AppKit does.

`NSPrintOperation.run()` shows the panel, paginates, asks the platform for a document,
then for every page (the user's range, repeated for copies, reversed for a descending
page order) begins a page, calls the view's `beginPage(in:atPlacement:)`, draws the view
hierarchy through the same `_displayHierarchy` the window uses (so layer-backed subtrees,
text, images and SwiftUI content print as they draw), draws the header and footer when
`NSPrintHeaderAndFooter` is set, and ends the page. `NSGraphicsContext.isDrawingToScreen`
is false meanwhile. The default `beginPage` places the page rect on the paper at the
operation's scale, in the superview's coordinate system, so views that override it see
what AppKit's see.

### The platform seam

`PlatformPrintBackend` (Platform/Printing.swift) answers three questions: which printers
exist, how to make a PDF document, and how to make a job on a device. Both documents are
`PlatformPrintDocument`s that hand out a `CGContext` per page (points, origin bottom-left)
and are finished or cancelled. A fourth, optional, is the platform's native print dialog,
used only when `APPKITWIN_PRINT_PANEL=native` says so.

The PDF document per platform (Platform/PDFDocument.swift):

- macOS host: Apple's `CGPDFContext`, so the tests compare against the reference writer.
- Linux: Cairo's PDF surface (`cairo_pdf_surface_create`, one `cairo_show_page` per page).
  Pango draws text into it with embedded fonts; the result is what CUPS gets.
- Windows: the package's own small PDF writer (Support/PDFWriter.swift) fed by a
  recording hook on the port's `CGContext` (`CGContextRecorder`): every path fill, stroke,
  clip, transform, alpha and image the page's context is asked for is also written as PDF
  content. Text reaches it as glyph outlines (CoreText's DirectWrite engine draws through
  the context's path calls when a recorder listens) or, for the DirectWrite layouts the
  cell text backend draws, as the layout rasterised at 4x. Fonts are not embedded, so the
  text is not selectable in the PDF; that is the trade-off against the alternative, the
  D2D print control into an XPS package that Windows cannot turn into PDF without a
  printer driver. Embedding subset fonts in the writer is the follow-up that lifts it.

Device jobs:

- Windows: Direct2D's print control (`ID2D1Device::CreatePrintControl`) over an
  `IPrintDocumentPackageTarget` for the printer (`cd2d_print_job_*` in the CD2D shim):
  every page is an `ID2D1CommandList` drawn through a `CD2DTarget` by the same `CGContext`
  the window draws with, so text, images and effects print exactly as they display, with
  the print control rasterising at 300 dpi only what Direct2D cannot express. The job goes
  to the spooler as XPS, which every Windows print driver, including Microsoft Print to
  PDF, accepts. This was chosen over `StartDoc`/`StartPage` on a printer DC because the DC
  render target rasterises whole pages and loses DirectWrite's text; the GDI route stays
  possible behind the same seam if a driver needs it.
- Linux: CUPS through its command-line tools, `lpstat -p`/`-d` for the printers and `lp`
  of the rendered PDF with the title and orientation (libcups is not linked, so a system
  without CUPS has no printers and prints to PDF).
- Host backend: a fake "Host Printer" whose jobs are kept as PDF data for the tests.

Copies are repeated by `NSPrintOperation` itself, collated, so every backend behaves the
same and a PDF of a two-copy job shows both.

### The panels

`NSPrintPanel` and `NSPageLayout` are drawn by the package on every platform
(`_NSPrintPanelForm`): printer, copies, page range, paper size (the built-in table of the
common papers by AppKit's names, "na-letter", "iso-a4", ...), orientation, scale, accessory
views, a page preview with paging rendered through the operation's own pagination, "Save as
PDF…" through `NSSavePanel`, Cancel and Print. Edits apply to the print info as they are
made so the preview follows; Cancel restores the values the panel opened with. The panel's
`options` decide which rows appear; `.showsPageSetupAccessory` brings the paper, orientation
and scale rows the Page Setup panel is made of. Both run modally (`runModal(with:)`) or as
sheets (`beginSheet(with:modalFor:delegate:didEnd:contextInfo:)`, the async forms, and
`NSPrintOperation.runModal(for:...)`), ending through the port's selector dispatch with the
panel or operation as the sender (`_lastReturnCode` / `_lastRunSucceeded` carry the code).

On Windows `APPKITWIN_PRINT_PANEL=native` runs `PrintDlgEx` instead: the printer, copies,
collation, page range, orientation and paper come back through `PlatformPrintJobSettings`
and the package's panel is skipped. Linux has no native dialog; the package's panel is it.

The progress panel (`_NSPrintProgressPanel`) is the package's too: the job title, "Page n
of m", a bar and Cancel, with the event loop pumped once per page so it repaints and the
cancel click lands.

### Without a printer

When the platform has no printers the print info's printer is the generic "PDF" printer:
Print then saves a PDF, asking for the file with `NSSavePanel` unless the job already has
`NSJobSavingURL`. `.preview` writes a temporary PDF and opens it with the platform's
viewer.

## Consequences

- `NSPrintInfo`, `NSPrinter`, `NSPrintOperation`, `NSPrintPanel` and `NSPageLayout` are
  hand-written; the Carbon `PM*` accessors, EPS operations, `NSPDFPanel` and
  `takeSettings(from:)` stay unimplemented.
- `NSWindow` answers `print:` (prints its content view) and `runPageLayout:` on the
  responder chain, so File > Print… and Page Setup… work in any application. That print
  uses the shared print info, whose default horizontal pagination is `.clip` as in AppKit:
  a window wider than the printable area loses its right side unless the application sets
  `.fit` (the HelloWindow demo does);
  `NSDocument.printDocument`/`printOperation(withSettings:error:)` land with the document
  architecture (ADR-0017) once that branch and this one are together.
- Windows PDF text is outlines or raster, not embedded fonts (see above).
- A Windows device job draws in points on Direct2D pages declared in DIPs (the job scales
  by 96/72), and carries the native dialog's DEVMODE as its print ticket
  (`PTConvertDevModeToPrintTicket`), so the driver gets the paper and orientation chosen
  there; the package panel's choices reach the driver only through the page size.
- Printer-specific papers and hardware margins are not read from the drivers yet
  (`imageablePageBounds` is the paper for the generic and host printers); the paper table
  is the port's.
- Verified: `PrintTests` (19) on macOS against Apple's PDF parser, in the Linux container
  against Cairo's writer; `HelloWindow --print-pdf` in the container produces the Layout
  Demo as a PDF whose page count the run script checks. Windows is compiled by CI and
  verified from the pull request's checklist on the PC.
