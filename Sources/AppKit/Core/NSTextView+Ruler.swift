// NSTextView as the client of its scroll view's horizontal ruler (ADR-0034).
//
// With `usesRuler` on and the enclosing scroll view showing its rulers, the text view
// takes the horizontal ruler when its selection changes (or `toggleRuler(_:)` shows it)
// and `updateRuler()` puts up the markers of the selected paragraph's style: first-line,
// head and tail indents and the tab stops, from
// `NSLayoutManager.rulerMarkers(for:paragraphStyle:ruler:)`. Moving a marker changes that
// value in the paragraphs `rangeForUserParagraphAttributeChange` covers (or the typing
// attributes in an empty selection of an empty paragraph); dragging a tab stop off the
// ruler removes it, and a click on the rule adds a left tab stop where it is dropped.
// Marker locations are the view's own x: the container origin plus the line fragment
// padding plus the indent.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension NSTextView {
    /// What an indent marker stands for (its `representedObject`); a tab stop's is its NSTextTab.
    internal static let _firstLineIndentMarker = "NSFirstLineHeadIndentRulerMarker" as NSString
    internal static let _headIndentMarker = "NSHeadIndentRulerMarker" as NSString
    internal static let _tailIndentMarker = "NSTailIndentRulerMarker" as NSString

    /// The x of the leading text margin (indent 0) in the view.
    internal var _rulerLeadingX: CGFloat { textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0) }
    /// The x of the trailing text margin (tail indent 0).
    internal var _rulerTrailingX: CGFloat {
        let width = textContainer?.size.width ?? bounds.width
        return textContainerOrigin.x + width - (textContainer?.lineFragmentPadding ?? 0)
    }

    /// The horizontal ruler this text view can be the client of: its scroll view's, shown.
    internal var _availableRuler: NSRulerView? {
        guard usesRuler, let sv = enclosingScrollView, sv.rulersVisible, sv.hasHorizontalRuler else { return nil }
        return sv.horizontalRulerView
    }

    /// Becomes the ruler's client (if it is not already) and refreshes the markers.
    internal func _takeRulerIfAvailable() {
        guard let ruler = _availableRuler else { return }
        if ruler.clientView !== self { ruler.clientView = self }
        updateRuler()
    }

    /// The style of the paragraph at the selection.
    internal var _rulerParagraphStyle: NSParagraphStyle {
        let sel = selectedRange()
        if let storage = textStorage, storage.length > 0 {
            let at = min(sel.location, storage.length - 1)
            if sel.location < storage.length || sel.location == storage.length && sel.location > 0,
               let ps = storage.attribute(.paragraphStyle, at: at, effectiveRange: nil) as? NSParagraphStyle {
                return ps
            }
        }
        return (typingAttributes[.paragraphStyle] as? NSParagraphStyle) ?? defaultParagraphStyle ?? .default
    }

    internal func _updateRulerMarkers() {
        guard let ruler = _availableRuler, ruler.clientView === self, let lm = layoutManager else { return }
        ruler.markers = lm.rulerMarkers(for: self, paragraphStyle: _rulerParagraphStyle, ruler: ruler)
    }

    /// Applies `change` to the paragraph styles of the paragraphs a paragraph attribute
    /// change covers, as one undoable edit.
    internal func _changeParagraphStyles(_ change: (NSMutableParagraphStyle) -> Void) {
        let range = rangeForUserParagraphAttributeChange
        guard range.location != NSNotFound else { return }
        guard let storage = textStorage, range.length > 0 else {
            let ps = (_rulerParagraphStyle.mutableCopy() as! NSMutableParagraphStyle)
            change(ps)
            var attrs = typingAttributes
            attrs[.paragraphStyle] = ps.copy() as! NSParagraphStyle
            typingAttributes = attrs
            return
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        var runs: [(NSRange, NSParagraphStyle)] = []
        storage.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, r, _ in
            runs.append((r, (value as? NSParagraphStyle) ?? self.defaultParagraphStyle ?? .default))
        }
        for (r, style) in runs {
            let ps = style.mutableCopy() as! NSMutableParagraphStyle
            change(ps)
            storage.addAttribute(.paragraphStyle, value: ps.copy() as! NSParagraphStyle, range: r)
        }
        storage.endEditing()
        didChangeText()
    }

    /// Tab stops match by alignment and location (each paragraph has its own objects).
    private static func _sameTab(_ a: NSTextTab, _ b: NSTextTab) -> Bool {
        a.alignment == b.alignment && abs(a.location - b.location) < 0.01
    }

    internal func _rulerDidMove(_ marker: NSRulerMarker) {
        let leading = _rulerLeadingX, trailing = _rulerTrailingX
        let x = marker.markerLocation
        let represented = marker.representedObject
        if let tab = represented as? NSTextTab {
            let moved = NSTextTab(textAlignment: tab.alignment, location: max(0, x - leading), options: tab.options)
            _changeParagraphStyles { ps in
                ps.tabStops = ps.tabStops.map { NSTextView._sameTab($0, tab) ? moved : $0 }.sorted { $0.location < $1.location }
            }
            marker.representedObject = moved
        } else if let name = represented as? NSString {
            let indent = max(0, x - leading)
            if name == NSTextView._firstLineIndentMarker {
                _changeParagraphStyles { $0.firstLineHeadIndent = indent }
            } else if name == NSTextView._headIndentMarker {
                _changeParagraphStyles { $0.headIndent = indent }
            } else if name == NSTextView._tailIndentMarker {
                _changeParagraphStyles { $0.tailIndent = min(0, x - trailing) }
            }
        }
        _updateRulerMarkers()
    }

    internal func _rulerDidRemove(_ marker: NSRulerMarker) {
        guard let tab = marker.representedObject as? NSTextTab else { return }
        _changeParagraphStyles { ps in ps.tabStops = ps.tabStops.filter { !NSTextView._sameTab($0, tab) } }
        _updateRulerMarkers()
    }

    internal func _rulerDidAdd(_ marker: NSRulerMarker) {
        let tab = NSTextTab(textAlignment: .left, location: max(0, marker.markerLocation - _rulerLeadingX))
        _changeParagraphStyles { ps in
            ps.tabStops = (ps.tabStops.filter { !NSTextView._sameTab($0, tab) } + [tab]).sorted { $0.location < $1.location }
        }
        _updateRulerMarkers()
    }

    /// A click on the rule starts dragging a new left tab stop.
    internal func _rulerHandleMouseDown(_ ruler: NSRulerView, _ event: NSEvent) {
        guard isEditable, isRichText else { return }
        let marker = NSRulerMarker(rulerView: ruler, markerLocation: 0, image: NSRulerView._markerImage(.leftTab), imageOrigin: NSPoint(x: 4.5, y: 0))
        marker.isRemovable = true
        _ = ruler.trackMarker(marker, withMouseEvent: event)
    }

    /// Markers stay within the text margins.
    internal func _rulerClamp(_ marker: NSRulerMarker, _ location: CGFloat) -> CGFloat {
        min(max(location, _rulerLeadingX), max(_rulerLeadingX, _rulerTrailingX))
    }
}

