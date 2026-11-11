// CTRun and CTLine (CTRun.h, CTLine.h).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/coretext/ctrun
public final class CTRun: NSObject {
    let font: CTFont
    let attributes: [NSAttributedString.Key: Any]
    let glyphs: ContiguousArray<CGGlyph>
    /// Relative to the line origin (CTRunGetPositions).
    let positions: ContiguousArray<CGPoint>
    let advances: ContiguousArray<CGSize>
    let stringIndices: ContiguousArray<CFIndex>
    let isWhitespace: [Bool]
    let stringRange: NSRange
    let status: CTRunStatus

    init(font: CTFont, attributes: [NSAttributedString.Key: Any], glyphs: [CGGlyph], positions: [CGPoint], advances: [CGSize], stringIndices: [Int], isWhitespace: [Bool], stringRange: NSRange, status: CTRunStatus) {
        self.font = font
        self.attributes = attributes
        self.glyphs = ContiguousArray(glyphs)
        self.positions = ContiguousArray(positions)
        self.advances = ContiguousArray(advances)
        self.stringIndices = ContiguousArray(stringIndices)
        self.isWhitespace = isWhitespace
        self.stringRange = stringRange
        self.status = status
    }

    var width: CGFloat { advances.reduce(0) { $0 + $1.width } }

    /// A copy with the given glyph subrange, repositioned to start at `x`.
    func slice(_ range: Range<Int>, startingAt x: CGFloat) -> CTRun {
        let dx = x - (positions[range.lowerBound].x)
        let p = positions[range].map { CGPoint(x: $0.x + dx, y: $0.y) }
        let lo = stringIndices[range].min() ?? stringRange.location
        let hi = (stringIndices[range].max() ?? lo)
        return CTRun(font: font, attributes: attributes, glyphs: Array(glyphs[range]), positions: p, advances: Array(advances[range]),
                     stringIndices: Array(stringIndices[range]), isWhitespace: Array(isWhitespace[range]), stringRange: NSRange(location: lo, length: max(1, hi - lo + 1)), status: status)
    }

    func resolvedRange(_ r: CFRange) -> Range<Int> {
        let lo = max(0, min(r.location, glyphs.count))
        let hi = r.length == 0 ? glyphs.count : max(lo, min(glyphs.count, r.location + r.length))
        return lo..<hi
    }

    var foregroundColor: CGColor? {
        attributes[.ctForegroundColor] as? CGColor
    }

    /// Draws glyphs `range` at `origin` (the line origin in `ctx` user space).
    func draw(in ctx: CGContext, range: CFRange, origin: CGPoint, lineAscent: CGFloat, lineDescent: CGFloat) {
        let r = resolvedRange(range)
        guard !r.isEmpty, attributes[.ctRunDelegate] == nil else { return }   // a delegate's space draws nothing
        let m = ctx.textMatrix
        let color: CGColor = {
            if let c = foregroundColor { return c }
            return ctx._fillColor
        }()
        let x0 = positions[r.lowerBound].x, x1 = positions[r.upperBound - 1].x + advances[r.upperBound - 1].width
        if let bg = attributes[.ctBackgroundColor] as? CGColor {
            ctx.saveGState()
            ctx.setFillColor(bg)
            ctx.fill(CGRect(x: origin.x + x0, y: origin.y - lineDescent, width: x1 - x0, height: lineAscent + lineDescent))
            ctx.restoreGState()
        }
        var absolute: [CGPoint] = []
        var drawn: [CGGlyph] = []
        absolute.reserveCapacity(r.count)
        for i in r {
            // Whitespace has no ink; tabs and line breaks would show the font's missing-glyph box.
            if isWhitespace[i] { continue }
            let p = positions[i].applying(m)
            absolute.append(CGPoint(x: origin.x + p.x, y: origin.y + p.y))
            drawn.append(glyphs[i])
        }
        font.engine.draw(glyphs: drawn, positions: absolute, color: color, in: ctx)
        if let styleValue = _ctNumber(attributes[.ctUnderlineStyle]).map({ Int32($0) }), styleValue != 0 {
            let style = CTUnderlineStyle(rawValue: styleValue & 0xFF)
            let thickness = max(0.5, font.engine.underlineThickness) * (style.contains(.thick) ? 2 : 1)
            let y = origin.y + positions[r.lowerBound].y + font.engine.underlinePosition - thickness / 2
            ctx.saveGState()
            ctx.setFillColor((attributes[.ctUnderlineColor] as? CGColor) ?? color)
            ctx.fill(CGRect(x: origin.x + x0, y: y, width: x1 - x0, height: thickness))
            if style.rawValue & CTUnderlineStyle.double.rawValue == CTUnderlineStyle.double.rawValue {
                ctx.fill(CGRect(x: origin.x + x0, y: y - thickness * 2, width: x1 - x0, height: thickness))
            }
            ctx.restoreGState()
        }
    }
}

