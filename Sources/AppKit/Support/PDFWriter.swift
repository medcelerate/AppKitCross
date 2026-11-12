// A small PDF writer (ADR-0022). The Windows PDF backend records what a page's
// CGContext is asked to draw and emits it through this writer; nothing here is
// platform-specific, so `PrintTests` exercise it on every host.
//
// Output is PDF 1.4 with uncompressed content streams: paths, fills, strokes, clips,
// transforms, constant alpha (ExtGState) and RGB images with an optional soft mask.
// Text arrives as filled glyph outlines or rasterised layouts (see ADR-0022 for why fonts
// are not embedded yet).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A path element in user space.
public enum _PDFPathElement: Equatable {
    case move(CGPoint)
    case line(CGPoint)
    case quad(CGPoint, CGPoint)          // control, end
    case curve(CGPoint, CGPoint, CGPoint) // control1, control2, end
    case close
}

public final class _PDFWriter {
    private var objects: [Data] = []            // object bodies, 1-based numbers
    private var pageObjects: [Int] = []
    private var content = ""                    // the current page's content stream
    private var pageSize = CGSize.zero
    private var pageOpen = false
    private var currentPoint = CGPoint.zero
    private var subpathStart = CGPoint.zero
    /// ExtGState objects by (fill alpha, stroke alpha).
    private var alphaStates: [String: Int] = [:]
    /// Image XObjects used by the current page: resource name → object number.
    private var pageImages: [(String, Int)] = []
    private var pageAlphaStates: Set<String> = []
    private var imageCounter = 0
    public var title: String? = nil

    public init() {}

    public var pageCount: Int { pageObjects.count }
    public var isPageOpen: Bool { pageOpen }

    // MARK: Pages

    public func beginPage(width: CGFloat, height: CGFloat) {
        if pageOpen { endPage() }
        pageSize = CGSize(width: width, height: height)
        content = ""
        pageImages = []
        pageAlphaStates = []
        pageOpen = true
    }

    public func endPage() {
        guard pageOpen else { return }
        pageOpen = false
        let stream = Data(content.utf8)
        let contentsNumber = addObject(streamObject(dictionary: "/Length \(stream.count)", stream: stream))
        var resources = "/ProcSet [/PDF /ImageC /ImageB]"
        if !pageAlphaStates.isEmpty {
            resources += " /ExtGState <<" + pageAlphaStates.sorted().map { " /\($0) \(alphaStates[$0]!) 0 R" }.joined() + " >>"
        }
        if !pageImages.isEmpty {
            resources += " /XObject <<" + pageImages.map { " /\($0.0) \($0.1) 0 R" }.joined() + " >>"
        }
        // The page tree object is written last; its number is reserved below (see finish).
        let page = "<< /Type /Page /Parent PAGES_REF /MediaBox [0 0 \(num(pageSize.width)) \(num(pageSize.height))] /Resources << \(resources) >> /Contents \(contentsNumber) 0 R >>"
        pageObjects.append(addObject(Data(page.utf8)))
    }

    /// Closes the document and returns its bytes.
    public func finish() -> Data {
        if pageOpen { endPage() }
        let pagesNumber = objects.count + 1
        let kids = pageObjects.map { "\($0) 0 R" }.joined(separator: " ")
        _ = addObject(Data("<< /Type /Pages /Kids [\(kids)] /Count \(pageObjects.count) >>".utf8))
        let catalogNumber = addObject(Data("<< /Type /Catalog /Pages \(pagesNumber) 0 R >>".utf8))
        var info = "<< /Producer (AppKitCross)"
        if let title, !title.isEmpty { info += " /Title (\(escape(title)))" }
        info += " >>"
        let infoNumber = addObject(Data(info.utf8))

        var out = Data("%PDF-1.4\n%\u{E2}\u{E3}\u{CF}\u{D3}\n".utf8)
        var offsets: [Int] = []
        for (i, body) in objects.enumerated() {
            offsets.append(out.count)
            out.append(Data("\(i + 1) 0 obj\n".utf8))
            if i + 1 == pagesNumber || pageObjects.contains(i + 1) {
                let text = String(decoding: body, as: UTF8.self).replacingOccurrences(of: "PAGES_REF", with: "\(pagesNumber) 0 R")
                out.append(Data(text.utf8))
            } else {
                out.append(body)
            }
            out.append(Data("\nendobj\n".utf8))
        }
        let xref = out.count
        var table = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for o in offsets { table += String(format: "%010d 00000 n \n", o) }
        table += "trailer\n<< /Size \(objects.count + 1) /Root \(catalogNumber) 0 R /Info \(infoNumber) 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        out.append(Data(table.utf8))
        return out
    }

