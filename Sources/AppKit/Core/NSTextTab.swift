// NSTextTab (hand-written; seeded from the generated stub, see tools/apigen)
// A tab stop of a paragraph style. The layout manager hands the stops to CoreText as
// CTTextTabs (ADR-0030); locations are measured from the line fragment's leading edge
// after its padding, the same origin as the paragraph's head indent.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(CoreText)
import CoreText
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttab
open class NSTextTab: NSObject, NSCopying, NSCoding, NSSecureCoding {
    #if !canImport(Darwin)
    /// First stored word: a non-zero CF type ID, see Support/CFBridgeLayout.swift.
    private let _cfinfo = _swiftObjectCFInfo
    #endif
    private let _alignment: NSTextAlignment
    private let _location: CGFloat
    private let _options: [NSTextTab.OptionKey: Any]

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttab/init(textalignment:location:options:)
    public init(textAlignment alignment: NSTextAlignment, location loc: CGFloat, options: [NSTextTab.OptionKey : Any] = [:]) {
        _alignment = alignment
        _location = loc
        _options = options
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttab/init(type:location:)
    public convenience init(type: NSParagraphStyle.TextTabType, location loc: CGFloat) {
        switch type {
        case .leftTabStopType: self.init(textAlignment: .left, location: loc)
        case .rightTabStopType: self.init(textAlignment: .right, location: loc)
        case .centerTabStopType: self.init(textAlignment: .center, location: loc)
        case .decimalTabStopType:
            self.init(textAlignment: .right, location: loc, options: [.columnTerminators: NSTextTab.columnTerminators(for: nil)])
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttab/alignment
    open var alignment: NSTextAlignment { _alignment }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttab/columnterminators(for:)
    @available(macOS 10.11, *)
    public class func columnTerminators(for aLocale: Locale?) -> CharacterSet {
        let separator = (aLocale ?? Locale.current).decimalSeparator ?? "."
        return CharacterSet(charactersIn: separator)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttab/location
    open var location: CGFloat { _location }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttab/options
    open var options: [NSTextTab.OptionKey : Any] { _options }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttab/tabstoptype
    open var tabStopType: NSParagraphStyle.TextTabType {
        switch _alignment {
        case .right: return _options[.columnTerminators] != nil ? .decimalTabStopType : .rightTabStopType
        case .center: return .centerTabStopType
        default: return .leftTabStopType
        }
    }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any { self }   // immutable, as in AppKit
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) {
        coder.encode(Int(_alignment.rawValue), forKey: "NSAlignment")
        coder.encode(Double(_location), forKey: "NSLocation")
    }
    // Requirement of NSCoding
    public required init?(coder: NSCoder) {
        _alignment = NSTextAlignment(rawValue: coder.decodeInteger(forKey: "NSAlignment")) ?? .left
        _location = CGFloat(coder.decodeDouble(forKey: "NSLocation"))
        _options = [:]
        super.init()
    }
    // Requirement of NSSecureCoding
    class public var supportsSecureCoding: Bool { true }

    open override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? NSTextTab else { return false }
        return o._alignment == _alignment && o._location == _location
    }
    open override var hash: Int { Int(_location * 64) ^ _alignment.rawValue }
}