public func CTRunGetTypeID() -> CFTypeID { 5 }
public func CTRunGetGlyphCount(_ run: CTRun) -> CFIndex { run.glyphs.count }
public func CTRunGetAttributes(_ run: CTRun) -> CFDictionary {
    var d: [String: Any] = [:]
    for (k, v) in run.attributes { d[k.rawValue] = v }
    return d as NSDictionary
}
public func CTRunGetStatus(_ run: CTRun) -> CTRunStatus { run.status }

// The *Ptr accessors hand out the run's own storage, which lives as long as the run.
public func CTRunGetGlyphsPtr(_ run: CTRun) -> UnsafePointer<CGGlyph>? { run.glyphs.withUnsafeBufferPointer { $0.baseAddress } }
public func CTRunGetPositionsPtr(_ run: CTRun) -> UnsafePointer<CGPoint>? { run.positions.withUnsafeBufferPointer { $0.baseAddress } }
public func CTRunGetAdvancesPtr(_ run: CTRun) -> UnsafePointer<CGSize>? { run.advances.withUnsafeBufferPointer { $0.baseAddress } }
public func CTRunGetStringIndicesPtr(_ run: CTRun) -> UnsafePointer<CFIndex>? { run.stringIndices.withUnsafeBufferPointer { $0.baseAddress } }

public func CTRunGetGlyphs(_ run: CTRun, _ range: CFRange, _ buffer: UnsafeMutablePointer<CGGlyph>) {
    for (n, i) in run.resolvedRange(range).enumerated() { buffer[n] = run.glyphs[i] }
}
public func CTRunGetPositions(_ run: CTRun, _ range: CFRange, _ buffer: UnsafeMutablePointer<CGPoint>) {
    for (n, i) in run.resolvedRange(range).enumerated() { buffer[n] = run.positions[i] }
}
public func CTRunGetAdvances(_ run: CTRun, _ range: CFRange, _ buffer: UnsafeMutablePointer<CGSize>) {
    for (n, i) in run.resolvedRange(range).enumerated() { buffer[n] = run.advances[i] }
}
public func CTRunGetStringIndices(_ run: CTRun, _ range: CFRange, _ buffer: UnsafeMutablePointer<CFIndex>) {
    for (n, i) in run.resolvedRange(range).enumerated() { buffer[n] = run.stringIndices[i] }
}
public func CTRunGetBaseAdvancesAndOrigins(_ runRef: CTRun, _ range: CFRange, _ advancesBuffer: UnsafeMutablePointer<CGSize>?, _ originsBuffer: UnsafeMutablePointer<CGPoint>?) {
    for (n, i) in runRef.resolvedRange(range).enumerated() { advancesBuffer?[n] = runRef.advances[i]; originsBuffer?[n] = .zero }
}
public func CTRunGetStringRange(_ run: CTRun) -> CFRange { CFRange(run.stringRange) }

public func CTRunGetTypographicBounds(_ run: CTRun, _ range: CFRange, _ ascent: UnsafeMutablePointer<CGFloat>?, _ descent: UnsafeMutablePointer<CGFloat>?, _ leading: UnsafeMutablePointer<CGFloat>?) -> Double {
    ascent?.pointee = run.font.engine.ascent
    descent?.pointee = run.font.engine.descent
    leading?.pointee = run.font.engine.leading
    return run.resolvedRange(range).reduce(0.0) { $0 + Double(run.advances[$1].width) }
}

