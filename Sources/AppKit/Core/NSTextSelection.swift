// NSTextSelection (hand-written; seeded from the generated stub, see tools/apigen)
// A TextKit 2 selection (ADR-0040): ranges with an affinity and a granularity, the x a
// vertical movement keeps (`anchorPositionOffset`) and, internally, the location an
// extension grows from and the unit (word, paragraph) a double- or triple-click selected.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselection
@available(macOS 12.0, *)
open class NSTextSelection: NSObject, NSSecureCoding, NSCoding {
    private let _textRanges: [NSTextRange]
    private let _affinity: NSTextSelection.Affinity
    private let _granularity: NSTextSelection.Granularity
    private var _anchorPositionOffset: CGFloat = 0
    private var _isLogical = true
    private var _secondarySelectionLocation: (any NSTextLocation)?
    private var _typingAttributes: [NSAttributedString.Key: Any] = [:]
    /// The fixed end of a selection being extended (nil: the far end from the movement).
    internal var _anchor: (any NSTextLocation)?
    /// The unit a click selected, kept while a drag or shift-click extends by that unit.
    internal var _anchorRange: NSTextRange?
    /// Whether `anchorPositionOffset` holds the x of an ongoing vertical movement.
    internal var _hasAnchorPosition = false
    internal var _isTransient = false

    /// A caret at `location`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselection/init(_:affinity:)
    public convenience init(_ location: any NSTextLocation, affinity: NSTextSelection.Affinity) {
        self.init([NSTextRange(location: location)], affinity: affinity, granularity: .character)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselection/init(_:affinity:granularity:)
    public init(_ textRanges: [NSTextRange], affinity: NSTextSelection.Affinity, granularity: NSTextSelection.Granularity) {
        _textRanges = textRanges.sorted { $0.location.compare($1.location) == .orderedAscending }
        _affinity = affinity
        _granularity = granularity
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselection/init(range:affinity:granularity:)
    public convenience init(range: NSTextRange, affinity: NSTextSelection.Affinity, granularity: NSTextSelection.Granularity) {
        self.init([range], affinity: affinity, granularity: granularity)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselection/init(coder:)
    public required init?(coder: NSCoder) {
        _textRanges = []
        _affinity = .downstream
        _granularity = .character
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselection/encode(with:)
    open func encode(with coder: NSCoder) {}
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselection/supportssecurecoding
    class public var supportsSecureCoding: Bool { true }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselection/textranges
    open var textRanges: [NSTextRange] { _textRanges }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselection/affinity-swift.property
    open var affinity: NSTextSelection.Affinity { _affinity }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselection/granularity-swift.property
    open var granularity: NSTextSelection.Granularity { _granularity }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselection/anchorpositionoffset
    open var anchorPositionOffset: CGFloat {
        get { _anchorPositionOffset }
        set { _anchorPositionOffset = newValue; _hasAnchorPosition = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselection/islogical
    open var isLogical: Bool {
        get { _isLogical }
        set { _isLogical = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselection/istransient
    open var isTransient: Bool { _isTransient }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselection/secondaryselectionlocation
    open var secondarySelectionLocation: (any NSTextLocation)? {
        get { _secondarySelectionLocation }
        set { _secondarySelectionLocation = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselection/typingattributes
    open var typingAttributes: [NSAttributedString.Key : Any] {
        get { _typingAttributes }
        set { _typingAttributes = newValue }
    }
    /// A selection like this one (affinity, granularity, typing attributes) over `textRanges`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselection/textselection(_:)
    open func textSelection(_ textRanges: [NSTextRange]) -> NSTextSelection {
        let s = NSTextSelection(textRanges, affinity: _affinity, granularity: _granularity)
        s._typingAttributes = _typingAttributes
        s._isLogical = _isLogical
        return s
    }
    open override var description: String { "NSTextSelection(\(_textRanges), \(_affinity), \(_granularity))" }
}

@available(macOS 12.0, *)
extension NSTextSelection {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselection/affinity-swift.enum
    @available(macOS 12.0, *)
    public enum Affinity: Int, Sendable, Equatable, Hashable {
        case downstream = 1
        case upstream = 0
    }
}

@available(macOS 12.0, *)
extension NSTextSelection {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextselection/granularity-swift.enum
    @available(macOS 12.0, *)
    public enum Granularity: Int, Sendable, Equatable, Hashable {
        case character = 0
        case line = 3
        case paragraph = 2
        case sentence = 4
        case word = 1
    }
}
