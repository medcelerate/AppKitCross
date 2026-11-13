// NSRulerView (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// A ruler a scroll view tiles above (horizontal) or beside (vertical) its content
// (ADR-0034). Across its thickness, from the outer edge: the accessory view's band, the
// markers' band, then the rule with the hash marks, next to the content. The baseline,
// where markers stand, is the border between the markers' band and the rule.
//
// Locations along the axis come in two spaces: marker locations and the origin offset are
// in the client view's coordinates, everything else (hash marks, ruler lines, image rects)
// in the ruler's. Conversion goes through the view hierarchy, so scrolling and a scaled
// client move the marks with the content. The hash marks follow the unit's step cycles:
// labels are spread by the step-up cycle until they are far enough apart, then marks are
// subdivided by the step-down cycle while they stay far enough apart.
//
// Marker drags run on the ruler's mouse events (no modal tracking loop in the port):
// mouse-down on a marker starts the drag, dragged events move it (asking the client),
// and mouse-up ends it — removing a removable marker dragged off the ruler, or adding a
// marker that `trackMarker(_:withMouseEvent:)` started.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(QuartzCore)
import QuartzCore
#endif
#if canImport(CoreText)
import CoreText
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview
@MainActor open class NSRulerView: NSView {
    private weak var _scrollView: NSScrollView?
    private var _orientation: NSRulerView.Orientation
    private weak var _clientView: NSView?
    private var _markers: [NSRulerMarker] = []
    private var _accessoryView: NSView?
    private var _units: NSRulerView.UnitName
    private var _originOffset: CGFloat = 0
    private var _ruleThickness: CGFloat = 16
    private var _reservedForMarkers: CGFloat = 15
    private var _reservedForAccessory: CGFloat = 0
    /// The temporary ruler line `moveRulerline(fromLocation:toLocation:)` shows (ruler coordinates).
    private var _rulerline: CGFloat?

    /// The marker being dragged.
    private struct _Drag {
        let marker: NSRulerMarker
        let adding: Bool
        /// Pointer location minus marker location at the start (client coordinates).
        let grab: CGFloat
        let startLocation: CGFloat
        /// Dragged off the ruler far enough to remove (or not add) it.
        var off: Bool
    }
    private var _drag: _Drag?

    // MARK: Units

    internal struct _Unit {
        let abbreviation: String
        let pointsPerUnit: CGFloat
        let stepUp: [CGFloat]
        let stepDown: [CGFloat]
    }
    private static var _registeredUnits: [NSRulerView.UnitName: _Unit] = [
        .inches: _Unit(abbreviation: "in", pointsPerUnit: 72, stepUp: [2], stepDown: [0.5, 0.5, 0.5]),
        .centimeters: _Unit(abbreviation: "cm", pointsPerUnit: 28.35, stepUp: [2], stepDown: [0.5, 0.2]),
        .points: _Unit(abbreviation: "pt", pointsPerUnit: 1, stepUp: [10], stepDown: [0.5]),
        .picas: _Unit(abbreviation: "pc", pointsPerUnit: 12, stepUp: [10], stepDown: [0.5]),
    ]
    internal static func _unit(named name: NSRulerView.UnitName) -> _Unit? { _registeredUnits[name] }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/registerunit(withname:abbreviation:unittopointsconversionfactor:stepupcycle:stepdowncycle:)
    @MainActor public class func registerUnit(withName unitName: NSRulerView.UnitName, abbreviation: String, unitToPointsConversionFactor conversionFactor: CGFloat, stepUpCycle: [NSNumber], stepDownCycle: [NSNumber]) {
        precondition(conversionFactor > 0, "NSRulerView: the conversion factor must be positive")
        precondition(stepUpCycle.allSatisfy { $0.doubleValue > 1 }, "NSRulerView: step-up values must be greater than 1")
        precondition(stepDownCycle.allSatisfy { $0.doubleValue > 0 && $0.doubleValue < 1 }, "NSRulerView: step-down values must be between 0 and 1")
        _registeredUnits[unitName] = _Unit(abbreviation: abbreviation, pointsPerUnit: conversionFactor,
                                           stepUp: stepUpCycle.map { CGFloat($0.doubleValue) },
                                           stepDown: stepDownCycle.map { CGFloat($0.doubleValue) })
    }