public func CTRunGetImageBounds(_ run: CTRun, _ context: CGContext?, _ range: CFRange) -> CGRect {
    let r = run.resolvedRange(range)
    guard !r.isEmpty else { return .null }
    let rects = run.font.engine.boundingRects(for: Array(run.glyphs[r]))
    var bounds = CGRect.null
    for (n, i) in r.enumerated() { bounds = bounds.union(rects[n].offsetBy(dx: run.positions[i].x, dy: run.positions[i].y)) }
    if let context { bounds = bounds.offsetBy(dx: context.textPosition.x, dy: context.textPosition.y) }
    return bounds
}

public func CTRunGetTextMatrix(_ run: CTRun) -> CGAffineTransform { run.font.matrix }

public func CTRunDraw(_ run: CTRun, _ context: CGContext, _ range: CFRange) {
    run.draw(in: context, range: range, origin: context.textPosition, lineAscent: run.font.engine.ascent, lineDescent: run.font.engine.descent)
}

/// - SeeAlso: https://developer.apple.com/documentation/coretext/ctline
public final class CTLine: NSObject {
    let runs: [CTRun]
    let stringRange: NSRange
    let width: CGFloat
    let trailingWhitespaceWidth: CGFloat
    let ascent: CGFloat, descent: CGFloat, leading: CGFloat
    private let fallbackFont: CTFont

    init(runs: [CTRun], stringRange: NSRange, width: CGFloat, trailingWhitespaceWidth: CGFloat, fallbackFont: CTFont) {
        self.runs = runs
        self.stringRange = stringRange
        self.width = width
        self.trailingWhitespaceWidth = trailingWhitespaceWidth
        self.fallbackFont = fallbackFont
        var a: CGFloat = 0, d: CGFloat = 0, l: CGFloat = 0
        if runs.isEmpty { a = fallbackFont.engine.ascent; d = fallbackFont.engine.descent; l = fallbackFont.engine.leading }
        for r in runs {
            if let delegate = r.attributes[.ctRunDelegate] as? CTRunDelegate {
                a = max(a, delegate.ascent); d = max(d, delegate.descent)
            } else {
                a = max(a, r.font.engine.ascent); d = max(d, r.font.engine.descent); l = max(l, r.font.engine.leading)
            }
        }
        ascent = a; descent = d; leading = l
    }

    var glyphCount: Int { runs.reduce(0) { $0 + $1.glyphs.count } }

    /// Glyph edges in visual order: (x, next x, string index) for hit testing.
    func clusters() -> [(x0: CGFloat, x1: CGFloat, index: Int)] {
        var out: [(CGFloat, CGFloat, Int)] = []
        for r in runs {
            for i in r.glyphs.indices { out.append((r.positions[i].x, r.positions[i].x + r.advances[i].width, r.stringIndices[i])) }
        }
        return out
    }

    /// The line rebuilt from glyph subranges of its runs (truncation, justification).
    static func assemble(_ pieces: [CTRun], stringRange: NSRange, fallbackFont: CTFont) -> CTLine {
        var pen: CGFloat = 0
        var runs: [CTRun] = []
        for p in pieces {
            guard !p.glyphs.isEmpty else { continue }
            runs.append(p.slice(0..<p.glyphs.count, startingAt: pen))
            pen += p.width
        }
        return CTLine(runs: runs, stringRange: stringRange, width: pen, trailingWhitespaceWidth: 0, fallbackFont: fallbackFont)
    }
}

public func CTLineGetTypeID() -> CFTypeID { 6 }

public func CTLineCreateWithAttributedString(_ attrString: CFAttributedString) -> CTLine {
    let ts = CTTypesetter(attributedString: attrString)
    return ts.makeLine(range: NSRange(location: 0, length: ts.text.count))
}

