// NSTextRange (hand-written; seeded from the generated stub, see tools/apigen)
// A span between two NSTextLocations (ADR-0040). Every operation goes through
// `compare(_:)`, so ranges work with any location type; the port's own locations are
// `_NSTextIndexLocation`s (UTF-16 offsets into the document).

import Foundation

/// A location in a document managed by the port's content storage: a UTF-16 offset.
internal final class _NSTextIndexLocation: NSObject, NSTextLocation {
    let offset: Int
    init(_ offset: Int) { self.offset = offset }

    func compare(_ location: any NSTextLocation) -> ComparisonResult {
        if let other = location as? _NSTextIndexLocation {
            return offset < other.offset ? .orderedAscending : offset > other.offset ? .orderedDescending : .orderedSame
        }
        // A foreign location knows how it relates to ours.
        switch location.compare(self) {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }

    override func isEqual(_ object: Any?) -> Bool { (object as? _NSTextIndexLocation)?.offset == offset }
    override var hash: Int { offset.hashValue }
    override var description: String { "\(offset)" }
}

/// The offset of a location the port made, if it is one.
internal func _offset(of location: any NSTextLocation) -> Int? { (location as? _NSTextIndexLocation)?.offset }

internal extension NSTextRange {
    /// A range over UTF-16 offsets.
    static func _make(_ range: NSRange) -> NSTextRange {
        NSTextRange(location: _NSTextIndexLocation(range.location), end: _NSTextIndexLocation(range.location + range.length))!
    }
    /// The offsets of a range of the port's locations.
    var _nsRange: NSRange? {
        guard let a = _offset(of: location), let b = _offset(of: endLocation) else { return nil }
        return NSRange(location: a, length: max(0, b - a))
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextrange
@available(macOS 12.0, *)
open class NSTextRange: NSObject {
    private let _location: any NSTextLocation
    private let _end: any NSTextLocation

    /// An empty range at `location`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextrange/init(location:)
    public convenience init(location: any NSTextLocation) { self.init(location: location, end: nil)! }
    /// Fails when `endLocation` precedes `location`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextrange/init(location:end:)
    public init?(location: any NSTextLocation, end endLocation: (any NSTextLocation)?) {
        let end = endLocation ?? location
        guard location.compare(end) != .orderedDescending else { return nil }
        _location = location
        _end = end
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextrange/location
    open var location: any NSTextLocation { _location }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextrange/endlocation
    open var endLocation: any NSTextLocation { _end }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextrange/isempty
    open var isEmpty: Bool { _location.compare(_end) == .orderedSame }
    /// Whether `location` is in the range (the end is not, except in an empty range at it).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextrange/contains(_:)
    open func contains(_ location: any NSTextLocation) -> Bool {
        let afterStart = _location.compare(location) != .orderedDescending
        if isEmpty { return afterStart && _end.compare(location) == .orderedSame }
        return afterStart && location.compare(_end) == .orderedAscending
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextrange/contains(_:)
    open func contains(_ textRange: NSTextRange) -> Bool {
        _location.compare(textRange.location) != .orderedDescending && textRange.endLocation.compare(_end) != .orderedDescending
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextrange/intersects(_:)
    open func intersects(_ textRange: NSTextRange) -> Bool {
        if isEmpty || textRange.isEmpty {
            // An empty range intersects a range it lies within (or at the end of).
            let (empty, other) = isEmpty ? (self, textRange) : (textRange, self)
            return other.location.compare(empty.location) != .orderedDescending && empty.location.compare(other.endLocation) != .orderedDescending
        }
        return _location.compare(textRange.endLocation) == .orderedAscending && textRange.location.compare(_end) == .orderedAscending
    }
    /// The overlap, or nil when the ranges do not intersect. Builds a plain NSTextRange.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextrange/intersection(_:)
    open func intersection(_ textRange: NSTextRange) -> Self? {
        guard intersects(textRange) else { return nil }
        let start = _location.compare(textRange.location) == .orderedDescending ? _location : textRange.location
        let end = _end.compare(textRange.endLocation) == .orderedAscending ? _end : textRange.endLocation
        return NSTextRange(location: start, end: end).map { $0 as! Self }
    }
    /// The smallest range covering both. Builds a plain NSTextRange.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextrange/union(_:)
    open func union(_ textRange: NSTextRange) -> Self {
        let start = _location.compare(textRange.location) == .orderedAscending ? _location : textRange.location
        let end = _end.compare(textRange.endLocation) == .orderedDescending ? _end : textRange.endLocation
        return NSTextRange(location: start, end: end)! as! Self
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextrange/isequal(to:)
    open func isEqual(to textRange: NSTextRange) -> Bool {
        _location.compare(textRange.location) == .orderedSame && _end.compare(textRange.endLocation) == .orderedSame
    }
    open override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? NSTextRange else { return false }
        return isEqual(to: other)
    }
    open override var hash: Int { (_offset(of: _location) ?? 0) &* 31 &+ (_offset(of: _end) ?? 0) }
    open override var description: String { "\(type(of: self))(\(_location)...\(_end))" }
}
