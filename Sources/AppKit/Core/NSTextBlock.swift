// NSTextBlock (hand-written; seeded from the generated stub, see tools/apigen)
//
// A block of paragraphs laid out in a rectangle of its own (`NSParagraphStyle.textBlocks`,
// outermost first): content width and height limits, then padding, border and margin on
// each edge, a background colour and border colours. The layout manager asks
// `rectForLayout(at:in:textContainer:characterRange:)` where to lay the content out and
// `boundsRect(forContentRect:in:textContainer:characterRange:)` for the box around it,
// then `drawBackground(withFrame:in:characterRange:layoutManager:)` (ADR-0030).
// Percentage values are relative to the width of the rectangle the block sits in.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextblock
open class NSTextBlock: NSObject, NSSecureCoding, NSCoding, NSCopying {
    #if !canImport(Darwin)
    /// First stored word: a non-zero CF type ID, see Support/CFBridgeLayout.swift.
    private let _cfinfo = _swiftObjectCFInfo
    #endif
    internal var _values: [Int: (value: CGFloat, type: NSTextBlock.ValueType)] = [:]       // by Dimension
    internal var _widths: [Int: (value: CGFloat, type: NSTextBlock.ValueType)] = [:]       // layer * 8 + edge
    internal var _borderColors: [UInt: NSColor] = [:]
    internal var _backgroundColor: NSColor?
    internal var _verticalAlignment: NSTextBlock.VerticalAlignment = .topAlignment

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextblock/init()
    public override init() { super.init() }