public func CTLineCreateTruncatedLine(_ line: CTLine, _ width: Double, _ truncationType: CTLineTruncationType, _ truncationToken: CTLine?) -> CTLine? {
    let limit = CGFloat(width)
    if line.width - line.trailingWhitespaceWidth <= limit { return line }
    let token: CTLine = truncationToken ?? {
        var attrs: [NSAttributedString.Key: Any] = [:]
        if let last = (truncationType == .start ? line.runs.first : line.runs.last) {
            attrs = last.attributes
            attrs[.ctFont] = last.font
        }
        return CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2026}", attributes: attrs))
    }()
    let available = limit - token.width
    guard available >= 0 else { return token.width <= limit ? token : nil }
    // Glyph pieces in visual order, each one glyph, so any prefix/suffix can be taken.
    var pieces: [(run: CTRun, index: Int, width: CGFloat)] = []
    for r in line.runs { for i in r.glyphs.indices { pieces.append((r, i, r.advances[i].width)) } }
    func take(_ indices: [Int]) -> [CTRun] {
        // Group consecutive glyphs of the same run back into runs.
        var out: [CTRun] = []
        var start = 0
        while start < indices.count {
            var end = start
            while end + 1 < indices.count, pieces[indices[end + 1]].run === pieces[indices[start]].run, pieces[indices[end + 1]].index == pieces[indices[end]].index + 1 { end += 1 }
            let run = pieces[indices[start]].run
            out.append(run.slice(pieces[indices[start]].index..<(pieces[indices[end]].index + 1), startingAt: 0))
            start = end + 1
        }
        return out
    }
    var head: [Int] = [], tail: [Int] = []
    switch truncationType {
    case .end:
        var w: CGFloat = 0
        for (n, p) in pieces.enumerated() { if w + p.width > available { break }; w += p.width; head.append(n) }
    case .start:
        var w: CGFloat = 0
        for (n, p) in pieces.enumerated().reversed() { if w + p.width > available { break }; w += p.width; tail.insert(n, at: 0) }
    case .middle:
        var w: CGFloat = 0
        var lo = 0, hi = pieces.count - 1
        var front = true
        while lo <= hi {
            let p = front ? pieces[lo] : pieces[hi]
            if w + p.width > available { break }
            w += p.width
            if front { head.append(lo); lo += 1 } else { tail.insert(hi, at: 0); hi -= 1 }
            front.toggle()
        }
    }
    let assembled = take(head) + token.runs + take(tail)
    return CTLine.assemble(assembled, stringRange: line.stringRange, fallbackFont: line.runs.first?.font ?? token.runs.first?.font ?? CTTypesetter.defaultFont)
}

public func CTLineCreateJustifiedLine(_ line: CTLine, _ justificationFactor: CGFloat, _ justificationWidth: Double) -> CTLine? {
    let content = line.width - line.trailingWhitespaceWidth
    let extra = (CGFloat(justificationWidth) - content) * min(1, max(0, justificationFactor))
    guard extra > 0 else { return line }
    // Stretch the inter-word spaces (not trailing ones).
    var spaces = 0
    for r in line.runs { for i in r.glyphs.indices where r.isWhitespace[i] && r.positions[i].x + r.advances[i].width <= content { spaces += 1 } }
    guard spaces > 0 else { return line }
    let per = extra / CGFloat(spaces)
    var pieces: [CTRun] = []
    var shift: CGFloat = 0
    for r in line.runs {
        var advances = Array(r.advances), positions = Array(r.positions)
        for i in r.glyphs.indices {
            positions[i].x += shift
            if r.isWhitespace[i] && r.positions[i].x + r.advances[i].width <= content { advances[i].width += per; shift += per }
        }
        pieces.append(CTRun(font: r.font, attributes: r.attributes, glyphs: Array(r.glyphs), positions: positions, advances: advances,
                            stringIndices: Array(r.stringIndices), isWhitespace: Array(r.isWhitespace), stringRange: r.stringRange, status: r.status))
    }
    return CTLine(runs: pieces, stringRange: line.stringRange, width: line.width + shift, trailingWhitespaceWidth: line.trailingWhitespaceWidth, fallbackFont: line.runs.first?.font ?? CTTypesetter.defaultFont)
}

public func CTLineGetGlyphCount(_ line: CTLine) -> CFIndex { line.glyphCount }
public func CTLineGetGlyphRuns(_ line: CTLine) -> CFArray { line.runs as NSArray }
public func CTLineGetStringRange(_ line: CTLine) -> CFRange { CFRange(line.stringRange) }

public func CTLineGetPenOffsetForFlush(_ line: CTLine, _ flushFactor: CGFloat, _ flushWidth: Double) -> Double {
    Double(max(0, CGFloat(flushWidth) - (line.width - line.trailingWhitespaceWidth)) * flushFactor)
}

