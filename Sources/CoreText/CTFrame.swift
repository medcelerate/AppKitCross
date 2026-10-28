// CTFramesetter and CTFrame (CTFramesetter.h, CTFrame.h): paragraphs of lines laid out
// in a path's bounding box. Line origins are relative to that box's origin, as on Apple
// platforms (CTFrameDraw adds the offset itself).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/coretext/ctframe
public final class CTFrame: NSObject {
    let lines: [CTLine]
    let origins: [CGPoint]
    let path: CGPath
    let bounds: CGRect
    let stringRange: NSRange
    let visibleRange: NSRange
    let attributes: NSDictionary?

    init(lines: [CTLine], origins: [CGPoint], path: CGPath, bounds: CGRect, stringRange: NSRange, visibleRange: NSRange, attributes: NSDictionary?) {
        self.lines = lines
        self.origins = origins
        self.path = path
        self.bounds = bounds
        self.stringRange = stringRange
        self.visibleRange = visibleRange
        self.attributes = attributes
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/coretext/ctframesetter
public final class CTFramesetter: NSObject {
    let typesetter: CTTypesetter
    init(typesetter: CTTypesetter) { self.typesetter = typesetter }

    private func paragraphStyle(at index: Int) -> CTParagraphStyle? {
        let count = typesetter.text.count
        guard count > 0 else { return nil }
        return typesetter.attributed.attribute(.ctParagraphStyle, at: min(index, count - 1), effectiveRange: nil) as? CTParagraphStyle
    }

    /// Lays `range` out in `rect`; `unbounded` ignores the height (used to measure).
    func layout(range: NSRange, rect: CGRect, unbounded: Bool) -> (lines: [CTLine], origins: [CGPoint], visible: NSRange) {
        let text = typesetter.text
        let end = range.length == 0 ? text.count : min(text.count, range.location + range.length)
        var index = range.location
        var lines: [CTLine] = [], origins: [CGPoint] = []
        var y = rect.height
        var paragraphStart = true
        var previousSpacing: CGFloat = 0
        repeat {
            let style = paragraphStyle(at: index)
            let head = paragraphStart ? (style?.firstLineHeadIndent ?? 0) : (style?.headIndent ?? 0)
            let tail = style?.tailIndent ?? 0
            let width = max(0, (tail > 0 ? tail : rect.width + tail) - head)
            let mode = style?.lineBreakMode ?? .byWordWrapping
            var count: Int
            switch mode {
            case .byClipping, .byTruncatingHead, .byTruncatingTail, .byTruncatingMiddle:
                // One line per paragraph, cut to the width.
                count = 0
                while index + count < end {
                    let nl = typesetter.newlineLength(at: index + count)
                    if nl > 0 { count += nl; break }
                    count += 1
                }
            case .byCharWrapping:
                count = CTTypesetterSuggestClusterBreak(typesetter, index, Double(width))
            case .byWordWrapping:
                count = CTTypesetterSuggestLineBreak(typesetter, index, Double(width))
            }
            if index + count > end { count = end - index }
            var line = CTTypesetterCreateLine(typesetter, CFRange(location: index, length: count))
            switch mode {
            case .byTruncatingHead: line = CTLineCreateTruncatedLine(line, Double(width), .start, nil) ?? line
            case .byTruncatingTail: line = CTLineCreateTruncatedLine(line, Double(width), .end, nil) ?? line
            case .byTruncatingMiddle: line = CTLineCreateTruncatedLine(line, Double(width), .middle, nil) ?? line
            default: break
            }
            var ascent = line.ascent, descent = line.descent, leading = line.leading
            if let s = style {
                let multiple = s.lineHeightMultiple
                if multiple > 0 { ascent *= multiple; descent *= multiple }
                let height = ascent + descent + leading
                if s.maximumLineHeight > 0, height > s.maximumLineHeight { let d = height - s.maximumLineHeight; ascent -= d }
                if s.minimumLineHeight > 0, height < s.minimumLineHeight { ascent += s.minimumLineHeight - height }
            }
            let spacingBefore = paragraphStart ? (style?.paragraphSpacingBefore ?? 0) : 0
            let lineTop = y - previousSpacing - spacingBefore
            if !unbounded, !lines.isEmpty, lineTop - ascent - descent < 0 { break }
            let flush: CGFloat
            switch style?.alignment ?? .natural {
            case .center: flush = 0.5
            case .right: flush = 1
            default: flush = 0
            }
            if style?.alignment == .justified, index + count < end, typesetter.newlineLength(at: index + count - 1) == 0 {
                line = CTLineCreateJustifiedLine(line, 1, Double(width)) ?? line
            }
            let x = head + CGFloat(CTLineGetPenOffsetForFlush(line, flush, Double(width)))
            let origin = CGPoint(x: x, y: lineTop - ascent)
            lines.append(line)
            origins.append(origin)
            y = origin.y - descent - leading
            let endedParagraph = count > 0 && typesetter.newlineLength(at: index + count - 1) > 0
            previousSpacing = (style?.lineSpacing ?? 0) + (endedParagraph ? (style?.paragraphSpacing ?? 0) : 0)
            paragraphStart = endedParagraph
            index += max(count, 1)
        } while index < end
        let visibleEnd = lines.last.map { $0.stringRange.location + $0.stringRange.length } ?? range.location
        return (lines, origins, NSRange(location: range.location, length: visibleEnd - range.location))
    }
}

public func CTFramesetterGetTypeID() -> CFTypeID { 7 }
public func CTFrameGetTypeID() -> CFTypeID { 8 }

public func CTFramesetterCreateWithAttributedString(_ attrString: CFAttributedString) -> CTFramesetter {
    CTFramesetter(typesetter: CTTypesetter(attributedString: attrString))
}

public func CTFramesetterCreateWithTypesetter(_ typesetter: CTTypesetter) -> CTFramesetter {
    CTFramesetter(typesetter: typesetter)
}

public func CTFramesetterGetTypesetter(_ framesetter: CTFramesetter) -> CTTypesetter { framesetter.typesetter }

public func CTFramesetterCreateFrame(_ framesetter: CTFramesetter, _ stringRange: CFRange, _ path: CGPath, _ frameAttributes: CFDictionary?) -> CTFrame {
    let bounds = path.boundingBoxOfPath
    let r = framesetter.layout(range: stringRange.nsRange, rect: bounds, unbounded: false)
    return CTFrame(lines: r.lines, origins: r.origins, path: path, bounds: bounds, stringRange: stringRange.nsRange, visibleRange: r.visible, attributes: frameAttributes)
}

public func CTFramesetterSuggestFrameSizeWithConstraints(_ framesetter: CTFramesetter, _ stringRange: CFRange, _ frameAttributes: CFDictionary?, _ constraints: CGSize, _ fitRange: UnsafeMutablePointer<CFRange>?) -> CGSize {
    // "Unbounded" is a large finite extent so the arithmetic below keeps its precision.
    let unboundedHeight = constraints.height >= 1e7 || constraints.height <= 0
    let width = constraints.width >= 1e7 || constraints.width <= 0 ? 1e7 : constraints.width
    let rect = CGRect(x: 0, y: 0, width: width, height: unboundedHeight ? 1e7 : constraints.height)
    let r = framesetter.layout(range: stringRange.nsRange, rect: rect, unbounded: unboundedHeight)
    fitRange?.pointee = CFRange(r.visible)
    guard let last = r.lines.last, let lastOrigin = r.origins.last else { return .zero }
    var maxWidth: CGFloat = 0
    for (i, l) in r.lines.enumerated() { maxWidth = max(maxWidth, r.origins[i].x + l.width - l.trailingWhitespaceWidth) }
    let height = rect.height - (lastOrigin.y - last.descent - last.leading)
    return CGSize(width: min(maxWidth.rounded(.up), width), height: height.rounded(.up))
}

public func CTFrameGetStringRange(_ frame: CTFrame) -> CFRange { CFRange(frame.stringRange) }
public func CTFrameGetVisibleStringRange(_ frame: CTFrame) -> CFRange { CFRange(frame.visibleRange) }
public func CTFrameGetPath(_ frame: CTFrame) -> CGPath { frame.path }
public func CTFrameGetFrameAttributes(_ frame: CTFrame) -> CFDictionary? { frame.attributes }
public func CTFrameGetLines(_ frame: CTFrame) -> CFArray { frame.lines as NSArray }

public func CTFrameGetLineOrigins(_ frame: CTFrame, _ range: CFRange, _ origins: UnsafeMutablePointer<CGPoint>) {
    let lo = max(0, min(range.location, frame.origins.count))
    let hi = range.length == 0 ? frame.origins.count : min(frame.origins.count, lo + range.length)
    for (n, i) in (lo..<hi).enumerated() { origins[n] = frame.origins[i] }
}

public func CTFrameDraw(_ frame: CTFrame, _ context: CGContext) {
    context.saveGState()
    context.addPath(frame.path)
    context.clip()
    for (i, line) in frame.lines.enumerated() {
        context.textPosition = CGPoint(x: frame.bounds.minX + frame.origins[i].x, y: frame.bounds.minY + frame.origins[i].y)
        CTLineDraw(line, context)
    }
    context.restoreGState()
}