    // MARK: Graphics state

    public func saveState() { content += "q\n" }
    public func restoreState() { content += "Q\n" }
    public func concatenate(_ t: CGAffineTransform) {
        guard t != .identity else { return }
        content += "\(num(t.a)) \(num(t.b)) \(num(t.c)) \(num(t.d)) \(num(t.tx)) \(num(t.ty)) cm\n"
    }
    public func setFillColor(red: CGFloat, green: CGFloat, blue: CGFloat) { content += "\(num(red)) \(num(green)) \(num(blue)) rg\n" }
    public func setStrokeColor(red: CGFloat, green: CGFloat, blue: CGFloat) { content += "\(num(red)) \(num(green)) \(num(blue)) RG\n" }
    public func setLineWidth(_ w: CGFloat) { content += "\(num(w)) w\n" }
    /// 0 butt, 1 round, 2 square (PDF's and CoreGraphics' numbering agree).
    public func setLineCap(_ cap: Int) { content += "\(cap) J\n" }
    /// 0 miter, 1 round, 2 bevel.
    public func setLineJoin(_ join: Int) { content += "\(join) j\n" }
    public func setMiterLimit(_ limit: CGFloat) { content += "\(num(limit)) M\n" }
    public func setDash(phase: CGFloat, lengths: [CGFloat]) {
        content += "[\(lengths.map(num).joined(separator: " "))] \(num(phase)) d\n"
    }
    /// Constant alpha for fills and strokes through a shared ExtGState.
    public func setAlpha(fill: CGFloat, stroke: CGFloat) {
        let key = "GS" + String(Int((max(0, min(1, fill)) * 1000).rounded())) + "_" + String(Int((max(0, min(1, stroke)) * 1000).rounded()))
        if alphaStates[key] == nil {
            alphaStates[key] = addObject(Data("<< /Type /ExtGState /ca \(num(fill)) /CA \(num(stroke)) >>".utf8))
        }
        pageAlphaStates.insert(key)
        content += "/\(key) gs\n"
    }

    // MARK: Paths

    private func emit(_ path: [_PDFPathElement]) {
        for e in path {
            switch e {
            case let .move(p):
                content += "\(num(p.x)) \(num(p.y)) m\n"; currentPoint = p; subpathStart = p
            case let .line(p):
                content += "\(num(p.x)) \(num(p.y)) l\n"; currentPoint = p
            case let .quad(c, p):
                // Degree elevation of the quadratic to a cubic.
                let c1 = CGPoint(x: currentPoint.x + 2.0 / 3.0 * (c.x - currentPoint.x), y: currentPoint.y + 2.0 / 3.0 * (c.y - currentPoint.y))
                let c2 = CGPoint(x: p.x + 2.0 / 3.0 * (c.x - p.x), y: p.y + 2.0 / 3.0 * (c.y - p.y))
                content += "\(num(c1.x)) \(num(c1.y)) \(num(c2.x)) \(num(c2.y)) \(num(p.x)) \(num(p.y)) c\n"; currentPoint = p
            case let .curve(c1, c2, p):
                content += "\(num(c1.x)) \(num(c1.y)) \(num(c2.x)) \(num(c2.y)) \(num(p.x)) \(num(p.y)) c\n"; currentPoint = p
            case .close:
                content += "h\n"; currentPoint = subpathStart
            }
        }
    }

    public func fill(_ path: [_PDFPathElement], evenOdd: Bool = false) {
        guard !path.isEmpty else { return }
        emit(path)
        content += evenOdd ? "f*\n" : "f\n"
    }

    public func stroke(_ path: [_PDFPathElement]) {
        guard !path.isEmpty else { return }
        emit(path)
        content += "S\n"
    }

    public func clip(_ path: [_PDFPathElement], evenOdd: Bool = false) {
        guard !path.isEmpty else { return }
        emit(path)
        content += evenOdd ? "W* n\n" : "W n\n"
    }

