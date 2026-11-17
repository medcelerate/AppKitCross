// NSTextView on TextKit 2 (ADR-0040): an NSTextContentStorage over the view's text storage,
// an NSTextLayoutManager with the view's container, and its viewport layout controller. The
// view's geometry hooks read the layout manager, the viewport is laid out from `layout()`
// and when the enclosing clip view scrolls (never from `draw(_:)`), drawing walks only the
// fragments in the dirty rect in TextKit 1's order, and keyboard and mouse selection go
// through `textSelectionNavigation`. Asking for `layoutManager` (or text the engine cannot
// lay out: text tables, or becoming a field editor) switches the view to TextKit 1.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// TextKit 2 state a text view keeps.
@MainActor internal final class _NSTextViewTextKit2State {
    /// The selections at mouse-down, which a drag extends.
    var dragAnchors: [NSTextSelection] = []
    var dragging = false
    /// A fit of the frame is scheduled (drawing laid out fragments it had not).
    var fitScheduled = false
    var switching = false
    /// The layout manager's content generation the table check last ran at.
    var checkedGeneration = -1
    weak var observedClipView: NSView?
    nonisolated(unsafe) var clipObserver: NSObjectProtocol?
    deinit { if let token = clipObserver { NotificationCenter.default.removeObserver(token) } }
    var viewportDelegate: _NSTextViewViewportDelegate?
}

/// The viewport controller's delegate: the view's visible rect, in container coordinates.
internal final class _NSTextViewViewportDelegate: NSObject, NSTextViewportLayoutControllerDelegate {
    weak var textView: NSTextView?
    init(_ textView: NSTextView) { self.textView = textView }
    func viewportBounds(for textViewportLayoutController: NSTextViewportLayoutController) -> CGRect {
        MainActor.assumeIsolated { textView?._tk2ViewportBounds ?? .zero }
    }
    func textViewportLayoutController(_ textViewportLayoutController: NSTextViewportLayoutController, configureRenderingSurfaceFor textLayoutFragment: NSTextLayoutFragment) {}
    func textViewportLayoutControllerDidLayout(_ textViewportLayoutController: NSTextViewportLayoutController) {
        MainActor.assumeIsolated { textView?._tk2FitFrame() }
    }
}

extension NSTextView {
    /// `APPKITWIN_TEXTKIT=2` makes new text views use TextKit 2 (the port's default is
    /// TextKit 1 until TextKit 2 is verified on every platform; ADR-0040).
    internal static var _defaultEngineIsTextKit2: Bool { ProcessInfo.processInfo.environment["APPKITWIN_TEXTKIT"] == "2" }

    /// The TextKit 1 layout manager when it is the active engine, without switching to it.
    internal var _activeLayoutManager: NSLayoutManager? { _textLayoutManager == nil ? _layoutManager : nil }

    // MARK: Setting up and switching engines

    /// Lays the view out with TextKit 2: a content storage over the view's text storage (or
    /// the container's own TextKit 2 objects).
    internal func _wireTextKit2(layoutManager existing: NSTextLayoutManager? = nil) {
        let tlm = existing ?? NSTextLayoutManager()
        let cs: NSTextContentStorage
        if let own = tlm.textContentManager as? NSTextContentStorage {
            cs = own
            if let s = own.textStorage { _storage = s } else { own.textStorage = _storage }
        } else {
            cs = NSTextContentStorage()
            cs.textStorage = textStorage
            cs.addTextLayoutManager(tlm)
        }
        // TextKit 1 lets go of the storage and the container.
        let lm = _layoutManager
        if let c = textContainer, let i = lm.textContainers.firstIndex(where: { $0 === c }) { lm.removeTextContainer(at: i) }
        if lm.textStorage === textStorage { textStorage?.removeLayoutManager(lm) }
        _textContentStorage = cs
        _textLayoutManager = tlm
        tlm.textContainer = textContainer
        tlm._textView = self
        tlm._didInvalidate = { [weak self] in MainActor.assumeIsolated { self?._tk2DidInvalidate() } }
        let d = _NSTextViewViewportDelegate(self)
        _tk2.viewportDelegate = d
        tlm.textViewportLayoutController.delegate = d
        _tk2SyncSelection()
        _tk2ObserveClipView()
    }

