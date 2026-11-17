// NSTextSelectionNavigation (hand-written; seeded from the generated stub, see tools/apigen)
// Selection movement and hit testing for TextKit 2 (ADR-0040), computed against the
// NSTextSelectionDataSource protocol: substrings for characters, words, sentences and
// paragraphs; line fragment ranges and caret offsets for lines and points. Vertical
// movement needs line geometry, which the data source protocol does not give; it uses the
// NSTextLayoutManager's lines and is unavailable (nil) with other data sources.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselectionnavigation
@available(macOS 12.0, *)
open class NSTextSelectionNavigation: NSObject {
    private weak var _dataSource: (any NSTextSelectionDataSource)?
    private var _allowsNonContiguousRanges = false
    private var _rotatesCoordinateSystemForLayoutOrientation = true

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselectionnavigation/init(datasource:)
    public init(dataSource: any NSTextSelectionDataSource) {
        _dataSource = dataSource
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselectionnavigation/textselectiondatasource
    open var textSelectionDataSource: (any NSTextSelectionDataSource)? { _dataSource }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselectionnavigation/allowsnoncontiguousranges
    open var allowsNonContiguousRanges: Bool {
        get { _allowsNonContiguousRanges }
        set { _allowsNonContiguousRanges = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselectionnavigation/rotatescoordinatesystemforlayoutorientation
    open var rotatesCoordinateSystemForLayoutOrientation: Bool {
        get { _rotatesCoordinateSystemForLayoutOrientation }
        set { _rotatesCoordinateSystemForLayoutOrientation = newValue }
    }
    /// Nothing is cached between calls: every answer comes from the data source.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselectionnavigation/flushlayoutcache()
    open func flushLayoutCache() {}

    // MARK: Offsets through the data source

    private func _offset(_ ds: any NSTextSelectionDataSource, _ location: any NSTextLocation) -> Int {
        ds.offset(from: ds.documentRange.location, to: location)
    }
    private func _location(_ ds: any NSTextSelectionDataSource, _ offset: Int) -> (any NSTextLocation)? {
        ds.location(ds.documentRange.location, offsetBy: offset)
    }
    private func _length(_ ds: any NSTextSelectionDataSource) -> Int {
        ds.offset(from: ds.documentRange.location, to: ds.documentRange.endLocation)
    }
    private func _range(_ ds: any NSTextSelectionDataSource, _ a: Int, _ b: Int) -> NSTextRange? {
        guard let s = _location(ds, min(a, b)), let e = _location(ds, max(a, b)) else { return nil }
        return NSTextRange(location: s, end: e)
    }

    /// The composed character after (or before) offset `o`.
    private func _characterStep(_ ds: any NSTextSelectionDataSource, from o: Int, forward: Bool, decomposing: Bool = false) -> Int {
        let n = _length(ds)
        if forward ? o >= n : o <= 0 { return o }
        guard let loc = _location(ds, o) else { return o }
        var target = forward ? o + 1 : o - 1
        var opts: NSString.EnumerationOptions = [.byComposedCharacterSequences, .substringNotRequired]
        if !forward { opts.insert(.reverse) }
        ds.enumerateSubstrings(from: loc, options: opts) { _, r, _, stop in
            let a = self._offset(ds, r.location), b = self._offset(ds, r.endLocation)
            target = forward ? b : a
            if decomposing, !forward, b - a > 1 { target = b - 1 }
            stop.pointee = true
        }
        return max(0, min(n, target))
    }

    /// The end of the next word (forward) or the start of the previous one (backward).
    private func _wordStep(_ ds: any NSTextSelectionDataSource, from o: Int, forward: Bool) -> Int {
        guard let loc = _location(ds, o) else { return o }
        var target = forward ? _length(ds) : 0
        var opts: NSString.EnumerationOptions = [_NSTextUnits.byWords, .substringNotRequired]
        if !forward { opts.insert(.reverse) }
        ds.enumerateSubstrings(from: loc, options: opts) { _, r, _, stop in
            let a = self._offset(ds, r.location), b = self._offset(ds, r.endLocation)
            if forward, b > o { target = b; stop.pointee = true }
            if !forward, a < o { target = a; stop.pointee = true }
        }
        return target
    }

    /// The edge of the enclosing unit; when already there, the edge of the next one.
    private func _unitStep(_ ds: any NSTextSelectionDataSource, from o: Int, forward: Bool, granularity: NSTextSelection.Granularity, contentOnly: Bool) -> Int {
        let n = _length(ds)
        func edges(_ at: Int) -> (Int, Int)? {
            guard let loc = _location(ds, max(0, min(n, at))), let r = ds.textRange(for: granularity, enclosing: loc) else { return nil }
            var a = _offset(ds, r.location), b = _offset(ds, r.endLocation)
            if contentOnly { b = _trimBreak(ds, a, b) }
            if b < a { b = a }
            return (a, b)
        }
        guard let (a, b) = edges(o) else { return o }
        if forward {
            if o < b { return b }
            if b >= n { return n }
            // Past the unit's content: the end of the next unit's.
            var fullEnd = b
            if let loc = _location(ds, o), let r = ds.textRange(for: granularity, enclosing: loc) { fullEnd = _offset(ds, r.endLocation) }
            return edges(max(fullEnd, o + 1))?.1 ?? n
        } else {
            if o > a { return a }
            guard a > 0 else { return 0 }
            return edges(a - 1)?.0 ?? 0
        }
    }

    /// `b` without a trailing line break (the caret goes before it).
    private func _trimBreak(_ ds: any NSTextSelectionDataSource, _ a: Int, _ b: Int) -> Int {
        guard b > a, let loc = _location(ds, a) else { return b }
        var trimmed = b
        ds.enumerateSubstrings(from: loc, options: [.byParagraphs, .substringNotRequired]) { _, r, _, stop in
            let e = self._offset(ds, r.endLocation)
            if e <= b { trimmed = min(b, e) }
            stop.pointee = true
        }
        return trimmed
    }

    // MARK: Vertical movement (needs the layout manager's lines)

    /// The caret x at offset `o` and its line, in container coordinates.
    private func _caretGeometry(_ ds: any NSTextSelectionDataSource, _ o: Int, upstream: Bool) -> (x: CGFloat, minY: CGFloat, maxY: CGFloat, line: NSTextLineFragment)? {
        guard let tlm = ds as? NSTextLayoutManager, let (f, li) = tlm._line(at: o, upstream: upstream) else { return nil }
        let l = f._lines[li]
        let x = f._origin.x + l.typographicBounds.minX + l._caretOffset(o - f._documentOffset)
        return (x, f._origin.y + l.typographicBounds.minY, f._origin.y + l.typographicBounds.maxY, l)
    }

    /// The caret nearest `point` in the line at its height, and whether it sits at the end
    /// of a soft-wrapped line (upstream).
    private func _verticalTarget(_ ds: any NSTextSelectionDataSource, at point: CGPoint) -> (offset: Int, upstream: Bool, line: NSTextLineFragment)? {
        guard let tlm = ds as? NSTextLayoutManager, let (f, li) = tlm._lineIndex(atY: point.y) else { return nil }
        let l = f._lines[li]
        let base = f._documentOffset
        var i = l.characterIndex(for: CGPoint(x: point.x - f._origin.x - l.typographicBounds.minX, y: 0))
        if l._line != nil, i < l._visibleEnd {
            let x0 = l._caretOffset(i), x1 = l._caretOffset(i + 1)
            let px = point.x - f._origin.x - l.typographicBounds.minX
            if x1 > x0, (px - x0) / (x1 - x0) > 0.5 { i += 1 }
        }
        i = min(i, l._visibleEnd)
        let lineEnd = l.characterRange.location + l.characterRange.length
        let upstream = l._newlineLength == 0 && i == lineEnd && li < f._lines.count - 1
        return (base + i, upstream, l)
    }

    /// The caret nearest `point` through the data source's lines and caret offsets.
    internal func _caretOffset(_ ds: any NSTextSelectionDataSource, at point: CGPoint) -> Int? {
        if let tlm = ds as? NSTextLayoutManager { return tlm._caretOffset(at: point) }
        guard let line = ds.lineFragmentRange(for: point, inContainerAt: ds.documentRange.location) else { return nil }
        var best: (d: CGFloat, o: Int)? = nil
        ds.enumerateCaretOffsetsInLineFragment(at: line.location) { x, loc, _, _ in
            let d = abs(x - point.x)
            if best == nil || d < best!.d { best = (d, self._offset(ds, loc)) }
        }
        return best?.o
    }

    // MARK: Movement

    /// The selection after moving `textSelection` towards `destination` in `direction`;
    /// extending keeps its anchor. Nil when the move is not possible.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselectionnavigation/destinationselection(for:direction:destination:extending:confined:)
    open func destinationSelection(for textSelection: NSTextSelection, direction: NSTextSelectionNavigation.Direction, destination: NSTextSelectionNavigation.Destination, extending: Bool, confined: Bool) -> NSTextSelection? {
        guard let ds = _dataSource, let first = textSelection.textRanges.first, let last = textSelection.textRanges.last else { return nil }
        let n = _length(ds)
        let start = _offset(ds, first.location), end = _offset(ds, last.endLocation)
        let isRange = end > start
        let vertical = direction == .up || direction == .down
        let rtl = ds.baseWritingDirection(at: first.location) == .rightToLeft
        let forward: Bool
        switch direction {
        case .forward, .down: forward = true
        case .backward, .up: forward = false
        case .right: forward = !rtl
        case .left: forward = rtl
        }
        // The fixed end and the moving end.
        let anchor: Int = textSelection._anchor.map { _offset(ds, $0) } ?? (isRange ? (forward ? start : end) : start)
        var head: Int
        if extending { head = isRange ? (anchor == start ? end : start) : start }
        else { head = forward ? end : start }
        var affinity: NSTextSelection.Affinity = .downstream
        var keepX: CGFloat? = nil
        switch destination {
        case .character:
            if vertical { fallthrough }
            if !extending && isRange { break }      // collapses to the edge in the direction of movement
            head = _characterStep(ds, from: head, forward: forward)
        case .line:
            if vertical {
                guard let g = _caretGeometry(ds, head, upstream: textSelection.affinity == .upstream) else { return nil }
                let x = textSelection._hasAnchorPosition ? textSelection.anchorPositionOffset : g.x
                keepX = x
                let probe = forward ? CGPoint(x: x, y: g.maxY + 0.5) : CGPoint(x: x, y: g.minY - 0.5)
                guard let t = _verticalTarget(ds, at: probe) else { return nil }
                if t.line === g.line || g.minY - 0.5 < 0 && !forward {
                    // Off the first or last line: the start or end of the document.
                    head = forward ? n : 0
                    keepX = nil
                } else {
                    head = t.offset
                    if t.upstream { affinity = .upstream }
                }
            } else {
                // A caret drawn at the end of a soft-wrapped line belongs to that line.
                let probe = textSelection.affinity == .upstream && head > 0 && !isRange ? head - 1 : head
                if let loc = _location(ds, probe), let line = ds.textRange(for: .line, enclosing: loc) {
                    let a = _offset(ds, line.location), b = _offset(ds, line.endLocation)
                    if forward {
                        // Before the line break, or at the soft wrap (drawn at the end of this line).
                        let trimmed = _trimBreak(ds, a, b)
                        head = trimmed
                        if trimmed == b, b < n { affinity = .upstream }
                    } else {
                        head = a
                    }
                }
            }
        case .word:
            head = _wordStep(ds, from: head, forward: forward)
        case .sentence:
            head = _unitStep(ds, from: head, forward: forward, granularity: .sentence, contentOnly: true)
        case .paragraph:
            head = _unitStep(ds, from: head, forward: forward, granularity: .paragraph, contentOnly: true)
        case .container, .document:
            head = forward ? n : 0
        }
        head = max(0, min(n, head))
        let result: NSTextSelection
        if extending {
            guard let r = _range(ds, anchor, head) else { return nil }
            result = NSTextSelection([r], affinity: affinity, granularity: .character)
            result._anchor = _location(ds, anchor)
        } else {
            guard let loc = _location(ds, head) else { return nil }
            result = NSTextSelection(loc, affinity: affinity)
        }
        if let x = keepX { result.anchorPositionOffset = x }
        result.typingAttributes = textSelection.typingAttributes
        return result
    }

    /// What deleting towards `destination` removes: the selection, or the text from the
    /// caret to the destination.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselectionnavigation/deletionranges(for:direction:destination:allowsdecomposition:)
    open func deletionRanges(for textSelection: NSTextSelection, direction: NSTextSelectionNavigation.Direction, destination: NSTextSelectionNavigation.Destination, allowsDecomposition: Bool) -> [NSTextRange] {
        let nonEmpty = textSelection.textRanges.filter { !$0.isEmpty }
        if !nonEmpty.isEmpty { return nonEmpty }
        guard let ds = _dataSource, let caret = textSelection.textRanges.first else { return [] }
        let o = _offset(ds, caret.location)
        let forward = direction == .forward || direction == .right || direction == .down
        var target: Int
        if destination == .character, allowsDecomposition, !forward {
            target = _characterStep(ds, from: o, forward: false, decomposing: true)
        } else {
            let caretSelection = NSTextSelection(caret.location, affinity: textSelection.affinity)
            guard let moved = destinationSelection(for: caretSelection, direction: direction, destination: destination, extending: true, confined: false),
                  let r = moved.textRanges.first else { return [] }
            target = forward ? _offset(ds, r.endLocation) : _offset(ds, r.location)
            if target == o { target = forward ? _offset(ds, r.endLocation) : _offset(ds, r.location) }
        }
        guard target != o, let r = _range(ds, o, target) else { return [] }
        return [r]
    }

    /// Where typed text goes: the caret, or the start of the selection.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselectionnavigation/resolvedinsertionlocation(for:writingdirection:)
    open func resolvedInsertionLocation(for textSelection: NSTextSelection, writingDirection: NSTextSelectionNavigation.WritingDirection) -> (any NSTextLocation)? {
        textSelection.textRanges.first?.location
    }

    // MARK: Granularity

    /// The selection widened to whole units of `selectionGranularity`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselectionnavigation/textselection(for:enclosing:)
    open func textSelection(for selectionGranularity: NSTextSelection.Granularity, enclosing textSelection: NSTextSelection) -> NSTextSelection {
        guard let ds = _dataSource else { return textSelection }
        let ranges: [NSTextRange] = textSelection.textRanges.compactMap { r in
            guard let head = ds.textRange(for: selectionGranularity, enclosing: r.location) else { return r }
            if r.isEmpty { return head }
            let lastOffset = max(_offset(ds, r.location), _offset(ds, r.endLocation) - 1)
            guard let lastLoc = _location(ds, lastOffset), let tail = ds.textRange(for: selectionGranularity, enclosing: lastLoc) else { return head }
            return head.union(tail)
        }
        let s = NSTextSelection(ranges, affinity: textSelection.affinity, granularity: selectionGranularity)
        s.typingAttributes = textSelection.typingAttributes
        return s
    }
    /// The unit of `selectionGranularity` at `point` (container coordinates).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselectionnavigation/textselection(for:enclosing:incontainerat:)
    open func textSelection(for selectionGranularity: NSTextSelection.Granularity, enclosing point: CGPoint, inContainerAt location: any NSTextLocation) -> NSTextSelection? {
        guard let ds = _dataSource, let o = _caretOffset(ds, at: point), let loc = _location(ds, o),
              let r = ds.textRange(for: selectionGranularity, enclosing: loc) else { return nil }
        let s = NSTextSelection([r], affinity: .downstream, granularity: selectionGranularity)
        s._anchorRange = r
        return s
    }

    // MARK: Mouse

    /// The selections a click or drag at `point` (container coordinates) makes. With
    /// `.extend`, or while `selecting` (a drag), the anchors' selection grows to the point,
    /// by the anchors' granularity (a double-click drag extends by words); `.multiple` adds a
    /// caret to the anchors.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselectionnavigation/textselections(interactingat:incontainerat:anchors:modifiers:selecting:bounds:)
    open func textSelections(interactingAt point: CGPoint, inContainerAt containerLocation: any NSTextLocation, anchors: [NSTextSelection], modifiers: NSTextSelectionNavigation.Modifier, selecting: Bool, bounds: CGRect) -> [NSTextSelection] {
        guard let ds = _dataSource, let o = _caretOffset(ds, at: point), let loc = _location(ds, o) else { return anchors }
        guard (modifiers.contains(.extend) || selecting), let anchor = anchors.first, let a0 = anchor.textRanges.first, let a1 = anchor.textRanges.last else {
            let caret = NSTextSelection(loc, affinity: .downstream)
            return modifiers.contains(.multiple) && _allowsNonContiguousRanges ? anchors + [caret] : [caret]
        }
        let g = anchor.granularity
        if g != .character, let unit = anchor._anchorRange ?? NSTextRange(location: a0.location, end: a1.endLocation),
           let target = ds.textRange(for: g, enclosing: loc) {
            let s = NSTextSelection([unit.union(target)], affinity: .downstream, granularity: g)
            s._anchorRange = unit
            return [s]
        }
        let start = _offset(ds, a0.location), end = _offset(ds, a1.endLocation)
        let fixed: Int
        if let a = anchor._anchor { fixed = _offset(ds, a) }
        else if start == end { fixed = start }
        else { fixed = o >= end ? start : (o <= start ? end : start) }
        guard let r = _range(ds, fixed, o) else { return anchors }
        let s = NSTextSelection([r], affinity: .downstream, granularity: .character)
        s._anchor = _location(ds, fixed)
        return [s]
    }
}

@available(macOS 12.0, *)
extension NSTextSelectionNavigation {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselectionnavigation/destination
    @available(macOS 12.0, *)
    public enum Destination: Int, Sendable, Equatable, Hashable {
        case character = 0
        case container = 5
        case document = 6
        case line = 2
        case paragraph = 4
        case sentence = 3
        case word = 1
    }
}

@available(macOS 12.0, *)
extension NSTextSelectionNavigation {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselectionnavigation/direction
    @available(macOS 12.0, *)
    public enum Direction: Int, Sendable, Equatable, Hashable {
        case backward = 1
        case down = 5
        case forward = 0
        case left = 3
        case right = 2
        case up = 4
    }
}

@available(macOS 12.0, *)
extension NSTextSelectionNavigation {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselectionnavigation/layoutorientation
    @available(macOS 12.0, *)
    public enum LayoutOrientation: Int, Sendable, Equatable, Hashable {
        case horizontal = 0
        case vertical = 1
    }
}

@available(macOS 12.0, *)
extension NSTextSelectionNavigation {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselectionnavigation/modifier
    @available(macOS 12.0, *)
    public struct Modifier: OptionSet, Sendable, Equatable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselectionnavigation/modifier/extend
        static public var extend: NSTextSelectionNavigation.Modifier { NSTextSelectionNavigation.Modifier(rawValue: 1) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselectionnavigation/modifier/multiple
        static public var multiple: NSTextSelectionNavigation.Modifier { NSTextSelectionNavigation.Modifier(rawValue: 4) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselectionnavigation/modifier/visual
        static public var visual: NSTextSelectionNavigation.Modifier { NSTextSelectionNavigation.Modifier(rawValue: 2) }
    }
}

@available(macOS 12.0, *)
extension NSTextSelectionNavigation {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselectionnavigation/writingdirection
    @available(macOS 12.0, *)
    public enum WritingDirection: Int, Sendable, Equatable, Hashable {
        case leftToRight = 0
        case rightToLeft = 1
    }
}
