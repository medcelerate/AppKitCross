// NSTextLayoutManager (hand-written; seeded from the generated stub, see tools/apigen)
// TextKit 2 layout over the port's CoreText (ADR-0040). One NSTextLayoutFragment per
// element of the content manager, in document order; fragments that are not laid out yet
// have an estimated height, and frames are stacked from the top of the container. Only
// what is asked for is laid out (the viewport layout controller asks for the visible
// fragments). The layout manager is also the selection navigation's data source.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(CoreText)
import CoreText
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager
@available(macOS 12.0, *)
open class NSTextLayoutManager: NSObject, NSSecureCoding, NSCoding, NSTextSelectionDataSource {
    private weak var _textContentManager: NSTextContentManager?
    private var _textContainer: NSTextContainer?
    private weak var _delegate: (any NSTextLayoutManagerDelegate)?
    private var _fragments: [NSTextLayoutFragment] = []
    private var _fragmentsValid = false
    private var _positionsValid = false
    /// Stands in for the element-less empty document (the extra line fragment).
    private var _emptyDocumentFragment: NSTextLayoutFragment?
    private var _textSelections: [NSTextSelection] = []
    private var _textSelectionNavigation: NSTextSelectionNavigation?
    private var _viewportController: NSTextViewportLayoutController?
    /// Rendering attributes by document range (TextKit 1's temporary attributes).
    private var _rendering: [(range: NSRange, attrs: [NSAttributedString.Key: Any])] = []
    private var _usesFontLeading = true
    private var _usesHyphenation = false
    private var _limitsLayoutForSuspiciousContents = false
    private var _resolvesNaturalAlignment = true
    private var _layoutQueue: OperationQueue?
    private var _renderingAttributesValidator: ((NSTextLayoutManager, NSTextLayoutFragment) -> Void)?
    /// Added to every frame's y by `NSTextViewportLayoutController.adjustViewport`.
    internal var _originOffset: CGFloat = 0