    /// TextKit 1 from now on, as AppKit's compatibility mode: the content storage stops
    /// observing, the NSLayoutManager takes the storage and container, and spelling marks
    /// become temporary attributes again.
    internal func _switchToTextKit1() {
        guard let tlm = _textLayoutManager, !_tk2.switching else { return }
        _tk2.switching = true
        defer { _tk2.switching = false }
        var marks: [(NSRange, Int)] = []
        tlm.enumerateRenderingAttributes(from: tlm.documentRange.location, reverse: false) { _, attrs, r in
            if let v = (attrs[.spellingState] as? NSNumber)?.intValue, v != 0, let nr = r._nsRange { marks.append((nr, v)) }
            return true
        }
        tlm.textViewportLayoutController.delegate = nil
        tlm._didInvalidate = nil
        tlm._textView = nil
        tlm.textContainer = nil
        if let cs = _textContentStorage {
            cs.removeTextLayoutManager(tlm)
            if let s = textStorage, s.textStorageObserver === cs { s.textStorageObserver = nil }
        }
        _textLayoutManager = nil
        _textContentStorage = nil
        _tk2.viewportDelegate = nil
        _wireTextKit1()
        for (r, v) in marks { _layoutManager.addTemporaryAttribute(.spellingState, value: NSNumber(value: v), forCharacterRange: r) }
        _invalidateLayout()
        needsDisplay = true
    }

