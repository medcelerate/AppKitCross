// NSBindingSelectionMarker (hand-written; seeded from the generated stub, see tools/apigen)
//
// The three markers a controller's selection proxy answers instead of a value, and the
// per-class default placeholders bound views show for them (ADR-0032).

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbindingselectionmarker
@available(macOS 10.14, *)
open class NSBindingSelectionMarker: NSObject, NSCopying {
    nonisolated(unsafe) private static let _multipleValues = NSBindingSelectionMarker()
    nonisolated(unsafe) private static let _noSelection = NSBindingSelectionMarker()
    nonisolated(unsafe) private static let _notApplicable = NSBindingSelectionMarker()

    private struct PlaceholderKey: Hashable {
        let marker: ObjectIdentifier?
        let objectClass: ObjectIdentifier
        let binding: NSBindingName
    }
    nonisolated(unsafe) private static var _placeholders: [PlaceholderKey: Any] = [:]

    private override init() { super.init() }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbindingselectionmarker/defaultplaceholder(for:on:withbinding:)
    @available(macOS 10.15, *)
    public class func defaultPlaceholder(for marker: NSBindingSelectionMarker?, on objectClass: AnyClass, withBinding binding: NSBindingName) -> Any? {
        var cls: AnyClass? = objectClass
        while let c = cls {
            let key = PlaceholderKey(marker: marker.map { ObjectIdentifier($0) }, objectClass: ObjectIdentifier(c), binding: binding)
            if let p = _placeholders[key] { return p }
            cls = _getSuperclass(c)
        }
        return nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbindingselectionmarker/multiplevalues
    class public var multipleValues: NSBindingSelectionMarker { _multipleValues }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbindingselectionmarker/noselection
    class public var noSelection: NSBindingSelectionMarker { _noSelection }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbindingselectionmarker/notapplicable
    class public var notApplicable: NSBindingSelectionMarker { _notApplicable }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbindingselectionmarker/setdefaultplaceholder(_:for:on:withbinding:)
    @available(macOS 10.15, *)
    public class func setDefaultPlaceholder(_ placeholder: Any?, for marker: NSBindingSelectionMarker?, on objectClass: AnyClass, withBinding binding: NSBindingName) {
        let key = PlaceholderKey(marker: marker.map { ObjectIdentifier($0) }, objectClass: ObjectIdentifier(objectClass), binding: binding)
        _placeholders[key] = placeholder
    }
    // Requirement of NSCopying
    /// The markers are singletons; a copy is the marker itself.
    open func copy(with zone: NSZone? = nil) -> Any { self }

    open override var description: String {
        if self === NSBindingSelectionMarker._multipleValues { return "<NSMultipleValuesMarker>" }
        if self === NSBindingSelectionMarker._noSelection { return "<NSNoSelectionMarker>" }
        return "<NSNotApplicableMarker>"
    }
}