extension NSLayoutManager {
    /// The markers `rulerMarkers(for:paragraphStyle:ruler:)` makes: indents, then tab stops.
    @MainActor internal func _rulerMarkers(for view: NSTextView, paragraphStyle style: NSParagraphStyle, ruler: NSRulerView) -> [NSRulerMarker] {
        let leading = view._rulerLeadingX, trailing = view._rulerTrailingX
        let mid = NSPoint(x: 4.5, y: 0)
        func marker(_ x: CGFloat, _ kind: NSRulerView._MarkerKind, _ object: any NSCopying, removable: Bool = false) -> NSRulerMarker {
            let m = NSRulerMarker(rulerView: ruler, markerLocation: x, image: NSRulerView._markerImage(kind), imageOrigin: mid)
            m.representedObject = object
            m.isRemovable = removable
            m.isMovable = view.isEditable && view.isRichText
            return m
        }
        var markers = [
            marker(leading + style.firstLineHeadIndent, .firstLineIndent, NSTextView._firstLineIndentMarker),
            marker(leading + style.headIndent, .headIndent, NSTextView._headIndentMarker),
            marker(style.tailIndent > 0 ? leading + style.tailIndent : trailing + style.tailIndent, .tailIndent, NSTextView._tailIndentMarker),
        ]
        for tab in style.tabStops {
            let kind: NSRulerView._MarkerKind
            switch tab.alignment {
            case .right: kind = tab.options[.columnTerminators] != nil ? .decimalTab : .rightTab
            case .center: kind = .centerTab
            default: kind = .leftTab
            }
            markers.append(marker(leading + tab.location, kind, tab, removable: true))
        }
        return markers
    }
}