    public func fillRect(_ r: CGRect) {
        content += "\(num(r.minX)) \(num(r.minY)) \(num(r.width)) \(num(r.height)) re f\n"
    }

    public func clipRect(_ r: CGRect) {
        content += "\(num(r.minX)) \(num(r.minY)) \(num(r.width)) \(num(r.height)) re W n\n"
    }

    // MARK: Images

    /// Draws an RGB image (`rgb`: 3 bytes per pixel, rows top first) with an optional
    /// 8-bit alpha plane into `rect` (user space, bottom-left origin).
    public func drawImage(width: Int, height: Int, rgb: Data, alpha: Data?, in rect: CGRect) {
        guard width > 0, height > 0, rgb.count >= width * height * 3 else { return }
        var maskRef = ""
        if let alpha, alpha.count >= width * height {
            let mask = addObject(streamObject(dictionary: "/Type /XObject /Subtype /Image /Width \(width) /Height \(height) /ColorSpace /DeviceGray /BitsPerComponent 8 /Length \(alpha.count)", stream: alpha))
            maskRef = " /SMask \(mask) 0 R"
        }
        let image = addObject(streamObject(dictionary: "/Type /XObject /Subtype /Image /Width \(width) /Height \(height) /ColorSpace /DeviceRGB /BitsPerComponent 8\(maskRef) /Length \(rgb.count)", stream: rgb))
        imageCounter += 1
        let name = "Im\(imageCounter)"
        pageImages.append((name, image))
        content += "q \(num(rect.width)) 0 0 \(num(rect.height)) \(num(rect.minX)) \(num(rect.minY)) cm /\(name) Do Q\n"
    }

    // MARK: Plumbing

    @discardableResult private func addObject(_ body: Data) -> Int {
        objects.append(body)
        return objects.count
    }

    private func streamObject(dictionary: String, stream: Data) -> Data {
        var d = Data("<< \(dictionary) >>\nstream\n".utf8)
        d.append(stream)
        d.append(Data("\nendstream".utf8))
        return d
    }

    private func num(_ v: CGFloat) -> String {
        if v == v.rounded() && abs(v) < 1e9 { return String(Int(v)) }
        var s = String(format: "%.4f", Double(v))
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private func escape(_ s: String) -> String {
        var out = ""
        for ch in s.unicodeScalars {
            switch ch {
            case "(", ")", "\\": out += "\\" + String(ch)
            case _ where ch.value < 32 || ch.value > 126: out += String(format: "\\%03o", ch.value & 0xFF)
            default: out.unicodeScalars.append(ch)
            }
        }
        return out
    }
}

/// What tests and the core need to know about a PDF without a parser: the page count and
/// the first page's media box, read from the object syntax every writer here produces
/// (this writer, Cairo, Apple's CoreGraphics).
public enum _PDFInspector {
    public static func isPDF(_ data: Data) -> Bool { data.starts(with: Array("%PDF-".utf8)) }

    /// The number of `/Type /Page` objects (not `/Pages`).
    public static func pageCount(_ data: Data) -> Int {
        let text = String(decoding: data, as: UTF8.self)
        var count = 0
        var search = text.startIndex
        while let r = text.range(of: "/Type /Page", range: search..<text.endIndex) {
            let after = r.upperBound
            if after == text.endIndex || text[after] != "s" { count += 1 }
            search = after
        }
        // Apple's writer may use the compact form.
        if count == 0 {
            search = text.startIndex
            while let r = text.range(of: "/Type/Page", range: search..<text.endIndex) {
                let after = r.upperBound
                if after == text.endIndex || text[after] != "s" { count += 1 }
                search = after
            }
        }
        return count
    }

    /// The first `/MediaBox [x y w h]` found.
    public static func mediaBox(_ data: Data) -> CGRect? {
        let text = String(decoding: data, as: UTF8.self)
        guard let r = text.range(of: "/MediaBox"), let open = text[r.upperBound...].firstIndex(of: "["),
              let close = text[open...].firstIndex(of: "]") else { return nil }
        let parts = text[text.index(after: open)..<close].split(whereSeparator: { $0 == " " || $0 == "\n" }).compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2] - parts[0], height: parts[3] - parts[1])
    }
}
