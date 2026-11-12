// PDF documents for the print backends (ADR-0022): Apple's CGPDFContext on the macOS
// host, Cairo's PDF surface on Linux, and on Windows the pure-Swift writer fed by a
// recording CGContext (Support/PDFWriter.swift). Every backend makes its documents here,
// so "Save as PDF", `dataWithPDF` and the Linux CUPS job share one path per platform.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

@MainActor
enum _PlatformPDF {
    /// A PDF document, or nil when the platform cannot write one.
    static func makeDocument(title: String?) -> (any PlatformPrintDocument)? {
        #if canImport(Darwin)
        return _ApplePDFDocument(title: title)
        #elseif os(Linux)
        return _CairoPDFDocument(title: title)
        #elseif os(Windows)
        return _RecordedPDFDocument(title: title)
        #else
        return nil
        #endif
    }
}

#if canImport(Darwin)
/// Apple's PDF context, one page per `beginPage`.
@MainActor
final class _ApplePDFDocument: PlatformPrintDocument {
    private let data = NSMutableData()
    private var context: CGContext?
    private var pageOpen = false
    private var finished = false
    private let title: String?

    init(title: String?) { self.title = title }

    func beginPage(size: CGSize) -> CGContext? {
        var box = CGRect(origin: .zero, size: size)
        if context == nil {
            guard let consumer = CGDataConsumer(data: data), let ctx = CGContext(consumer: consumer, mediaBox: &box, [kCGPDFContextTitle as String: title ?? ""] as CFDictionary) else { return nil }
            context = ctx
        }
        guard let ctx = context else { return nil }
        let boxData = withUnsafeBytes(of: &box) { Data($0) }
        ctx.beginPDFPage([kCGPDFContextMediaBox as String: boxData as CFData] as CFDictionary)
        pageOpen = true
        return ctx
    }

    func endPage() {
        guard pageOpen, let ctx = context else { return }
        ctx.endPDFPage()
        pageOpen = false
    }

    func finish() -> Data? {
        guard !finished else { return data as Data }
        finished = true
        if pageOpen { endPage() }
        guard let ctx = context else { return nil }
        ctx.closePDF()
        return data as Data
    }

    func cancel() {
        if pageOpen { endPage() }
        context?.closePDF()
        context = nil
        finished = true
    }
}
#endif

#if os(Linux)
import CCairo

/// Cairo's PDF surface, written to a temporary file and read back on `finish`.
@MainActor
final class _CairoPDFDocument: PlatformPrintDocument {
    private let path: String
    private var surface: OpaquePointer?
    private var cr: OpaquePointer?
    private var context: CGContext?
    private var pageOpen = false
    private var finished = false

    init?(title: String?) {
        path = NSTemporaryDirectory() + "/appkitcross-print-\(UUID().uuidString).pdf"
        guard let s = cairo_pdf_surface_create(path, 612, 792) else { return nil }
        surface = s
        // PDF 1.4: no object streams, so page objects stay readable by the inspector
        // (`_PDFInspector`) and by every viewer; content streams are still deflated.
        cairo_pdf_surface_restrict_to_version(s, CAIRO_PDF_VERSION_1_4)
        if let t = title, !t.isEmpty {
            cairo_pdf_surface_set_metadata(s, CAIRO_PDF_METADATA_TITLE, t)
        }
        cairo_pdf_surface_set_metadata(s, CAIRO_PDF_METADATA_CREATOR, "AppKitCross")
        cr = cairo_create(s)
    }

    func beginPage(size: CGSize) -> CGContext? {
        guard let surface, let cr, !finished else { return nil }
        if pageOpen { endPage() }
        cairo_pdf_surface_set_size(surface, Double(size.width), Double(size.height))
        cairo_identity_matrix(cr)
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
        let ctx = CGContext(cairo: cr, baseTransform: flip, width: Int(size.width.rounded(.up)), height: Int(size.height.rounded(.up)))
        context = ctx
        pageOpen = true
        return ctx
    }

    func endPage() {
        guard pageOpen, let cr else { return }
        context = nil
        cairo_show_page(cr)
        pageOpen = false
    }

    func finish() -> Data? {
        guard !finished else { return nil }
        if pageOpen { endPage() }
        finished = true
        close()
        let data = FileManager.default.contents(atPath: path)
        try? FileManager.default.removeItem(atPath: path)
        return data
    }

    func cancel() {
        context = nil
        finished = true
        close()
        try? FileManager.default.removeItem(atPath: path)
    }

    private func close() {
        if let cr { cairo_destroy(cr) }
        cr = nil
        if let surface { cairo_surface_finish(surface); cairo_surface_destroy(surface) }
        surface = nil
    }
}
#endif

#if os(Windows)
/// The PDF writer fed by a recording CGContext: every page is drawn into an offscreen
/// Direct2D bitmap (discarded) while the context forwards its paths, clips, transforms,
/// images and text to `_PDFRecorder`.
@MainActor
final class _RecordedPDFDocument: PlatformPrintDocument {
    private let writer = _PDFWriter()
    private var recorder: _PDFRecorder?
    private var context: CGContext?
    private var finished = false