    /// Text tables are laid out by TextKit 1 only (as on macOS).
    private var _storageNeedsTextKit1: Bool {
        guard let s = textStorage, s.length > 0 else { return false }
        var found = false
        s.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: s.length), options: []) { v, _, stop in
            if let ps = v as? NSParagraphStyle, !ps.textBlocks.isEmpty { found = true; stop.pointee = true }
        }
        return found
    }

    /// Content or layout changed (an edit, a geometry change): redisplay, and fit the frame
    /// on the next layout pass.
    internal func _tk2DidInvalidate() {
        // Only content edits can bring a table in (not rendering attributes or layout).
        if !_tk2.switching, let tlm = _textLayoutManager, tlm._contentGeneration != _tk2.checkedGeneration {
            _tk2.checkedGeneration = tlm._contentGeneration
            if _storageNeedsTextKit1 { _switchToTextKit1(); return }
        }
        needsLayout = true
        needsDisplay = true
    }

    // MARK: Selection

    /// The layout manager's selection follows the view's selected range (the NSText model
    /// stays the source of truth), keeping the navigation state while they agree.
    internal func _tk2SyncSelection() {
        guard let tlm = _textLayoutManager else { return }
        let sel = selectedRange
        let raw = tlm._rawTextSelections
        if let current = raw.first, raw.count == 1, current.textRanges.first?._nsRange == sel { return }
        let s = NSTextSelection(range: NSTextRange._make(sel), affinity: .downstream, granularity: .character)
        if let a = _selectionAnchor, sel.length > 0, a == sel.location || a == NSMaxRange(sel) { s._anchor = _NSTextIndexLocation(a) }
        s.typingAttributes = typingAttributes
        tlm._setTextSelectionsQuietly([s])
    }

    /// Makes `selection` the view's selection.
    internal func _tk2Apply(_ selection: NSTextSelection) {
        guard let tlm = _textLayoutManager, let r = selection.textRanges.first?._nsRange else { return }
        tlm._setTextSelectionsQuietly([selection])
        let anchor = selection._anchor.flatMap(_offset(of:))
        selectedRange = r
        _selectionAnchor = r.length > 0 ? anchor : nil
        // The setter mirrored a plain selection; keep the navigation's (anchor, x, affinity).
        tlm._setTextSelectionsQuietly([selection])
    }

    private var _tk2CurrentSelection: NSTextSelection {
        _tk2SyncSelection()
        return _textLayoutManager?._rawTextSelections.first ?? NSTextSelection(range: NSTextRange._make(selectedRange), affinity: .downstream, granularity: .character)
    }

    /// A movement action through the selection navigation; false when TextKit 2 is not active.
    @discardableResult
    internal func _tk2Move(_ direction: NSTextSelectionNavigation.Direction, _ destination: NSTextSelectionNavigation.Destination, extending: Bool) -> Bool {
        guard let tlm = _textLayoutManager else { return false }
        if let next = tlm.textSelectionNavigation.destinationSelection(for: _tk2CurrentSelection, direction: direction, destination: destination, extending: extending, confined: false) {
            _tk2Apply(next)
            if let r = next.textRanges.first?._nsRange { scrollRangeToVisible(NSRange(location: extending && _selectionAnchor == NSMaxRange(r) ? r.location : NSMaxRange(r), length: 0)) }
        }
        return true
    }

    /// Page up and down: the caret moves by the visible height, keeping its x.
    @discardableResult
    internal func _tk2Page(down: Bool, extending: Bool) -> Bool {
        guard let tlm = _textLayoutManager else { return false }
        let current = _tk2CurrentSelection
        let sel = selectedRange
        let head = extending ? (_selectionAnchor == sel.location ? NSMaxRange(sel) : sel.location) : (down ? NSMaxRange(sel) : sel.location)
        let caret = _caretRect(for: head)
        let page = max(_lineHeight, visibleRect.height - _lineHeight)
        let origin = _drawOrigin
        let target = CGPoint(x: caret.minX - origin.x, y: caret.midY - origin.y + (down ? page : -page))
        let o = target.y < 0 ? 0 : tlm._caretOffset(at: target)
        let anchor = extending ? (_selectionAnchor ?? (down ? sel.location : NSMaxRange(sel))) : o
        let s = NSTextSelection(range: NSTextRange._make(NSRange(location: min(anchor, o), length: abs(o - anchor))), affinity: .downstream, granularity: .character)
        if extending { s._anchor = _NSTextIndexLocation(anchor) }
        s.typingAttributes = current.typingAttributes
        _tk2Apply(s)
        scrollRangeToVisible(NSRange(location: o, length: 0))
        return true
    }

    /// What a deletion removes, through the navigation; nil when TextKit 2 is not active.
    internal func _tk2DeletionRange(_ direction: NSTextSelectionNavigation.Direction, _ destination: NSTextSelectionNavigation.Destination) -> NSRange? {
        guard let tlm = _textLayoutManager else { return nil }
        let ranges = tlm.textSelectionNavigation.deletionRanges(for: _tk2CurrentSelection, direction: direction, destination: destination, allowsDecomposition: false)
        return ranges.first?._nsRange ?? NSRange(location: selectedRange.location, length: 0)
    }

    /// `selectWord:` and friends: the unit around the selection.
    @discardableResult
    internal func _tk2Select(_ granularity: NSTextSelection.Granularity) -> Bool {
        guard let tlm = _textLayoutManager else { return false }
        _tk2Apply(tlm.textSelectionNavigation.textSelection(for: granularity, enclosing: _tk2CurrentSelection))
        return true
    }

    // MARK: Mouse

    /// Click, shift-click, double- and triple-click through the navigation.
    internal func _tk2MouseDown(with event: NSEvent) {
        guard let tlm = _textLayoutManager else { return }
        guard isEditable || isSelectable else { return }
        if window?.firstResponder !== self { _ = window?.makeFirstResponder(self) }
        let p = _tk2ContainerPoint(convert(event.locationInWindow, from: nil))
        let nav = tlm.textSelectionNavigation
        let doc = tlm.documentRange.location
        _clickCount = event.clickCount
        var result: NSTextSelection?
        switch event.clickCount {
        case 2: result = nav.textSelection(for: .word, enclosing: p, inContainerAt: doc)
        case 3: result = nav.textSelection(for: .paragraph, enclosing: p, inContainerAt: doc)
        default:
            let modifiers: NSTextSelectionNavigation.Modifier = event.modifierFlags.contains(.shift) ? .extend : []
            result = nav.textSelections(interactingAt: p, inContainerAt: doc, anchors: [_tk2CurrentSelection], modifiers: modifiers, selecting: false, bounds: visibleRect).first
        }
        if let s = result {
            _tk2Apply(s)
            if s.textRanges.first?.isEmpty == true, !event.modifierFlags.contains(.shift) { _selectionAnchor = s.textRanges.first?._nsRange?.location }
        }
        _tk2.dragAnchors = tlm._rawTextSelections
        if let first = _tk2.dragAnchors.first, first.textRanges.first?.isEmpty == true {
            first._anchor = first.textRanges.first?.location
        }
        _tk2.dragging = true
    }

    /// A drag extends the mouse-down selection by its granularity.
    internal func _tk2MouseDragged(with event: NSEvent) {
        guard let tlm = _textLayoutManager, _tk2.dragging, !_tk2.dragAnchors.isEmpty else { return }
        let p = _tk2ContainerPoint(convert(event.locationInWindow, from: nil))
        guard let s = tlm.textSelectionNavigation.textSelections(interactingAt: p, inContainerAt: tlm.documentRange.location, anchors: _tk2.dragAnchors,
                                                                 modifiers: [], selecting: true, bounds: visibleRect).first else { return }
        _tk2Apply(s)
        _ = autoscroll(with: event)
    }

    internal func _tk2MouseUp() { _tk2.dragging = false }

    // MARK: Geometry

    internal func _tk2ContainerPoint(_ p: NSPoint) -> CGPoint {
        let origin = _drawOrigin
        return CGPoint(x: p.x - origin.x, y: p.y - origin.y)
    }

    /// The visible part of the view in container coordinates (all of it outside a scroll view).
    internal var _tk2ViewportBounds: CGRect {
        let origin = _drawOrigin
        let visible = enclosingScrollView != nil ? visibleRect : bounds
        return visible.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    internal func _tk2LayoutLines() -> [_Line] {
        guard let tlm = _textLayoutManager else { return [] }
        let origin = _drawOrigin
        var lines: [_Line] = []
        _ = tlm.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout, .ensuresExtraLineFragment]) { f in
            let frame = f.layoutFragmentFrame
            let base = f._documentOffset
            for l in f.textLineFragments {
                lines.append(_Line(range: NSRange(location: base + l.characterRange.location, length: l.characterRange.length - l._newlineLength),
                                   y: frame.minY + l.typographicBounds.minY + origin.y, width: l.typographicBounds.width, endsWithNewline: l._newlineLength > 0))
            }
            return true
        }
        return lines
    }

    internal func _tk2CaretRect(for offset: Int) -> NSRect {
        let origin = _drawOrigin
        guard let tlm = _textLayoutManager else { return .zero }
        let upstream = tlm._rawTextSelections.first.map { $0.affinity == .upstream && $0.textRanges.first?._nsRange == NSRange(location: offset, length: 0) } ?? false
        var rect = NSRect(x: origin.x + (textContainer?.lineFragmentPadding ?? 0), y: origin.y, width: 1, height: _lineHeight)
        tlm.enumerateTextSegments(in: NSTextRange(location: _NSTextIndexLocation(min(offset, _length))), type: .selection, options: upstream ? [.upstreamAffinity] : []) { _, r, _, _ in
            rect = NSRect(x: r.minX + origin.x, y: r.minY + origin.y, width: 1, height: r.height)
            return false
        }
        return rect
    }

    internal func _tk2Offset(at point: NSPoint) -> Int {
        _textLayoutManager?._caretOffset(at: _tk2ContainerPoint(point)) ?? 0
    }

    internal var _tk2ContentSize: NSSize {
        guard let tlm = _textLayoutManager else { return .zero }
        let usage = tlm.usageBoundsForTextContainer
        let padding = isFieldEditor ? 0 : (textContainer?.lineFragmentPadding ?? 0)
        var used: CGFloat = 0
        for f in tlm._allFragments where f.state == .layoutAvailable { for l in f._lines { used = max(used, l.typographicBounds.maxX) } }
        let inset = textContainerInset
        return NSSize(width: (max(0, used - padding) + 2 * padding + 2 * inset.width).rounded(.up),
                      height: max(usage.maxY, _lineHeight) + 2 * inset.height)
    }

    /// The rects of a character range in view coordinates (find highlights, marked text).
    internal func _tk2Rects(forCharacterRange range: NSRange, type: NSTextLayoutManager.SegmentType = .standard) -> [NSRect] {
        guard let tlm = _textLayoutManager, range.length > 0 else { return [] }
        let origin = _drawOrigin
        var out: [NSRect] = []
        tlm.enumerateTextSegments(in: NSTextRange._make(_clamped(range)), type: type, options: [.rangeNotRequired]) { _, r, _, _ in
            out.append(r.offsetBy(dx: origin.x, dy: origin.y))
            return true
        }
        return out
    }

    /// An attachment's frame in view coordinates.
    internal func _tk2AttachmentFrame(at index: Int) -> NSRect? {
        guard let tlm = _textLayoutManager, let f = tlm.textLayoutFragment(for: _NSTextIndexLocation(index)) else { return nil }
        let r = f.frameForTextAttachment(at: _NSTextIndexLocation(index))
        guard r != .zero else { return nil }
        let origin = _drawOrigin
        return r.offsetBy(dx: f.layoutFragmentFrame.minX + origin.x, dy: f.layoutFragmentFrame.minY + origin.y)
    }

    // MARK: Layout and drawing

    /// Lays out the viewport (from `layout()` and scrolling; never from drawing).
    internal func _tk2LayoutViewport() {
        _textLayoutManager?.textViewportLayoutController.layoutViewport()
    }

    /// Fits a resizable view's frame to the usage bounds, as TextKit 1's layout does.
    internal func _tk2FitFrame() {
        guard _textLayoutManager != nil, !isFieldEditor, isVerticallyResizable || isHorizontallyResizable, !_fittingFrame else { return }
        _fittingFrame = true
        defer { _fittingFrame = false }
        let content = _tk2ContentSize
        let size = NSSize(width: isHorizontallyResizable ? max(minSize.width, min(maxSize.width, content.width)) : frame.width,
                          height: isVerticallyResizable ? max(minSize.height, min(maxSize.height, content.height)) : frame.height)
        if size != frame.size { setFrameSize(size) }
    }

    /// Scrolling lays the newly visible fragments out before they draw.
    internal func _tk2ObserveClipView() {
        guard let clip = superview as? NSClipView, _tk2.observedClipView !== clip else { return }
        if let token = _tk2.clipObserver { NotificationCenter.default.removeObserver(token) }
        _tk2.observedClipView = clip
        clip.postsBoundsChangedNotifications = true
        _tk2.clipObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self._textLayoutManager != nil else { return }
                self.needsLayout = true
            }
        }
    }

    /// Draws the fragments in `dirtyRect`: backgrounds, the selection and find highlights
    /// below, glyphs, then the highlights above (TextKit 1's order).
    internal func _tk2Draw(_ dirtyRect: NSRect) {
        guard let tlm = _textLayoutManager, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let origin = _drawOrigin
        let area = dirtyRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let before = tlm._allFragments.filter { $0.state == .layoutAvailable }.count
        let fragments = tlm._layoutFragments(in: area)
        if tlm._allFragments.filter({ $0.state == .layoutAvailable }).count != before, !_tk2.fitScheduled {
            // Laid out while drawing (no layout pass ran first): fit the frame afterwards.
            _tk2.fitScheduled = true
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self._tk2.fitScheduled = false
                    self._tk2FitFrame()
                }
            }
        }
        // Laid out (colours resolved) under one appearance, drawn under another (printing
        // from a dark window): resolve again; the geometry does not change.
        let dark = effectiveAppearance.isDark
        for f in fragments where f._laidOutDark != nil && f._laidOutDark != dark { tlm._layout(f) }
        for f in fragments { f._drawBackground(at: CGPoint(x: origin.x + f._origin.x, y: origin.y + f._origin.y)) }
        let sel = selectedRange
        if sel.length > 0 {
            _selectionHighlightColor.setFill()
            for r in _tk2Rects(forCharacterRange: sel, type: .selection) where r.intersects(dirtyRect) { NSBezierPath.fill(r) }
        }
        _drawFindHighlights(above: false)
        for f in fragments { f._drawForeground(at: CGPoint(x: origin.x + f._origin.x, y: origin.y + f._origin.y), in: ctx) }
        _drawFindHighlights(above: true)
    }

    // MARK: Spelling marks (temporary attributes in TextKit 1, rendering attributes in 2)

    internal func _setSpellingMark(_ value: Int, range r: NSRange) {
        if let tlm = _textLayoutManager {
            if value == 0 { tlm.removeRenderingAttribute(.spellingState, for: NSTextRange._make(r)) }
            else { tlm.addRenderingAttribute(.spellingState, value: NSNumber(value: value), for: NSTextRange._make(r)) }
            return
        }
        if value == 0 { _layoutManager.removeTemporaryAttribute(.spellingState, forCharacterRange: r) }
        else { _layoutManager.addTemporaryAttribute(.spellingState, value: NSNumber(value: value), forCharacterRange: r) }
    }

    /// The marked (misspelt) run at `index`, if any.
    internal func _spellingMark(at index: Int) -> NSRange? {
        if let tlm = _textLayoutManager {
            var found: NSRange?
            tlm.enumerateRenderingAttributes(from: _NSTextIndexLocation(index), reverse: false) { _, attrs, r in
                guard let nr = r._nsRange, nr.location <= index else { return false }
                if let v = (attrs[.spellingState] as? NSNumber)?.intValue, v != 0, NSLocationInRange(index, nr) { found = nr }
                return false
            }
            return found
        }
        var r = NSRange(location: 0, length: 0)
        guard let state = _layoutManager.temporaryAttribute(.spellingState, atCharacterIndex: index, effectiveRange: &r) as? NSNumber, state.intValue != 0 else { return nil }
        return r
    }
}