    /// Inches where the locale's region measures in them (the United States, Liberia,
    /// Myanmar), centimetres elsewhere.
    private static var _defaultUnits: NSRulerView.UnitName {
        let id = Locale.current.identifier
        return ["US", "LR", "MM"].contains { id.hasSuffix("_" + $0) || id.contains("_\($0)@") || id.contains("_\($0)_") } ? .inches : .centimeters
    }

    // MARK: Initialisers

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/init(coder:)
    public required init?(coder: NSCoder) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/init(scrollview:orientation:)
    @MainActor public init(scrollView: NSScrollView?, orientation: NSRulerView.Orientation) {
        _scrollView = scrollView
        _orientation = orientation
        _units = NSRulerView._defaultUnits
        super.init(frame: .zero)
    }

    // MARK: Properties

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/accessoryview
    @MainActor open var accessoryView: NSView? {
        get { _accessoryView }
        set {
            guard newValue !== _accessoryView else { return }
            _accessoryView?.removeFromSuperview()
            _accessoryView = newValue
            if let v = newValue { addSubview(v) }
            _layoutAccessory()
            _thicknessMayHaveChanged()
        }
    }
    /// The border between the markers' band and the rule, across the ruler.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/baselinelocation
    @MainActor open var baselineLocation: CGFloat { _accessoryThickness + _markersThickness }
    /// Setting a new client removes the markers and the accessory view, after telling the
    /// old client with `rulerView(_:willSetClientView:)`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/clientview
    @MainActor open var clientView: NSView? {
        get { _clientView }
        set {
            guard newValue !== _clientView else { return }
            if let old = _clientView, let new = newValue { old.rulerView(self, willSetClientView: new) }
            _endDrag(cancel: true)
            _markers.removeAll()
            accessoryView = nil
            _clientView = newValue
            needsDisplay = true
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/isflipped
    @MainActor open override var isFlipped: Bool {
        if _orientation == .horizontalRuler { return true }
        return (_clientView ?? _scrollView?.documentView)?.isFlipped ?? true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/markers
    @MainActor open var markers: [NSRulerMarker]? {
        get { _markers.isEmpty ? nil : _markers }
        set {
            _markers = newValue ?? []
            _thicknessMayHaveChanged()
            needsDisplay = true
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/measurementunits
    @MainActor open var measurementUnits: NSRulerView.UnitName {
        get { _units }
        set {
            precondition(NSRulerView._registeredUnits[newValue] != nil, "NSRulerView: unknown measurement units \(newValue.rawValue)")
            _units = newValue
            invalidateHashMarks()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/orientation
    @MainActor open var orientation: NSRulerView.Orientation {
        get { _orientation }
        set {
            guard newValue != _orientation else { return }
            _orientation = newValue
            _layoutAccessory()
            _scrollView?.tile()
            needsDisplay = true
        }
    }
    /// The zero mark's distance from the client view's bounds origin, in the client's coordinates.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/originoffset
    @MainActor open var originOffset: CGFloat {
        get { _originOffset }
        set { _originOffset = newValue; invalidateHashMarks() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/requiredthickness
    @MainActor open var requiredThickness: CGFloat { _accessoryThickness + _markersThickness + _ruleThickness }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/reservedthicknessforaccessoryview
    @MainActor open var reservedThicknessForAccessoryView: CGFloat {
        get { _reservedForAccessory }
        set { _reservedForAccessory = max(0, newValue); _layoutAccessory(); _thicknessMayHaveChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/reservedthicknessformarkers
    @MainActor open var reservedThicknessForMarkers: CGFloat {
        get { _reservedForMarkers }
        set { _reservedForMarkers = max(0, newValue); _layoutAccessory(); _thicknessMayHaveChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/rulethickness
    @MainActor open var ruleThickness: CGFloat {
        get { _ruleThickness }
        set { _ruleThickness = max(0, newValue); _thicknessMayHaveChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/scrollview
    @MainActor open var scrollView: NSScrollView? {
        get { _scrollView }
        set { _scrollView = newValue }
    }

    private var _accessoryThickness: CGFloat {
        guard let a = _accessoryView else { return _reservedForAccessory }
        return max(_reservedForAccessory, _orientation == .horizontalRuler ? a.frame.height : a.frame.width)
    }
    private var _markersThickness: CGFloat {
        _markers.reduce(_reservedForMarkers) { max($0, $1.thicknessRequiredInRuler) }
    }

    private func _thicknessMayHaveChanged() {
        if let sv = _scrollView, sv.rulersVisible { sv.tile() }
        needsDisplay = true
    }

    private func _layoutAccessory() {
        guard let a = _accessoryView else { return }
        let t = _accessoryThickness
        if _orientation == .horizontalRuler {
            a.setFrameOrigin(NSPoint(x: a.frame.minX, y: (t - a.frame.height) / 2))
        } else {
            a.setFrameOrigin(NSPoint(x: (t - a.frame.width) / 2, y: a.frame.minY))
        }
    }

    // MARK: Markers

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/addmarker(_:)
    @MainActor open func addMarker(_ marker: NSRulerMarker) {
        guard !_markers.contains(where: { $0 === marker }) else { return }
        _markers.append(marker)
        _thicknessMayHaveChanged()
        setNeedsDisplay(marker.imageRectInRuler.insetBy(dx: -1, dy: -1))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/removemarker(_:)
    @MainActor open func removeMarker(_ marker: NSRulerMarker) {
        guard let i = _markers.firstIndex(where: { $0 === marker }) else { return }
        _markers.remove(at: i)
        setNeedsDisplay(marker.imageRectInRuler.insetBy(dx: -1, dy: -1))
        _thicknessMayHaveChanged()
    }

    /// Starts dragging a new marker from a mouse-down in the ruler; it is added when the
    /// drag ends on the ruler. Returns whether the drag started (the client may refuse it).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/trackmarker(_:withmouseevent:)
    @MainActor open func trackMarker(_ marker: NSRulerMarker, withMouseEvent event: NSEvent) -> Bool {
        _beginTracking(marker, adding: true, event: event)
    }

    internal func _beginTracking(_ marker: NSRulerMarker, adding: Bool, event: NSEvent) -> Bool {
        guard _drag == nil else { return false }
        if adding {
            if let c = _clientView, !c.rulerView(self, shouldAdd: marker) { return false }
        } else {
            guard _markers.contains(where: { $0 === marker }) else { return false }
            guard marker.isMovable || marker.isRemovable else { return false }
            if marker.isMovable, let c = _clientView, !c.rulerView(self, shouldMove: marker) {
                if !marker.isRemovable { return false }
            }
        }
        let pointer = _clientLocation(forRulerPoint: convert(event.locationInWindow, from: nil))
        // A new marker jumps to the pointer; a moved one keeps where it was grabbed.
        let grab = adding ? 0 : pointer - marker.markerLocation
        if adding { marker.markerLocation = pointer }
        _drag = _Drag(marker: marker, adding: adding, grab: grab, startLocation: marker.markerLocation, off: false)
        marker._isDragging = true
        needsDisplay = true
        return true
    }

    /// The marker being dragged: still in `markers` for a move, separate while adding.
    internal var _draggedMarker: NSRulerMarker? { _drag?.marker }

    private func _continueDrag(with event: NSEvent) {
        guard var d = _drag else { return }
        let p = convert(event.locationInWindow, from: nil)
        let across = _orientation == .horizontalRuler ? p.y : p.x
        // More than the ruler's thickness off either side of it takes the marker off.
        d.off = across < -requiredThickness || across > 2 * requiredThickness
        if d.off && !d.adding && !d.marker.isRemovable { d.off = false }
        let marker = d.marker
        if !d.off && (d.adding || marker.isMovable) {
            var location = _clientLocation(forRulerPoint: p) - d.grab
            if let c = _clientView {
                location = d.adding ? c.rulerView(self, willAdd: marker, atLocation: location) : c.rulerView(self, willMove: marker, toLocation: location)
            }
            marker.markerLocation = location
        }
        _drag = d
        needsDisplay = true
    }

    private func _endDrag(cancel: Bool) {
        guard let d = _drag else { return }
        _drag = nil
        let marker = d.marker
        marker._isDragging = false
        needsDisplay = true
        if cancel {
            if !d.adding { marker.markerLocation = d.startLocation }
            return
        }
        if d.adding {
            guard !d.off else { return }
            addMarker(marker)
            _clientView?.rulerView(self, didAdd: marker)
        } else if d.off {
            if let c = _clientView, !c.rulerView(self, shouldRemove: marker) {
                marker.markerLocation = d.startLocation
                return
            }
            removeMarker(marker)
            _clientView?.rulerView(self, didRemove: marker)
        } else if marker.markerLocation != d.startLocation {
            _clientView?.rulerView(self, didMove: marker)
        }
    }

    // MARK: Events

    /// A mouse-down on a marker drags it; elsewhere it goes to the client view's
    /// `rulerView(_:handleMouseDownWith:)` (a text view adds a tab stop there).
    @MainActor open override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let m = _markers.last(where: { $0.imageRectInRuler.contains(p) }) {
            _ = m.trackMouse(with: event, adding: false)
            return
        }
        _clientView?.rulerView(self, handleMouseDownWith: event)
    }
    @MainActor open override func mouseDragged(with event: NSEvent) {
        if _drag != nil { _continueDrag(with: event) } else { super.mouseDragged(with: event) }
    }
    @MainActor open override func mouseUp(with event: NSEvent) {
        if _drag != nil {
            _continueDrag(with: event)
            _endDrag(cancel: false)
        } else {
            super.mouseUp(with: event)
        }
    }

    // MARK: Coordinates

    private var _axisIsX: Bool { _orientation == .horizontalRuler }

    /// A client-view location along the axis, in the ruler's coordinates.
    internal func _rulerLocation(forClientLocation location: CGFloat) -> CGFloat {
        guard let c = _clientView else { return location }
        let p = c.rulerView(self, pointForLocation: location)
        let q = convert(p, from: c)
        return _axisIsX ? q.x : q.y
    }

    /// The client-view location under a point of the ruler.
    internal func _clientLocation(forRulerPoint p: NSPoint) -> CGFloat {
        guard let c = _clientView else { return _axisIsX ? p.x : p.y }
        // Only the axis coordinate matters; the other is put inside the client.
        let q = c.convert(p, from: self)
        let point = _axisIsX ? NSPoint(x: q.x, y: c.bounds.midY) : NSPoint(x: c.bounds.midX, y: q.y)
        return c.rulerView(self, locationFor: point)
    }

    /// The client-view location of the zero mark.
    private var _zeroLocation: CGFloat {
        guard let c = _clientView else { return _originOffset }
        return (_axisIsX ? c.bounds.minX : c.bounds.minY) + _originOffset
    }

    // MARK: Hash marks

    /// A hash mark: its location in the ruler's coordinates, its level (0 for the labelled
    /// marks, one more for each subdivision) and its label.
    internal struct _HashMark: Equatable {
        let location: CGFloat
        let level: Int
        let label: String?
    }

    /// Labels closer than this (points) are spread out by the step-up cycle.
    internal var _minimumLabelSpacing: CGFloat { _axisIsX ? 36 : 24 }
    /// Marks closer than this are not subdivided further.
    internal static let _minimumMarkSpacing: CGFloat = 5

    /// The units each level of marks steps by: the labelled step first, then each
    /// subdivision of the step-down cycle that keeps marks far enough apart.
    internal func _levels() -> [CGFloat] {
        guard let unit = NSRulerView._registeredUnits[_units] else { return [1] }
        let perUnit = _rulerUnitLength(unit)
        guard perUnit > 0 else { return [1] }
        var label: CGFloat = 1
        var i = 0
        if !unit.stepUp.isEmpty {
            while label * perUnit < _minimumLabelSpacing && i < 64 {
                label *= unit.stepUp[i % unit.stepUp.count]
                i += 1
            }
        }
        var levels = [label]
        var step = label
        var j = 0
        if !unit.stepDown.isEmpty {
            while j < 16 {
                let next = step * unit.stepDown[j % unit.stepDown.count]
                if next * perUnit < NSRulerView._minimumMarkSpacing { break }
                step = next
                levels.append(step)
                j += 1
            }
        }
        return levels
    }

    /// One unit's length in the ruler's coordinates (the client's scale applies).
    private func _rulerUnitLength(_ unit: _Unit) -> CGFloat {
        abs(_rulerLocation(forClientLocation: unit.pointsPerUnit) - _rulerLocation(forClientLocation: 0))
    }

    /// The hash marks between two ruler locations.
    internal func _hashMarks(from start: CGFloat, to end: CGFloat) -> [_HashMark] {
        guard let unit = NSRulerView._registeredUnits[_units] else { return [] }
        let levels = _levels()
        guard let finest = levels.last, finest > 0 else { return [] }
        let a = _clientLocationForRulerLocation(start), b = _clientLocationForRulerLocation(end)
        let zero = _zeroLocation
        let lo = (min(a, b) - zero) / unit.pointsPerUnit, hi = (max(a, b) - zero) / unit.pointsPerUnit
        let first = Int((lo / finest).rounded(.up)), last = Int((hi / finest).rounded(.down))
        guard first <= last, last - first < 100_000 else { return [] }
        var marks: [_HashMark] = []
        for k in first...last {
            let u = CGFloat(k) * finest
            var level = levels.count - 1
            for (L, step) in levels.enumerated() {
                let q = u / step
                if abs(q - q.rounded()) < 1e-6 { level = L; break }
            }
            let location = _rulerLocation(forClientLocation: zero + u * unit.pointsPerUnit)
            marks.append(_HashMark(location: location, level: level, label: level == 0 ? NSRulerView._label(u) : nil))
        }
        return marks
    }

    private func _clientLocationForRulerLocation(_ l: CGFloat) -> CGFloat {
        _clientLocation(forRulerPoint: _axisIsX ? NSPoint(x: l, y: 0) : NSPoint(x: 0, y: l))
    }

    private static func _label(_ units: CGFloat) -> String {
        let r = units.rounded()
        if abs(units - r) < 1e-6 { return String(Int(r)) }
        var s = String(format: "%.2f", Double(units))
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// Recomputes the marks on the next draw.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/invalidatehashmarks()
    @MainActor open func invalidateHashMarks() { needsDisplay = true }

    // MARK: Drawing

    @MainActor open override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath.fill(dirtyRect)
        drawHashMarksAndLabels(in: dirtyRect)
        drawMarkers(in: dirtyRect)
        if let l = _rulerline {
            NSColor.labelColor.setFill()
            let b = baselineLocation
            NSBezierPath.fill(_axisIsX ? NSRect(x: l.rounded(.down), y: b, width: 1, height: _ruleThickness)
                                       : NSRect(x: b, y: l.rounded(.down), width: _ruleThickness, height: 1))
        }
    }

    /// The rule's background, the marks (from the content edge towards the baseline, longer
    /// for coarser levels), the labels beside the labelled marks and the edge line.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/drawhashmarksandlabels(in:)
    @MainActor open func drawHashMarksAndLabels(in rect: NSRect) {
        let base = baselineLocation
        let rule = _ruleThickness
        guard rule > 0 else { return }
        let ruleRect = _axisIsX ? NSRect(x: bounds.minX, y: base, width: bounds.width, height: rule)
                                : NSRect(x: base, y: bounds.minY, width: rule, height: bounds.height)
        guard ruleRect.intersects(rect) else { return }
        let start = _axisIsX ? rect.minX : rect.minY, end = _axisIsX ? rect.maxX : rect.maxY
        // Labels reach back past the dirty rect's start.
        let marks = _hashMarks(from: start - _minimumLabelSpacing, to: end)
        let edge = base + rule        // the content side of the rule
        NSColor.secondaryLabelColor.setFill()
        let font = NSFont.systemFont(ofSize: 9)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        for m in marks {
            let length: CGFloat
            switch m.level {
            case 0: length = rule * 0.75
            case 1: length = rule * 0.5
            case 2: length = rule * 0.35
            default: length = rule * 0.25
            }
            let x = m.location.rounded(.down)
            if _axisIsX {
                NSBezierPath.fill(NSRect(x: x, y: edge - length, width: 1, height: length))
            } else {
                NSBezierPath.fill(NSRect(x: edge - length, y: x, width: length, height: 1))
            }
            if let label = m.label {
                let s = label as NSString
                let size = s.size(withAttributes: attrs)
                let origin: NSPoint
                if _axisIsX {
                    origin = NSPoint(x: x + 2, y: base + 1)
                } else {
                    origin = NSPoint(x: base + 1, y: isFlipped ? x + 1 : x - size.height - 1)
                }
                s.draw(at: origin, withAttributes: attrs)
            }
        }
        NSColor.separatorColor.setFill()
        NSBezierPath.fill(_axisIsX ? NSRect(x: rect.minX, y: edge - 1, width: rect.width, height: 1)
                                   : NSRect(x: edge - 1, y: rect.minY, width: 1, height: rect.height))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/drawmarkers(in:)
    @MainActor open func drawMarkers(in rect: NSRect) {
        for m in _markers where !(m === _drag?.marker && _drag?.off == true) {
            m.draw(rect)
        }
        if let d = _drag, d.adding, !d.off { d.marker.draw(rect) }
    }
    /// Shows a temporary line across the rule at `newLocation` (ruler coordinates),
    /// removing the one at `oldLocation`; a negative location means none.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrulerview/moverulerline(fromlocation:tolocation:)
    @MainActor open func moveRulerline(fromLocation oldLocation: CGFloat, toLocation newLocation: CGFloat) {
        _rulerline = newLocation >= 0 ? newLocation : nil
        needsDisplay = true
    }
    internal var _rulerlineLocation: CGFloat? { _rulerline }

    // MARK: Standard marker images

    /// Package-drawn marker images: a tab stop (a small triangle pointing at the
    /// baseline) and the indent markers text views use. `imageOrigin` for each is the
    /// middle of its bottom edge.
    internal enum _MarkerKind { case leftTab, rightTab, centerTab, decimalTab, firstLineIndent, headIndent, tailIndent }

    internal static func _markerImage(_ kind: _MarkerKind) -> NSImage {
        let size = NSSize(width: 9, height: 7)
        return NSImage(size: size, flipped: false) { r in
            let p = NSBezierPath()
            switch kind {
            case .leftTab, .rightTab, .centerTab, .decimalTab:
                // An arrowhead standing on the baseline.
                p.move(to: NSPoint(x: r.midX, y: 0))
                p.line(to: NSPoint(x: r.maxX, y: r.maxY - 2))
                p.line(to: NSPoint(x: r.minX, y: r.maxY - 2))
                p.close()
                NSColor.labelColor.setFill()
                p.fill()
                let bar: NSRect
                switch kind {
                case .leftTab: bar = NSRect(x: r.midX - 0.5, y: r.maxY - 2, width: 4, height: 2)
                case .rightTab: bar = NSRect(x: r.midX - 3.5, y: r.maxY - 2, width: 4, height: 2)
                case .centerTab: bar = NSRect(x: r.midX - 2.5, y: r.maxY - 2, width: 5, height: 2)
                default: bar = NSRect(x: r.midX + 2, y: r.maxY - 2, width: 2, height: 2)
                }
                NSBezierPath.fill(bar)
            case .firstLineIndent:
                p.move(to: NSPoint(x: r.minX, y: r.maxY))
                p.line(to: NSPoint(x: r.maxX, y: r.maxY))
                p.line(to: NSPoint(x: r.midX, y: 0))
                p.close()
                NSColor.controlAccentColor.setFill()
                p.fill()
            case .headIndent, .tailIndent:
                p.move(to: NSPoint(x: r.minX, y: 0))
                p.line(to: NSPoint(x: r.maxX, y: 0))
                p.line(to: NSPoint(x: r.midX, y: r.maxY))
                p.close()
                NSColor.controlAccentColor.setFill()
                p.fill()
            }
            return true
        }
    }
}