    init(title: String?) { writer.title = title }

    func beginPage(size: CGSize) -> CGContext? {
        guard !finished else { return nil }
        if context != nil { endPage() }
        let w = max(1, Int(size.width.rounded(.up))), h = max(1, Int(size.height.rounded(.up)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: 0) else { return nil }
        writer.beginPage(width: size.width, height: size.height)
        let r = _PDFRecorder(writer: writer)
        recorder = r
        ctx._recorder = r
        context = ctx
        return ctx
    }

    func endPage() {
        context?._recorder = nil
        context = nil
        recorder = nil
        writer.endPage()
    }

    func finish() -> Data? {
        guard !finished else { return nil }
        if context != nil { endPage() }
        finished = true
        return writer.finish()
    }

    func cancel() {
        context?._recorder = nil
        context = nil
        finished = true
    }
}

/// Translates the recording CGContext's calls into PDF content.
final class _PDFRecorder: CGContextRecorder {
    private let writer: _PDFWriter
    private var alpha: (CGFloat, CGFloat) = (-1, -1)
    init(writer: _PDFWriter) { self.writer = writer }

    /// The path's elements through `applyWithBlock`, the CoreGraphics API the port's CGPath shares with Apple's.
    private func elements(_ path: CGPath) -> [_PDFPathElement] {
        var out: [_PDFPathElement] = []
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint: out.append(.move(e.points[0]))
            case .addLineToPoint: out.append(.line(e.points[0]))
            case .addQuadCurveToPoint: out.append(.quad(e.points[0], e.points[1]))
            case .addCurveToPoint: out.append(.curve(e.points[0], e.points[1], e.points[2]))
            case .closeSubpath: out.append(.close)
            }
        }
        return out
    }
    private func setAlpha(fill: CGFloat, stroke: CGFloat) {
        if alpha != (fill, stroke) { writer.setAlpha(fill: fill, stroke: stroke); alpha = (fill, stroke) }
    }

    func recordSave() { writer.saveState() }
    func recordRestore() { writer.restoreState(); alpha = (-1, -1) }
    func recordConcatenate(_ t: CGAffineTransform) { writer.concatenate(t) }
    func recordFill(_ path: CGPath, rule: CGPathFillRule, color: CGColor, alpha: CGFloat) {
        let (r, g, b, a) = color.rgba
        guard a * alpha > 0 else { return }
        writer.setFillColor(red: r, green: g, blue: b)
        setAlpha(fill: a * alpha, stroke: self.alpha.1 < 0 ? 1 : self.alpha.1)
        writer.fill(elements(path), evenOdd: rule == .evenOdd)
    }
    func recordStroke(_ path: CGPath, color: CGColor, alpha: CGFloat, width: CGFloat, cap: CGLineCap, join: CGLineJoin, miterLimit: CGFloat, dashPhase: CGFloat, dashLengths: [CGFloat]) {
        let (r, g, b, a) = color.rgba
        guard a * alpha > 0 else { return }
        writer.setStrokeColor(red: r, green: g, blue: b)
        setAlpha(fill: self.alpha.0 < 0 ? 1 : self.alpha.0, stroke: a * alpha)
        writer.setLineWidth(width)
        writer.setLineCap(cap == .round ? 1 : cap == .square ? 2 : 0)
        writer.setLineJoin(join == .round ? 1 : join == .bevel ? 2 : 0)
        writer.setMiterLimit(miterLimit)
        writer.setDash(phase: dashPhase, lengths: dashLengths)
        writer.stroke(elements(path))
    }
    func recordClip(_ path: CGPath, rule: CGPathFillRule) { writer.clip(elements(path), evenOdd: rule == .evenOdd) }
    func recordClip(rect: CGRect) { writer.clipRect(rect) }
    func recordImage(_ image: CGImage, in rect: CGRect, alpha: CGFloat, flippedRows: Bool) {
        // The port's images are premultiplied BGRA, top row first.
        let w = image.width, h = image.height
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        var mask = [UInt8](repeating: 0, count: w * h)
        var opaque = true
        let src = [UInt8](image.data)
        for y in 0..<h {
            let row = flippedRows ? h - 1 - y : y
            for x in 0..<w {
                let i = row * image.bytesPerRow + x * 4
                guard i + 3 < src.count else { continue }
                let b = CGFloat(src[i]), g = CGFloat(src[i + 1]), r = CGFloat(src[i + 2]), a = CGFloat(src[i + 3])
                let o = y * w + x
                let un: CGFloat = a > 0 ? 255 / a : 0
                rgb[o * 3] = UInt8(min(255, r * un)); rgb[o * 3 + 1] = UInt8(min(255, g * un)); rgb[o * 3 + 2] = UInt8(min(255, b * un))
                mask[o] = UInt8(min(255, a * alpha))
                if a < 255 || alpha < 1 { opaque = false }
            }
        }
        writer.drawImage(width: w, height: h, rgb: Data(rgb), alpha: opaque ? nil : Data(mask), in: rect)
    }
}
#endif
