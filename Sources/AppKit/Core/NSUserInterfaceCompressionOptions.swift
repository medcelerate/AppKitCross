// NSUserInterfaceCompressionOptions (hand-written; seeded from the generated stub, see tools/apigen)
//
// A set of option identifiers (macOS 15: the standard options are named
// NSUserInterfaceCompressionOption{HideImages,HideText,ReduceMetrics,BreakEqualWidths}).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserinterfacecompressionoptions
@available(macOS 10.13, *)
open class NSUserInterfaceCompressionOptions: NSObject, NSCopying, NSCoding {
    internal let _identifiers: Set<String>
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserinterfacecompressionoptions/init()
    public override init() { _identifiers = []; super.init() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserinterfacecompressionoptions/init(coder:)
    public required init(coder: NSCoder) {
        let list = coder._decodeObjectIfPresent(forKey: "NSIdentifiers") as? [String] ?? []
        _identifiers = Set(list)
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserinterfacecompressionoptions/init(identifier:)
    public init(identifier: String) { _identifiers = [identifier]; super.init() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserinterfacecompressionoptions/init(options:)
    public init(options: Set<NSUserInterfaceCompressionOptions>) {
        _identifiers = options.reduce(into: Set<String>()) { $0.formUnion($1._identifiers) }
        super.init()
    }
    private init(_ ids: Set<String>) { _identifiers = ids; super.init() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserinterfacecompressionoptions/breakequalwidths
    class public var breakEqualWidths: NSUserInterfaceCompressionOptions { NSUserInterfaceCompressionOptions(identifier: "NSUserInterfaceCompressionOptionBreakEqualWidths") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserinterfacecompressionoptions/contains(_:)
    open func contains(_ options: NSUserInterfaceCompressionOptions) -> Bool { options._identifiers.isSubset(of: _identifiers) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserinterfacecompressionoptions/hideimages
    class public var hideImages: NSUserInterfaceCompressionOptions { NSUserInterfaceCompressionOptions(identifier: "NSUserInterfaceCompressionOptionHideImages") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserinterfacecompressionoptions/hidetext
    class public var hideText: NSUserInterfaceCompressionOptions { NSUserInterfaceCompressionOptions(identifier: "NSUserInterfaceCompressionOptionHideText") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserinterfacecompressionoptions/intersects(_:)
    open func intersects(_ options: NSUserInterfaceCompressionOptions) -> Bool { !_identifiers.isDisjoint(with: options._identifiers) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserinterfacecompressionoptions/isempty
    open var isEmpty: Bool { _identifiers.isEmpty }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserinterfacecompressionoptions/reducemetrics
    class public var reduceMetrics: NSUserInterfaceCompressionOptions { NSUserInterfaceCompressionOptions(identifier: "NSUserInterfaceCompressionOptionReduceMetrics") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserinterfacecompressionoptions/standardoptions
    class public var standardOptions: NSUserInterfaceCompressionOptions {
        NSUserInterfaceCompressionOptions(["NSUserInterfaceCompressionOptionHideImages", "NSUserInterfaceCompressionOptionHideText",
                                           "NSUserInterfaceCompressionOptionReduceMetrics", "NSUserInterfaceCompressionOptionBreakEqualWidths"])
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserinterfacecompressionoptions/subtracting(_:)
    open func subtracting(_ options: NSUserInterfaceCompressionOptions) -> NSUserInterfaceCompressionOptions { NSUserInterfaceCompressionOptions(_identifiers.subtracting(options._identifiers)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserinterfacecompressionoptions/union(_:)
    open func union(_ options: NSUserInterfaceCompressionOptions) -> NSUserInterfaceCompressionOptions { NSUserInterfaceCompressionOptions(_identifiers.union(options._identifiers)) }
    open override func isEqual(_ object: Any?) -> Bool { (object as? NSUserInterfaceCompressionOptions)?._identifiers == _identifiers }
    open override var hash: Int { _identifiers.hashValue }
    open override var description: String { "<NSUserInterfaceCompressionOptions> identifiers = \(_identifiers.sorted())" }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any { self }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { coder.encode(_identifiers.sorted(), forKey: "NSIdentifiers") }
}