    // Hooks for the text view that hosts this layout manager.
    internal weak var _textView: NSTextView?
    /// Called after content or layout changes that need a redisplay (never from drawing).
    internal var _didInvalidate: (() -> Void)?

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/init()
    public override init() { super.init() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/init(coder:)
    public required init?(coder: NSCoder) { super.init() }
    // Requirement of NSCoding
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/encode(with:)
    open func encode(with coder: NSCoder) {}
    // Requirement of NSSecureCoding
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/supportssecurecoding
    class public var supportsSecureCoding: Bool { true }

    // MARK: Content and container

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/textcontentmanager
    open var textContentManager: NSTextContentManager? { _textContentManager }
    internal func _setTextContentManager(_ manager: NSTextContentManager?) {
        _textContentManager = manager
        _contentDidChange(edits: nil)
    }
    /// Moves this layout manager to `textContentManager`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/replace(_:)
    open func replace(_ textContentManager: NSTextContentManager) {
        guard textContentManager !== _textContentManager else { return }
        _textContentManager?.removeTextLayoutManager(self)
        textContentManager.addTextLayoutManager(self)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/textcontainer
    open var textContainer: NSTextContainer? {
        get { _textContainer }
        set {
            guard newValue !== _textContainer else { return }
            if _textContainer?._textLayoutManager === self { _textContainer?._textLayoutManager = nil }
            _textContainer = newValue
            newValue?._textLayoutManager = self
            _containerGeometryDidChange()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/delegate
    open var delegate: (any NSTextLayoutManagerDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }

    // MARK: Settings

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/usesfontleading
    open var usesFontLeading: Bool {
        get { _usesFontLeading }
        set { guard newValue != _usesFontLeading else { return }; _usesFontLeading = newValue; _invalidateAllLayout() }
    }
    /// Hyphenation is off in the port: CoreText breaks lines at word boundaries.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/useshyphenation
    open var usesHyphenation: Bool {
        get { _usesHyphenation }
        set { _usesHyphenation = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/limitslayoutforsuspiciouscontents
    open var limitsLayoutForSuspiciousContents: Bool {
        get { _limitsLayoutForSuspiciousContents }
        set { _limitsLayoutForSuspiciousContents = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/resolvesnaturalalignmentwithbasewritingdirection
    @available(macOS 26.0, *)
    open var resolvesNaturalAlignmentWithBaseWritingDirection: Bool {
        get { _resolvesNaturalAlignment }
        set { _resolvesNaturalAlignment = newValue }
    }
    /// Layout is synchronous; the queue is kept for clients.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/layoutqueue
    open var layoutQueue: OperationQueue? {
        get { _layoutQueue }
        set { _layoutQueue = newValue }
    }

    // MARK: Invalidation

    /// The content manager reports edits: (old range, new range) pairs, or nil for a
    /// change of the whole document.
    /// Counts content changes (the text view re-checks for text tables only after one).
    internal var _contentGeneration = 0

    internal func _contentDidChange(edits: [(old: NSRange, new: NSRange)]?) {
        _contentGeneration &+= 1
        if let edits {
            // Rendering attributes follow the text they decorate.
            for e in edits {
                let delta = e.new.length - e.old.length
                let oldEnd = NSMaxRange(e.old)
                _rendering = _rendering.compactMap { entry in
                    var r = entry.range
                    if r.location >= oldEnd { r.location += delta }
                    else if NSMaxRange(r) > e.old.location { return nil }
                    return r.length > 0 ? (r, entry.attrs) : nil
                }
            }
        } else {
            _rendering = []
        }
        _fragmentsValid = false
        _positionsValid = false
        _textSelectionNavigation?.flushLayoutCache()
        _didInvalidate?()
    }

    /// Typesets the laid-out fragments again in place (colours or link attributes changed;
    /// the geometry does not), so nothing above the viewport goes back to estimates.
    internal func _restyleLaidOutFragments() {
        for f in _fragments where f._state == .layoutAvailable { _layout(f) }
        _didInvalidate?()
    }

    internal func _containerGeometryDidChange() {
        _invalidateAllLayout()
    }

    private func _invalidateAllLayout() {
        for f in _fragments { f._lines = []; f._state = .none; f._laidOutWidth = -1; f._estimatedHeight = nil }
        _emptyDocumentFragment = nil
        _positionsValid = false
        _didInvalidate?()
    }

    internal func _invalidatePositions() { _positionsValid = false }

    internal func _fragmentInvalidated(_ fragment: NSTextLayoutFragment) {
        fragment._estimatedHeight = nil
        _positionsValid = false
    }

    /// Returns the fragments in `range` to the estimated state.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/invalidatelayout(for:)
    open func invalidateLayout(for range: NSTextRange) {
        for f in _fragments(intersecting: range) {
            f._lines = []
            f._state = .none
            f._laidOutWidth = -1
            f._estimatedHeight = nil
        }
        _positionsValid = false
        _didInvalidate?()
    }

    // MARK: Fragments

    /// The fragments in document order (one per element), reusing the fragments of
    /// elements that did not change.
    internal var _allFragments: [NSTextLayoutFragment] {
        _ensureFragments()
        if _fragments.isEmpty {
            if let f = _emptyDocumentFragment { return [f] }
            let p = NSTextParagraph(attributedString: nil)
            p.elementRange = NSTextRange(location: _NSTextIndexLocation(0))
            p.textContentManager = _textContentManager
            let f = NSTextLayoutFragment(textElement: p, range: nil)
            f._textLayoutManager = self
            _emptyDocumentFragment = f
            _positionsValid = false
            return [f]
        }
        return _fragments
    }

    private func _ensureFragments() {
        guard !_fragmentsValid else { return }
        _fragmentsValid = true
        _positionsValid = false
        var old: [ObjectIdentifier: NSTextLayoutFragment] = [:]
        for f in _fragments { if let e = f.textElement { old[ObjectIdentifier(e)] = f } }
        var made: [NSTextLayoutFragment] = []
        _ = _textContentManager?.enumerateTextElements(from: nil, options: []) { e in
            if let f = old[ObjectIdentifier(e)] {
                made.append(f)
            } else {
                let f = delegate?.textLayoutManager(self, textLayoutFragmentFor: e.elementRange?.location ?? _NSTextIndexLocation(0), in: e)
                    ?? NSTextLayoutFragment(textElement: e, range: e.elementRange)
                f._textLayoutManager = self
                made.append(f)
            }
            return true
        }
        _fragments = made
        if !made.isEmpty { _emptyDocumentFragment = nil }
        // A fragment that stopped (or started) being the last, or moved to (or from) the top
        // of the document, lays out again: the extra line and the spacing before depend on it.
        for (i, f) in made.enumerated() where f._state == .layoutAvailable {
            if f._laidOutAsLast != (i == made.count - 1) || f._laidOutAtStart != (f._documentOffset == 0) {
                f._lines = []; f._state = .none; f._laidOutWidth = -1; f._estimatedHeight = nil
            }
        }
    }

    private var _containerWidth: CGFloat { _textContainer?.size.width ?? 0 }

    /// A paragraph's string, from its element.
    private func _paragraphString(_ f: NSTextLayoutFragment) -> NSAttributedString {
        guard let e = f.textElement else { return NSAttributedString(string: "") }
        if let p = e as? NSTextParagraph { return p.attributedString }
        return (_textContentManager as? NSTextContentStorage)?.attributedString(for: e) ?? NSAttributedString(string: "")
    }

    /// The font the extra line fragment and estimates use.
    private func _font(of string: NSAttributedString, at index: Int) -> NSFont {
        if string.length > 0, let f = string.attribute(.font, at: max(0, min(index, string.length - 1)), effectiveRange: nil) as? NSFont { return f }
        return MainActor.assumeIsolated {
            if let tv = _textView, let f = tv.typingAttributes[.font] as? NSFont { return f }
            return NSFont.systemFont(ofSize: NSFont.systemFontSize)
        }
    }

    /// Lays one fragment out (it keeps its frame's origin; positions after it are stale).
    /// Fragments laid out so far (tests bound the work an edit does).
    internal var _fragmentLayoutCount = 0

    internal func _layout(_ f: NSTextLayoutFragment) {
        guard let container = _textContainer else { return }
        _fragmentLayoutCount &+= 1
        let all = _allFragments
        let isLast = f === all.last
        let string = _paragraphString(f)
        let docOffset = f._documentOffset
        // The last character's font, or the typing font for an empty document.
        let docLength = (_textContentManager as? NSTextContentStorage)?.textStorage?.length ?? 0
        let extraFont: NSFont
        if string.length > 0 { extraFont = _font(of: string, at: string.length - 1) }
        else if docLength > 0, let s = (_textContentManager as? NSTextContentStorage)?.textStorage { extraFont = _font(of: s, at: docLength - 1) }
        else { extraFont = _font(of: string, at: 0) }
        let appearance: NSAppearance? = MainActor.assumeIsolated { _textView?.effectiveAppearance }
        let links: [NSAttributedString.Key: Any]? = MainActor.assumeIsolated { _textView != nil ? _textView?.linkTextAttributes : NSTextLayoutManager.linkRenderingAttributes }
        let oldHeight = f._state == .layoutAvailable ? f._size.height : (f._estimatedHeight ?? -1)
        f._layout(container: container, appearance: appearance, linkAttributes: links, rendering: _renderingAttributes(local: f),
                  usesFontLeading: _usesFontLeading, isLast: isLast, extraLineFont: extraFont, paragraphString: string)
        f._laidOutDark = MainActor.assumeIsolated { appearance?.isDark }
        _ = docOffset
        if f._size.height != oldHeight { _positionsValid = false }
    }

    /// An estimated height: the paragraph's length over a line's worth of average glyphs.
    private func _estimate(_ f: NSTextLayoutFragment, isLast: Bool) -> CGFloat {
        if let h = f._estimatedHeight { return h }
        let string = _paragraphString(f)
        let font = _font(of: string, at: 0)
        let lineHeight = _NSLineTypesetter.emptyLineHeight(font)
        let padding = _textContainer?.lineFragmentPadding ?? 0
        let average = max(1, MainActor.assumeIsolated { font.pointSize } * 0.5)
        // An unbounded container (a horizontally resizable view's) never wraps.
        let perLine = max(1, Int(min(1_000_000_000, ((_containerWidth - 2 * padding) / average).rounded(.down))))
        var units = string.length
        var endsWithBreak = false
        if units > 0 {
            let last = (string.string as NSString).character(at: units - 1)
            if [0x0A, 0x0D, 0x2028, 0x2029, 0x0C].contains(last) { units -= 1; endsWithBreak = true }
        }
        var lines = max(1, (units + perLine - 1) / perLine)
        if isLast && (endsWithBreak || string.length == 0) { lines += string.length == 0 ? 0 : 1 }
        let style = string.length > 0 ? string.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle : nil
        let h = CGFloat(lines) * (lineHeight + (style?.lineSpacing ?? 0)) + (endsWithBreak ? (style?.paragraphSpacing ?? 0) : 0)
        f._estimatedHeight = h
        return h
    }

    /// Stacks the frames from the top: laid-out heights, else estimates.
    internal func _ensurePositions() {
        let all = _allFragments
        guard !_positionsValid else { return }
        _positionsValid = true
        var y = _originOffset
        let width = _containerWidth
        for (i, f) in all.enumerated() {
            f._origin = CGPoint(x: 0, y: y)
            if f._state == .layoutAvailable, f._laidOutWidth == width {
                y += f._size.height
            } else {
                if f._state == .layoutAvailable { f._lines = []; f._state = .none }
                let h = _estimate(f, isLast: i == all.count - 1)
                f._size = CGSize(width: width < CGFloat.greatestFiniteMagnitude / 2 ? width : 0, height: h)
                f._state = .estimatedUsageBounds
                y += h
            }
        }
    }

    /// Lays out `f` if it is not laid out for the current width.
    @discardableResult
    internal func _ensureLaidOut(_ f: NSTextLayoutFragment) -> Bool {
        if f._state == .layoutAvailable, f._laidOutWidth == _containerWidth { return false }
        _layout(f)
        return true
    }

    /// The index of the fragment holding document offset `o` (the last one at the end).
    internal func _fragmentIndex(forOffset o: Int) -> Int? {
        let all = _allFragments
        guard !all.isEmpty else { return nil }
        var lo = 0, hi = all.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            let r = all[mid].rangeInElement._nsRange ?? NSRange(location: 0, length: 0)
            if NSMaxRange(r) <= o { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// The index of the fragment at height `y` (container coordinates), clamped.
    internal func _fragmentIndex(forY y: CGFloat) -> Int? {
        _ensurePositions()
        let all = _allFragments
        guard !all.isEmpty else { return nil }
        var lo = 0, hi = all.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if all[mid]._origin.y + all[mid]._size.height <= y { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private func _fragments(intersecting range: NSTextRange) -> [NSTextLayoutFragment] {
        let all = _allFragments
        guard let r = range._nsRange, let first = _fragmentIndex(forOffset: r.location) else { return all.filter { $0.rangeInElement.intersects(range) } }
        var out: [NSTextLayoutFragment] = []
        var i = first
        while i < all.count {
            let fr = all[i].rangeInElement._nsRange ?? NSRange(location: 0, length: 0)
            if fr.location > NSMaxRange(r) || (fr.location == NSMaxRange(r) && r.length > 0) { break }
            out.append(all[i])
            i += 1
        }
        return out
    }

    // MARK: Ensuring layout

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/ensurelayout(for:)
    open func ensureLayout(for range: NSTextRange) {
        _ensurePositions()
        for f in _fragments(intersecting: range) { _ensureLaidOut(f) }
        _ensurePositions()
    }
    /// Lays out the fragments whose frames intersect `bounds`, top to bottom, placing each
    /// under the one above as it goes.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/ensurelayout(for:)
    open func ensureLayout(for bounds: CGRect) { _ = _layoutFragments(in: bounds) }

    /// Lays out and returns the fragments intersecting `bounds`.
    internal func _layoutFragments(in bounds: CGRect) -> [NSTextLayoutFragment] {
        _ensurePositions()
        let all = _allFragments
        guard var i = _fragmentIndex(forY: bounds.minY) else { return [] }
        var out: [NSTextLayoutFragment] = []
        var y = all[i]._origin.y
        while i < all.count {
            let f = all[i]
            if !out.isEmpty && y >= bounds.maxY { break }
            _ensureLaidOut(f)
            f._origin = CGPoint(x: 0, y: y)
            out.append(f)
            y += f._size.height
            i += 1
        }
        _restack(from: i, y: y)
        return out
    }

    /// Stacks the frames from index `i` at `y` (after layout changed heights above them).
    private func _restack(from i: Int, y: CGFloat) {
        let all = _allFragments
        var y = y
        var k = i
        let width = _containerWidth
        while k < all.count {
            let f = all[k]
            f._origin = CGPoint(x: 0, y: y)
            if !(f._state == .layoutAvailable && f._laidOutWidth == width) {
                let h = _estimate(f, isLast: k == all.count - 1)
                f._size = CGSize(width: width < CGFloat.greatestFiniteMagnitude / 2 ? width : 0, height: h)
                f._state = .estimatedUsageBounds
            }
            y += f._size.height
            k += 1
        }
        _positionsValid = true
    }

    /// Enumerates fragments from the one holding `location` (the first, or the last with
    /// `.reverse`, when nil) until `block` returns false; returns the far edge of the last
    /// fragment enumerated.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/enumeratetextlayoutfragments(from:options:using:)
    open func enumerateTextLayoutFragments(from location: (any NSTextLocation)?, options: NSTextLayoutFragment.EnumerationOptions = [], using block: (NSTextLayoutFragment) -> Bool) -> (any NSTextLocation)? {
        _ensureFragments()
        if _fragments.isEmpty && !options.contains(.ensuresExtraLineFragment) { return nil }
        _ensurePositions()
        let all = _allFragments
        let reverse = options.contains(.reverse)
        var i: Int
        if let location, let o = _offset(of: location), let found = _fragmentIndex(forOffset: o) {
            i = found
            if reverse, let r = all[i].rangeInElement._nsRange, r.location == o, o > 0, i > 0 { i -= 1 }
        } else if location != nil {
            return nil
        } else {
            i = reverse ? all.count - 1 : 0
        }
        var last: (any NSTextLocation)? = nil
        while i >= 0 && i < all.count {
            let f = all[i]
            if options.contains(.ensuresLayout) {
                if _ensureLaidOut(f) {
                    // Keep the frames below this one consistent while walking forwards.
                    _restack(from: i + 1, y: f._origin.y + f._size.height)
                }
            }
            i += reverse ? -1 : 1
            last = reverse ? f.rangeInElement.location : f.rangeInElement.endLocation
            if !block(f) { break }
        }
        return last
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/textlayoutfragment(for:)
    open func textLayoutFragment(for location: any NSTextLocation) -> NSTextLayoutFragment? {
        guard let o = _offset(of: location), let i = _fragmentIndex(forOffset: o) else { return nil }
        _ensurePositions()
        return _allFragments[i]
    }
    /// The fragment whose frame holds `position` (container coordinates).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/textlayoutfragment(for:)
    open func textLayoutFragment(for position: CGPoint) -> NSTextLayoutFragment? {
        guard let i = _fragmentIndex(forY: position.y) else { return nil }
        let f = _allFragments[i]
        return position.y >= f._origin.y && position.y < f._origin.y + f._size.height ? f : nil
    }
    /// The union of the fragments' frames.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/usageboundsfortextcontainer
    open var usageBoundsForTextContainer: CGRect {
        _ensurePositions()
        let all = _allFragments
        guard let first = all.first, let last = all.last else { return .zero }
        let width = all.reduce(CGFloat(0)) { max($0, $1._size.width) }
        return CGRect(x: 0, y: first._origin.y, width: width, height: last._origin.y + last._size.height - first._origin.y)
    }

    // MARK: Segments

    /// The document-coordinate line holding offset `o`: (fragment, line index).
    internal func _line(at o: Int, upstream: Bool = false) -> (fragment: NSTextLayoutFragment, line: Int)? {
        guard let i = _fragmentIndex(forOffset: o) else { return nil }
        let f = _allFragments[i]
        _ensurePositions()
        _ensureLaidOut(f)
        _ensurePositions()
        guard let li = f._lineIndex(forLocal: o - f._documentOffset, upstream: upstream) else { return nil }
        return (f, li)
    }

    /// Enumerates rects for `textRange`: one per line it touches, in container coordinates.
    /// Selection segments extend over a selected line break to the container's edge; an
    /// empty range gives a caret-wide segment.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/enumeratetextsegments(in:type:options:using:)
    open func enumerateTextSegments(in textRange: NSTextRange, type: NSTextLayoutManager.SegmentType, options: NSTextLayoutManager.SegmentOptions = [], using block: (NSTextRange?, CGRect, CGFloat, NSTextContainer) -> Bool) {
        guard let container = _textContainer, let r = textRange._nsRange else { return }
        if r.length == 0 {
            guard let (f, li) = _line(at: r.location, upstream: options.contains(.upstreamAffinity)) else { return }
            let l = f._lines[li]
            let x = f._origin.x + l.typographicBounds.minX + l._caretOffset(r.location - f._documentOffset)
            let rect = CGRect(x: x, y: f._origin.y + l.typographicBounds.minY, width: type == .standard ? 0 : 1, height: l.typographicBounds.height)
            _ = block(options.contains(.rangeNotRequired) ? nil : textRange, rect, l.glyphOrigin.y, container)
            return
        }
        var segments: [(NSRange, CGRect, CGFloat)] = []
        for f in _fragments(intersecting: textRange) {
            _ensureLaidOut(f)
            _ensurePositions()
            let base = f._documentOffset
            let local = NSRange(location: max(0, r.location - base), length: 0)
            let localEnd = min(f._paragraphString.length, NSMaxRange(r) - base)
            guard localEnd >= local.location else { continue }
            for l in f._lines where l.characterRange.location < localEnd && l.characterRange.location + l.characterRange.length > local.location {
                let a = max(local.location, l.characterRange.location), b = min(localEnd, l._visibleEnd)
                let tb = l.typographicBounds
                let x0 = tb.minX + l._caretOffset(a)
                var x1 = tb.minX + l._caretOffset(max(a, b))
                if type == .selection, localEnd > l._visibleEnd, l._newlineLength > 0 { x1 = max(x1, f._size.width - container.lineFragmentPadding) }
                let rect = CGRect(x: f._origin.x + x0, y: f._origin.y + tb.minY, width: max(0, x1 - x0), height: tb.height)
                let segRange = NSRange(location: base + a, length: max(0, min(localEnd, l.characterRange.location + l.characterRange.length) - a))
                segments.append((segRange, rect, l.glyphOrigin.y))
            }
        }
        for (k, s) in segments.enumerated() {
            if options.contains(.middleFragmentsExcluded), k > 0, k < segments.count - 1 { continue }
            var rect = s.1
            if k == 0, options.contains(.headSegmentExtended) { rect = CGRect(x: container.lineFragmentPadding, y: rect.minY, width: rect.maxX - container.lineFragmentPadding, height: rect.height) }
            if k == segments.count - 1, options.contains(.tailSegmentExtended), container.size.width < CGFloat.greatestFiniteMagnitude / 2 {
                rect.size.width = max(rect.width, container.size.width - container.lineFragmentPadding - rect.minX)
            }
            if !block(options.contains(.rangeNotRequired) ? nil : NSTextRange._make(s.0), rect, s.2, container) { return }
        }
    }

    // MARK: Rendering attributes

    /// Rendering attributes overlapping `f`, in its paragraph's indices.
    internal func _renderingAttributes(local f: NSTextLayoutFragment) -> [(range: NSRange, attrs: [NSAttributedString.Key: Any])] {
        guard !_rendering.isEmpty, let fr = f.rangeInElement._nsRange else { return [] }
        return _rendering.compactMap { t in
            let lo = max(t.range.location, fr.location), hi = min(NSMaxRange(t.range), NSMaxRange(fr))
            return hi > lo ? (NSRange(location: lo - fr.location, length: hi - lo), t.attrs) : nil
        }
    }

    /// A foreground colour or underline changes the CoreText lines; the frames stay.
    private func _renderingChanged(_ range: NSRange, keys: [NSAttributedString.Key]) {
        let restyles = keys.contains { $0 == .foregroundColor || $0 == .underlineStyle || $0 == .underlineColor || $0 == .strokeColor || $0 == .strokeWidth }
        if restyles {
            for f in _fragments(intersecting: NSTextRange._make(range)) where f._state == .layoutAvailable { _layout(f) }
        }
        _didInvalidate?()
    }

    private func _clamp(_ r: NSRange) -> NSRange {
        let n = (_textContentManager as? NSTextContentStorage)?.textStorage?.length ?? Int.max
        let lo = min(max(0, r.location), n)
        return NSRange(location: lo, length: max(0, min(NSMaxRange(r), n) - lo))
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/setrenderingattributes(_:for:)
    open func setRenderingAttributes(_ renderingAttributes: [NSAttributedString.Key : Any], for textRange: NSTextRange) {
        guard let r0 = textRange._nsRange else { return }
        let r = _clamp(r0)
        guard r.length > 0 else { return }
        var keys = Array(renderingAttributes.keys)
        _rendering = _rendering.flatMap { entry -> [(range: NSRange, attrs: [NSAttributedString.Key: Any])] in
            let e = entry.range
            guard NSMaxRange(e) > r.location, e.location < NSMaxRange(r) else { return [entry] }
            keys.append(contentsOf: entry.attrs.keys)
            var parts: [(range: NSRange, attrs: [NSAttributedString.Key: Any])] = []
            if e.location < r.location { parts.append((NSRange(location: e.location, length: r.location - e.location), entry.attrs)) }
            if NSMaxRange(e) > NSMaxRange(r) { parts.append((NSRange(location: NSMaxRange(r), length: NSMaxRange(e) - NSMaxRange(r)), entry.attrs)) }
            return parts
        }
        if !renderingAttributes.isEmpty { _rendering.append((r, renderingAttributes)) }
        _rendering.sort { $0.range.location < $1.range.location }
        _renderingChanged(r, keys: keys)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/addrenderingattribute(_:value:for:)
    open func addRenderingAttribute(_ renderingAttribute: NSAttributedString.Key, value: Any?, for textRange: NSTextRange) {
        guard let r0 = textRange._nsRange else { return }
        let r = _clamp(r0)
        guard r.length > 0 else { return }
        guard let value else { removeRenderingAttribute(renderingAttribute, for: textRange); return }
        // Marks usually arrive in document order (a spelling pass): append after the last run.
        if _rendering.last.map({ r.location >= NSMaxRange($0.range) }) ?? true {
            _rendering.append((r, [renderingAttribute: value]))
            _renderingChanged(r, keys: [renderingAttribute])
            return
        }
        // Split the runs at the range's edges, then add to every run inside it.
        var pieces: [(range: NSRange, attrs: [NSAttributedString.Key: Any])] = []
        var covered: [NSRange] = []
        for entry in _rendering {
            let e = entry.range
            guard NSMaxRange(e) > r.location, e.location < NSMaxRange(r) else { pieces.append(entry); continue }
            if e.location < r.location { pieces.append((NSRange(location: e.location, length: r.location - e.location), entry.attrs)) }
            let lo = max(e.location, r.location), hi = min(NSMaxRange(e), NSMaxRange(r))
            var a = entry.attrs
            a[renderingAttribute] = value
            pieces.append((NSRange(location: lo, length: hi - lo), a))
            covered.append(NSRange(location: lo, length: hi - lo))
            if NSMaxRange(e) > NSMaxRange(r) { pieces.append((NSRange(location: NSMaxRange(r), length: NSMaxRange(e) - NSMaxRange(r)), entry.attrs)) }
        }
        // The gaps between existing runs get a run of their own.
        var at = r.location
        for c in covered.sorted(by: { $0.location < $1.location }) {
            if c.location > at { pieces.append((NSRange(location: at, length: c.location - at), [renderingAttribute: value])) }
            at = max(at, NSMaxRange(c))
        }
        if at < NSMaxRange(r) { pieces.append((NSRange(location: at, length: NSMaxRange(r) - at), [renderingAttribute: value])) }
        _rendering = pieces.sorted { $0.range.location < $1.range.location }
        _renderingChanged(r, keys: [renderingAttribute])
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/removerenderingattribute(_:for:)
    open func removeRenderingAttribute(_ renderingAttribute: NSAttributedString.Key, for textRange: NSTextRange) {
        guard let r0 = textRange._nsRange else { return }
        let r = _clamp(r0)
        guard r.length > 0 else { return }
        var pieces: [(range: NSRange, attrs: [NSAttributedString.Key: Any])] = []
        var touched = false
        for entry in _rendering {
            let e = entry.range
            guard entry.attrs[renderingAttribute] != nil, NSMaxRange(e) > r.location, e.location < NSMaxRange(r) else { pieces.append(entry); continue }
            touched = true
            if e.location < r.location { pieces.append((NSRange(location: e.location, length: r.location - e.location), entry.attrs)) }
            var a = entry.attrs
            a[renderingAttribute] = nil
            let lo = max(e.location, r.location), hi = min(NSMaxRange(e), NSMaxRange(r))
            if !a.isEmpty { pieces.append((NSRange(location: lo, length: hi - lo), a)) }
            if NSMaxRange(e) > NSMaxRange(r) { pieces.append((NSRange(location: NSMaxRange(r), length: NSMaxRange(e) - NSMaxRange(r)), entry.attrs)) }
        }
        guard touched else { return }
        _rendering = pieces.sorted { $0.range.location < $1.range.location }
        _renderingChanged(r, keys: [renderingAttribute])
    }
    /// Removes the rendering attributes in `textRange`; the fragments there call the
    /// validator again before they draw.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/invalidaterenderingattributes(for:)
    open func invalidateRenderingAttributes(for textRange: NSTextRange) {
        setRenderingAttributes([:], for: textRange)
        for f in _fragments(intersecting: textRange) { f._renderingNeedsValidation = true }
    }
    /// Enumerates the runs of rendering attributes from `location` (backwards with
    /// `reverse`) until `block` returns false.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/enumeraterenderingattributes(from:reverse:using:)
    open func enumerateRenderingAttributes(from location: any NSTextLocation, reverse: Bool, using block: (NSTextLayoutManager, [NSAttributedString.Key : Any], NSTextRange) -> Bool) {
        guard let o = _offset(of: location) else { return }
        let runs = reverse ? _rendering.filter { $0.range.location < o }.reversed() : _rendering.filter { NSMaxRange($0.range) > o }
        for run in runs { if !block(self, run.attrs, NSTextRange._make(run.range)) { return } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/renderingattributesvalidator
    open var renderingAttributesValidator: ((NSTextLayoutManager, NSTextLayoutFragment) -> Void)? {
        get { _renderingAttributesValidator }
        set { _renderingAttributesValidator = newValue; for f in _fragments { f._renderingNeedsValidation = true } }
    }
    /// The link colour, underlined.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/linkrenderingattributes
    class public var linkRenderingAttributes: [NSAttributedString.Key : Any] {
        MainActor.assumeIsolated { [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue] }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/renderingattributes(forlink:at:)
    open func renderingAttributes(forLink link: Any, at location: any NSTextLocation) -> [NSAttributedString.Key : Any] {
        let defaults = NSTextLayoutManager.linkRenderingAttributes
        return delegate?.textLayoutManager(self, renderingAttributesForLink: link, at: location, defaultAttributes: defaults) ?? defaults
    }

    // MARK: Editing

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/replacecontents(in:with:)
    open func replaceContents(in range: NSTextRange, with textElements: [NSTextElement]) {
        _textContentManager?.replaceContents(in: range, with: textElements)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/replacecontents(in:with:)
    open func replaceContents(in range: NSTextRange, with attributedString: NSAttributedString) {
        guard let cm = _textContentManager else { return }
        if let storage = (cm as? NSTextContentStorage)?.textStorage, let r = range._nsRange, NSMaxRange(r) <= storage.length {
            cm.performEditingTransaction { storage.replaceCharacters(in: r, with: attributedString) }
        } else {
            cm.replaceContents(in: range, with: [NSTextParagraph(attributedString: attributedString)])
        }
    }

    // MARK: Selections

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/textselections
    open var textSelections: [NSTextSelection] {
        get {
            // A hosting text view's selection is the source of truth (typing moves it).
            if let tv = _textView { MainActor.assumeIsolated { tv._tk2SyncSelection() } }
            return _textSelections
        }
        set {
            _textSelections = newValue
            // ... and follows selections set here.
            if let tv = _textView, let first = newValue.first { MainActor.assumeIsolated { tv._tk2Apply(first) } }
            _didInvalidate?()
        }
    }
    internal func _setTextSelectionsQuietly(_ s: [NSTextSelection]) { _textSelections = s }
    internal var _rawTextSelections: [NSTextSelection] { _textSelections }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/textselectionnavigation
    open var textSelectionNavigation: NSTextSelectionNavigation {
        get {
            if let n = _textSelectionNavigation { return n }
            let n = NSTextSelectionNavigation(dataSource: self)
            _textSelectionNavigation = n
            return n
        }
        set { _textSelectionNavigation = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/textviewportlayoutcontroller
    open var textViewportLayoutController: NSTextViewportLayoutController {
        if let c = _viewportController { return c }
        let c = NSTextViewportLayoutController(textLayoutManager: self)
        _viewportController = c
        return c
    }

    // MARK: NSTextSelectionDataSource

    /// The document's text (from the content storage, else from the elements).
    internal var _documentString: NSString {
        if let s = (_textContentManager as? NSTextContentStorage)?.textStorage?.string { return s as NSString }
        let out = NSMutableString(string: "")
        _ = _textContentManager?.enumerateTextElements(from: nil, options: []) { e in
            if let p = e as? NSTextParagraph { out.append(p.attributedString.string) }
            return true
        }
        return out
    }

    // Requirement of NSTextSelectionDataSource
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/documentrange
    open var documentRange: NSTextRange { _textContentManager?.documentRange ?? NSTextRange(location: _NSTextIndexLocation(0)) }
    // Requirement of NSTextSelectionDataSource
    /// Enumerates words, sentences, paragraphs, lines or composed characters from `location`
    /// (to the document's start with `.reverse`).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/enumeratesubstrings(from:options:using:)
    open func enumerateSubstrings(from location: any NSTextLocation, options: NSString.EnumerationOptions = [], using block: (String?, NSTextRange, NSTextRange?, UnsafeMutablePointer<ObjCBool>) -> Void) {
        guard let o = _offset(of: location) else { return }
        let s = _documentString
        let reverse = options.contains(.reverse)
        let span = reverse ? NSRange(location: 0, length: min(o, s.length)) : NSRange(location: min(o, s.length), length: max(0, s.length - o))
        var stop = ObjCBool(false)
        for (r, enclosing) in _NSTextUnits.substrings(of: s, in: span, options: options) {
            let text = options.contains(.substringNotRequired) ? nil : s.substring(with: r)
            block(text, NSTextRange._make(r), NSTextRange._make(enclosing), &stop)
            if stop.boolValue { return }
        }
    }
    // Requirement of NSTextSelectionDataSource
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/textrange(for:enclosing:)
    open func textRange(for selectionGranularity: NSTextSelection.Granularity, enclosing location: any NSTextLocation) -> NSTextRange? {
        guard let o = _offset(of: location) else { return nil }
        let s = _documentString
        guard o >= 0, o <= s.length else { return nil }
        switch selectionGranularity {
        case .character:
            guard o < s.length else { return NSTextRange(location: location) }
            return NSTextRange._make(s.rangeOfComposedCharacterSequence(at: o))
        case .word:
            return NSTextRange._make(_NSTextUnits.wordRange(in: s, at: o))
        case .sentence:
            return NSTextRange._make(_NSTextUnits.sentenceRange(in: s, at: o))
        case .paragraph:
            if let cs = _textContentManager as? NSTextContentStorage, let i = cs._paragraphIndex(containing: o) {
                return cs._allParagraphs[i].elementRange
            }
            let units = Array((s as String).utf16)
            var p = 0
            while p < units.count {
                let e = _NSLineTypesetter.paragraphEnd(from: p, units: units)
                if o < e || e == units.count { return NSTextRange._make(NSRange(location: p, length: e - p)) }
                p = e
            }
            return NSTextRange(location: location)
        case .line:
            guard let (f, li) = _line(at: o) else { return nil }
            let l = f._lines[li]
            return NSTextRange._make(NSRange(location: f._documentOffset + l.characterRange.location, length: l.characterRange.length))
        }
    }
    // Requirement of NSTextSelectionDataSource
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/location(_:offsetby:)
    open func location(_ location: any NSTextLocation, offsetBy offset: Int) -> (any NSTextLocation)? {
        if let cs = _textContentManager as? NSTextContentStorage { return cs.location(location, offsetBy: offset) }
        guard let o = _offset(of: location) else { return nil }
        let n = o + offset
        return n >= 0 && n <= _documentString.length ? _NSTextIndexLocation(n) : nil
    }
    // Requirement of NSTextSelectionDataSource
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/offset(from:to:)
    open func offset(from: any NSTextLocation, to: any NSTextLocation) -> Int {
        guard let a = _offset(of: from), let b = _offset(of: to) else { return 0 }
        return b - a
    }
    // Requirement of NSTextSelectionDataSource
    /// The paragraph style's writing direction at `location` (natural is left to right).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/basewritingdirection(at:)
    open func baseWritingDirection(at location: any NSTextLocation) -> NSTextSelectionNavigation.WritingDirection {
        guard let o = _offset(of: location), let storage = (_textContentManager as? NSTextContentStorage)?.textStorage, storage.length > 0 else { return .leftToRight }
        let style = storage.attribute(.paragraphStyle, at: max(0, min(o, storage.length - 1)), effectiveRange: nil) as? NSParagraphStyle
        return style?.baseWritingDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }
    // Requirement of NSTextSelectionDataSource
    /// The caret positions of the line holding `location`, left to right: (x in container
    /// coordinates, location, whether it is a character's leading edge).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/enumeratecaretoffsetsinlinefragment(at:using:)
    open func enumerateCaretOffsetsInLineFragment(at location: any NSTextLocation, using block: (CGFloat, any NSTextLocation, Bool, UnsafeMutablePointer<ObjCBool>) -> Void) {
        guard let o = _offset(of: location), let (f, li) = _line(at: o) else { return }
        let l = f._lines[li]
        let base = f._documentOffset
        var stop = ObjCBool(false)
        var carets: [(CGFloat, Int, Bool)] = []
        for i in l.characterRange.location...max(l.characterRange.location, l._visibleEnd) {
            let x = f._origin.x + l.typographicBounds.minX + l._caretOffset(i)
            carets.append((x, base + i, i < l._visibleEnd))
        }
        for c in carets.sorted(by: { $0.0 < $1.0 }) {
            block(c.0, _NSTextIndexLocation(c.1), c.2, &stop)
            if stop.boolValue { return }
        }
    }
    // Requirement of NSTextSelectionDataSource
    /// The line at `point` (container coordinates; above the text is the first line, below
    /// it the last).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/linefragmentrange(for:incontainerat:)
    open func lineFragmentRange(for point: CGPoint, inContainerAt location: any NSTextLocation) -> NSTextRange? {
        guard let (f, li) = _lineIndex(atY: point.y) else { return nil }
        let l = f._lines[li]
        return NSTextRange._make(NSRange(location: f._documentOffset + l.characterRange.location, length: l.characterRange.length))
    }
    // Requirement of NSTextSelectionDataSource
    /// One container: its boundary is the document's end (start, in reverse).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselectiondatasource/enumeratecontainerboundaries(from:reverse:using:)
    open func enumerateContainerBoundaries(from location: any NSTextLocation, reverse: Bool, using block: (any NSTextLocation, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop = ObjCBool(false)
        block(reverse ? documentRange.location : documentRange.endLocation, &stop)
    }
    // Requirement of NSTextSelectionDataSource
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselectiondatasource/textlayoutorientation(at:)
    open func textLayoutOrientation(at location: any NSTextLocation) -> NSTextSelectionNavigation.LayoutOrientation { .horizontal }

    /// The line at height `y` in container coordinates (laying its fragment out).
    internal func _lineIndex(atY y: CGFloat) -> (fragment: NSTextLayoutFragment, line: Int)? {
        guard var i = _fragmentIndex(forY: y) else { return nil }
        let all = _allFragments
        // Layout can move the fragment; settle on the one that holds y once laid out.
        for _ in 0..<4 {
            let f = all[i]
            if _ensureLaidOut(f) { _restack(from: i + 1, y: f._origin.y + f._size.height) }
            if y >= f._origin.y + f._size.height, i + 1 < all.count { i += 1; continue }
            break
        }
        let f = all[i]
        let local = y - f._origin.y
        guard !f._lines.isEmpty else { return nil }
        if local < f._lines[0].typographicBounds.minY { return (f, 0) }
        var chosen = 0
        for (k, l) in f._lines.enumerated() where local >= l.typographicBounds.minY { chosen = k }
        return (f, chosen)
    }

    /// The caret offset nearest `point` (container coordinates), as the TextKit 1 text view
    /// rounds: past the middle of a glyph goes after it.
    internal func _caretOffset(at point: CGPoint) -> Int {
        guard let (f, li) = _lineIndex(atY: point.y) else { return 0 }
        let l = f._lines[li]
        let base = f._documentOffset
        if point.y < f._origin.y + l.typographicBounds.minY, li == 0, f === _allFragments.first { return base + l.characterRange.location }
        let p = CGPoint(x: point.x - f._origin.x - l.typographicBounds.minX, y: 0)
        var i = l.characterIndex(for: p)
        guard l._line != nil else { return base + i }
        if i < l._visibleEnd {
            let x0 = l._caretOffset(i), x1 = l._caretOffset(i + 1)
            if x1 > x0, (p.x - x0) / (x1 - x0) > 0.5 { i += 1 }
        }
        return base + min(i, l._visibleEnd)
    }
}

@available(macOS 12.0, *)
extension NSTextLayoutManager {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/segmentoptions
    @available(macOS 12.0, *)
    public struct SegmentOptions: OptionSet, Sendable, Equatable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/segmentoptions/headsegmentextended
        static public var headSegmentExtended: NSTextLayoutManager.SegmentOptions { NSTextLayoutManager.SegmentOptions(rawValue: 4) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/segmentoptions/middlefragmentsexcluded
        static public var middleFragmentsExcluded: NSTextLayoutManager.SegmentOptions { NSTextLayoutManager.SegmentOptions(rawValue: 2) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/segmentoptions/rangenotrequired
        static public var rangeNotRequired: NSTextLayoutManager.SegmentOptions { NSTextLayoutManager.SegmentOptions(rawValue: 1) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/segmentoptions/tailsegmentextended
        static public var tailSegmentExtended: NSTextLayoutManager.SegmentOptions { NSTextLayoutManager.SegmentOptions(rawValue: 8) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/segmentoptions/upstreamaffinity
        static public var upstreamAffinity: NSTextLayoutManager.SegmentOptions { NSTextLayoutManager.SegmentOptions(rawValue: 16) }
    }
}

@available(macOS 12.0, *)
extension NSTextLayoutManager {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutmanager/segmenttype
    @available(macOS 12.0, *)
    public enum SegmentType: Int, Sendable, Equatable, Hashable {
        case highlight = 2
        case selection = 1
        case standard = 0
    }
}

/// Text units for selection and navigation: composed characters, words (letters, digits
/// and the underscore, as the TextKit 1 text view's double-click), sentences, lines and
/// paragraphs, computed on the UTF-16 text without NSString's enumerator (corelibs
/// Foundation does not implement it).
internal enum _NSTextUnits {
    /// `.byWords` and `.bySentences` by value: corelibs Foundation marks them unavailable.
    static let byWords = NSString.EnumerationOptions(rawValue: 3)
    static let bySentences = NSString.EnumerationOptions(rawValue: 4)

    static func isWord(_ u: UInt16) -> Bool {
        guard let s = UnicodeScalar(u) else { return false }
        let c = Character(s)
        return c.isLetter || c.isNumber || c == "_"
    }

    /// The word around `o`; between words, the run of other characters around it (one
    /// character at a time for whitespace runs, as the double-click selects).
    static func wordRange(in s: NSString, at o: Int) -> NSRange {
        let n = s.length
        guard n > 0 else { return NSRange(location: 0, length: 0) }
        var start = min(o, n), end = start
        if (start < n && isWord(s.character(at: start))) || ((start == n || !isWord(s.character(at: start))) && start > 0 && isWord(s.character(at: start - 1))) {
            if !(start < n && isWord(s.character(at: start))) { start -= 1; end = start }
            while start > 0 && isWord(s.character(at: start - 1)) { start -= 1 }
            while end < n && isWord(s.character(at: end)) { end += 1 }
        } else if start < n {
            end = start + 1
        }
        return NSRange(location: start, length: end - start)
    }

    private static func isSentenceEnd(_ u: UInt16) -> Bool { u == 0x2E || u == 0x21 || u == 0x3F }
    private static func isSpace(_ u: UInt16) -> Bool { u == 0x20 || u == 0x09 || u == 0xA0 }
    private static func isBreak(_ u: UInt16) -> Bool { [0x0A, 0x0D, 0x2028, 0x2029, 0x0C].contains(u) }

    /// The sentence around `o`: up to and including terminal punctuation, the spaces after
    /// it, or a paragraph break.
    static func sentenceRange(in s: NSString, at o: Int) -> NSRange {
        let n = s.length
        guard n > 0 else { return NSRange(location: 0, length: 0) }
        for r in sentences(in: s, span: NSRange(location: 0, length: n)) where o >= r.location && (o < NSMaxRange(r) || NSMaxRange(r) == n) {
            return r
        }
        return NSRange(location: n, length: 0)
    }

    static func sentences(in s: NSString, span: NSRange) -> [NSRange] {
        var out: [NSRange] = []
        // Sentences are found from the paragraph start so a span starting mid-sentence
        // reports whole sentences.
        let units = Array((s as String).utf16)
        var i = 0
        let end = NSMaxRange(span)
        var start = 0
        while i < units.count {
            let u = units[i]
            if isBreak(u) {
                i += _NSLineTypesetter.newlineLength(at: i, in: units)
                out.append(NSRange(location: start, length: i - start)); start = i
                continue
            }
            if isSentenceEnd(u), i + 1 >= units.count || isSpace(units[i + 1]) || isBreak(units[i + 1]) {
                i += 1
                while i < units.count && isSpace(units[i]) { i += 1 }
                out.append(NSRange(location: start, length: i - start)); start = i
                continue
            }
            i += 1
        }
        if start < units.count { out.append(NSRange(location: start, length: units.count - start)) }
        return out.filter { NSMaxRange($0) > span.location && $0.location < end || ($0.length == 0 && $0.location == span.location) }
    }

    /// Substring ranges (and their enclosing ranges, which add the trailing separators)
    /// within `span`, in order (reversed with `.reverse`).
    static func substrings(of s: NSString, in span: NSRange, options: NSString.EnumerationOptions) -> [(NSRange, NSRange)] {
        var out: [(NSRange, NSRange)] = []
        let units = Array((s as String).utf16)
        let end = NSMaxRange(span)
        // The unit is an enumeration in the low byte (`.byLines` is 0); the rest are flags.
        let unit = options.rawValue & 0xFF
        if unit == byWords.rawValue {
            var i = span.location
            // Start at the beginning of a word cut by the span.
            while i > 0, i < units.count, isWord(units[i]), isWord(units[i - 1]) { i -= 1 }
            while i < end {
                guard isWord(units[i]) else { i += 1; continue }
                var j = i
                while j < units.count && isWord(units[j]) { j += 1 }
                var k = j
                while k < units.count && !isWord(units[k]) && !isBreak(units[k]) { k += 1 }
                out.append((NSRange(location: i, length: j - i), NSRange(location: i, length: k - i)))
                i = j
            }
        } else if unit == bySentences.rawValue {
            for r in sentences(in: s, span: span) where r.length > 0 {
                var c = NSMaxRange(r)
                while c > r.location && (isSpace(units[c - 1]) || isBreak(units[c - 1])) { c -= 1 }
                out.append((NSRange(location: r.location, length: c - r.location), r))
            }
        } else if unit == NSString.EnumerationOptions.byParagraphs.rawValue || unit == NSString.EnumerationOptions.byLines.rawValue {
            var p = 0
            while p < units.count {
                let e = _NSLineTypesetter.paragraphEnd(from: p, units: units)
                let sep = e - p >= 2 && units[e - 2] == 0x0D && units[e - 1] == 0x0A ? 2 : (_NSLineTypesetter.newlineLength(at: e - 1, in: units) > 0 ? 1 : 0)
                if e > span.location && p < end { out.append((NSRange(location: p, length: e - p - sep), NSRange(location: p, length: e - p))) }
                p = e
            }
        } else {
            var i = span.location
            while i < end {
                let r = s.rangeOfComposedCharacterSequence(at: i)
                out.append((r, r))
                i = NSMaxRange(r)
            }
        }
        return options.contains(.reverse) ? out.reversed() : out
    }
}