public func CTLineDraw(_ line: CTLine, _ context: CGContext) {
    let origin = context.textPosition
    for r in line.runs { r.draw(in: context, range: CFRange(location: 0, length: 0), origin: origin, lineAscent: line.ascent, lineDescent: line.descent) }
    context.textPosition = CGPoint(x: origin.x + line.width, y: origin.y)
}

public func CTLineGetTypographicBounds(_ line: CTLine, _ ascent: UnsafeMutablePointer<CGFloat>?, _ descent: UnsafeMutablePointer<CGFloat>?, _ leading: UnsafeMutablePointer<CGFloat>?) -> Double {
    ascent?.pointee = line.ascent
    descent?.pointee = line.descent
    leading?.pointee = line.leading
    return Double(line.width)
}

public func CTLineGetBoundsWithOptions(_ line: CTLine, _ options: CTLineBoundsOptions) -> CGRect {
    if options.contains(.useGlyphPathBounds) { return CTLineGetImageBounds(line, nil) }
    let leading = options.contains(.excludeTypographicLeading) ? 0 : line.leading
    return CGRect(x: 0, y: -line.descent - leading, width: line.width, height: line.ascent + line.descent + leading)
}

public func CTLineGetTrailingWhitespaceWidth(_ line: CTLine) -> Double { Double(line.trailingWhitespaceWidth) }

public func CTLineGetImageBounds(_ line: CTLine, _ context: CGContext?) -> CGRect {
    var bounds = CGRect.null
    for r in line.runs { bounds = bounds.union(CTRunGetImageBounds(r, nil, CFRange(location: 0, length: 0))) }
    if bounds.isNull { return .null }
    if let context { bounds = bounds.offsetBy(dx: context.textPosition.x, dy: context.textPosition.y) }
    return bounds
}

public func CTLineGetStringIndexForPosition(_ line: CTLine, _ position: CGPoint) -> CFIndex {
    let cs = line.clusters()
    guard !cs.isEmpty else { return line.stringRange.location }
    if position.x < cs.first!.x0 { return line.stringRange.location }
    for c in cs where position.x < c.x1 {
        // Trailing edge of a cluster selects the next string index.
        if position.x >= (c.x0 + c.x1) / 2 { return nextIndex(after: c.index, in: line, clusters: cs) }
        return c.index
    }
    return lineEndIndex(line)
}

private func nextIndex(after index: Int, in line: CTLine, clusters: [(x0: CGFloat, x1: CGFloat, index: Int)]) -> Int {
    let later = clusters.map(\.index).filter { $0 > index }
    return later.min() ?? lineEndIndex(line)
}

/// The caret index at the end of the line: before a trailing newline, as on Apple platforms.
private func lineEndIndex(_ line: CTLine) -> Int {
    var end = line.stringRange.location + line.stringRange.length
    if let last = line.runs.last, let lastGlyph = last.glyphs.indices.last, last.advances[lastGlyph].width == 0, last.stringIndices[lastGlyph] == end - 1 { end -= 1 }
    return end
}

public func CTLineGetOffsetForStringIndex(_ line: CTLine, _ charIndex: CFIndex, _ secondaryOffset: UnsafeMutablePointer<CGFloat>?) -> CGFloat {
    let cs = line.clusters()
    var result: CGFloat = 0
    if let exact = cs.first(where: { $0.index == charIndex }) {
        result = exact.x0
    } else if charIndex >= line.stringRange.location + line.stringRange.length {
        result = line.width
    } else if let before = cs.filter({ $0.index < charIndex }).max(by: { $0.index < $1.index }) {
        result = before.x1       // inside a cluster: its trailing edge
    }
    secondaryOffset?.pointee = result
    return result
}

public typealias CTLineEnumerationBlock = (Double, CFIndex, Bool, UnsafeMutablePointer<Bool>) -> Void

public func CTLineEnumerateCaretOffsets(_ line: CTLine, _ block: CTLineEnumerationBlock) {
    var stop = false
    for c in line.clusters() {
        block(Double(c.x0), c.index, true, &stop); if stop { return }
        block(Double(c.x1), c.index, false, &stop); if stop { return }
    }
}