    internal func _copyValues(into other: NSTextBlock) {
        other._values = _values; other._widths = _widths; other._borderColors = _borderColors
        other._backgroundColor = _backgroundColor; other._verticalAlignment = _verticalAlignment
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextblock/backgroundcolor
    open var backgroundColor: NSColor? {
        get { _backgroundColor }
        set { _backgroundColor = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextblock/bordercolor(for:)
    open func borderColor(for edge: NSRectEdge) -> NSColor? { _borderColors[edge.rawValue] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextblock/setbordercolor(_:)
    open func setBorderColor(_ color: NSColor?) {
        for e in NSTextBlock._edges { setBorderColor(color, for: e) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextblock/setbordercolor(_:for:)
    open func setBorderColor(_ color: NSColor?, for edge: NSRectEdge) { _borderColors[edge.rawValue] = color }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextblock/contentwidth
    open var contentWidth: CGFloat { value(for: .width) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextblock/contentwidthvaluetype
    open var contentWidthValueType: NSTextBlock.ValueType { valueType(for: .width) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextblock/setcontentwidth(_:type:)
    open func setContentWidth(_ val: CGFloat, type: NSTextBlock.ValueType) { setValue(val, type: type, for: .width) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextblock/setvalue(_:type:for:)
    open func setValue(_ val: CGFloat, type: NSTextBlock.ValueType, for dimension: NSTextBlock.Dimension) { _values[dimension.rawValue] = (val, type) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextblock/value(for:)
    open func value(for dimension: NSTextBlock.Dimension) -> CGFloat { _values[dimension.rawValue]?.value ?? 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextblock/valuetype(for:)
    open func valueType(for dimension: NSTextBlock.Dimension) -> NSTextBlock.ValueType { _values[dimension.rawValue]?.type ?? .absoluteValueType }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextblock/setwidth(_:type:for:)
    open func setWidth(_ val: CGFloat, type: NSTextBlock.ValueType, for layer: NSTextBlock.Layer) {
        for e in NSTextBlock._edges { setWidth(val, type: type, for: layer, edge: e) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextblock/setwidth(_:type:for:edge:)
    open func setWidth(_ val: CGFloat, type: NSTextBlock.ValueType, for layer: NSTextBlock.Layer, edge: NSRectEdge) {
        _widths[NSTextBlock._key(layer, edge)] = (val, type)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextblock/width(for:edge:)
    open func width(for layer: NSTextBlock.Layer, edge: NSRectEdge) -> CGFloat { _widths[NSTextBlock._key(layer, edge)]?.value ?? 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextblock/widthvaluetype(for:edge:)
    open func widthValueType(for layer: NSTextBlock.Layer, edge: NSRectEdge) -> NSTextBlock.ValueType {
        _widths[NSTextBlock._key(layer, edge)]?.type ?? .absoluteValueType
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextblock/verticalalignment
    open var verticalAlignment: NSTextBlock.VerticalAlignment {
        get { _verticalAlignment }
        set { _verticalAlignment = newValue }
    }

    // MARK: Geometry

    /// The content rectangle: from `startingPoint`, inside the margin, border and padding on
    /// each side, `contentWidth` wide when set (clamped by the minimum and maximum widths).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextblock/rectforlayout(at:in:textcontainer:characterrange:)
    open func rectForLayout(at startingPoint: NSPoint, in rect: NSRect, textContainer: NSTextContainer, characterRange charRange: NSRange) -> NSRect {
        _layoutRect(at: startingPoint, in: rect)
    }
    /// The content rectangle grown by the padding, border and margin, and to the minimum
    /// and explicit heights.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextblock/boundsrect(forcontentrect:in:textcontainer:characterrange:)
    open func boundsRect(forContentRect contentRect: NSRect, in rect: NSRect, textContainer: NSTextContainer, characterRange charRange: NSRange) -> NSRect {
        _boundsRect(forContent: contentRect, in: rect)
    }
    /// Fills the background inside the margins and draws each edge's border.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextblock/drawbackground(withframe:in:characterrange:layoutmanager:)
    open func drawBackground(withFrame frameRect: NSRect, in controlView: NSView, characterRange charRange: NSRange, layoutManager: NSLayoutManager) {
        _drawBackground(frame: frameRect, relativeTo: frameRect.width)
    }

    internal static let _edges: [NSRectEdge] = [.minX, .minY, .maxX, .maxY]
    internal static func _key(_ layer: NSTextBlock.Layer, _ edge: NSRectEdge) -> Int { (layer.rawValue + 1) * 8 + Int(edge.rawValue) }

    /// A width resolved against `basis` (percentages are of the containing width).
    internal func _resolved(_ layer: NSTextBlock.Layer, _ edge: NSRectEdge, basis: CGFloat) -> CGFloat {
        guard let w = _widths[NSTextBlock._key(layer, edge)] else { return 0 }
        return w.type == .percentageValueType ? basis * w.value / 100 : w.value
    }
    internal func _resolvedValue(_ d: NSTextBlock.Dimension, basis: CGFloat) -> CGFloat? {
        guard let v = _values[d.rawValue], v.value > 0 else { return nil }
        return v.type == .percentageValueType ? basis * v.value / 100 : v.value
    }
    /// Margin + border + padding on one edge.
    internal func _inset(_ edge: NSRectEdge, basis: CGFloat) -> CGFloat {
        _resolved(.margin, edge, basis: basis) + _resolved(.border, edge, basis: basis) + _resolved(.padding, edge, basis: basis)
    }

    internal func _layoutRect(at p: NSPoint, in rect: NSRect) -> NSRect {
        let basis = rect.width
        let left = _inset(.minX, basis: basis), right = _inset(.maxX, basis: basis), top = _inset(.minY, basis: basis)
        var width = max(0, rect.maxX - p.x - left - right)
        if let w = _resolvedValue(.width, basis: basis) { width = w }
        if let lo = _resolvedValue(.minimumWidth, basis: basis) { width = max(width, lo) }
        if let hi = _resolvedValue(.maximumWidth, basis: basis) { width = min(width, hi) }
        let h = max(0, rect.maxY - p.y - top - _inset(.maxY, basis: basis))
        return NSRect(x: p.x + left, y: p.y + top, width: width, height: h)
    }

    internal func _boundsRect(forContent c: NSRect, in rect: NSRect) -> NSRect {
        let basis = rect.width
        var height = c.height
        if let h = _resolvedValue(.height, basis: basis) { height = h }
        if let lo = _resolvedValue(.minimumHeight, basis: basis) { height = max(height, lo) }
        if let hi = _resolvedValue(.maximumHeight, basis: basis) { height = min(height, hi) }
        let left = _inset(.minX, basis: basis), right = _inset(.maxX, basis: basis)
        let top = _inset(.minY, basis: basis), bottom = _inset(.maxY, basis: basis)
        return NSRect(x: c.minX - left, y: c.minY - top, width: c.width + left + right, height: height + top + bottom)
    }

    /// Background inside the margin, then the border bands (flipped coordinates).
    internal func _drawBackground(frame f: NSRect, relativeTo basis: CGFloat) {
        MainActor.assumeIsolated {
            let mL = _resolved(.margin, .minX, basis: basis), mR = _resolved(.margin, .maxX, basis: basis)
            let mT = _resolved(.margin, .minY, basis: basis), mB = _resolved(.margin, .maxY, basis: basis)
            let box = NSRect(x: f.minX + mL, y: f.minY + mT, width: max(0, f.width - mL - mR), height: max(0, f.height - mT - mB))
            if let bg = _backgroundColor { bg.setFill(); NSBezierPath.fill(box) }
            let bL = _resolved(.border, .minX, basis: basis), bR = _resolved(.border, .maxX, basis: basis)
            let bT = _resolved(.border, .minY, basis: basis), bB = _resolved(.border, .maxY, basis: basis)
            func band(_ edge: NSRectEdge, _ r: NSRect) {
                guard r.width > 0, r.height > 0 else { return }
                (borderColor(for: edge) ?? NSColor.black).setFill()
                NSBezierPath.fill(r)
            }
            band(.minY, NSRect(x: box.minX, y: box.minY, width: box.width, height: bT))
            band(.maxY, NSRect(x: box.minX, y: box.maxY - bB, width: box.width, height: bB))
            band(.minX, NSRect(x: box.minX, y: box.minY, width: bL, height: box.height))
            band(.maxX, NSRect(x: box.maxX - bR, y: box.minY, width: bR, height: box.height))
        }
    }

    // MARK: Coding and copying

    class public var supportsSecureCoding: Bool { true }
    open func encode(with coder: NSCoder) {
        coder.encode(Int(_verticalAlignment.rawValue), forKey: "NSVerticalAlignment")
        coder.encode(_backgroundColor, forKey: "NSBackgroundColor")
    }
    public required init?(coder: NSCoder) {
        _verticalAlignment = NSTextBlock.VerticalAlignment(rawValue: coder.decodeInteger(forKey: "NSVerticalAlignment")) ?? .topAlignment
        _backgroundColor = coder.decodeObject(forKey: "NSBackgroundColor") as? NSColor
        super.init()
    }
    open func copy(with zone: NSZone? = nil) -> Any {
        let c = NSTextBlock()
        _copyValues(into: c)
        return c
    }
}
