// NSDataAsset (hand-written; seeded from the generated stub, see tools/apigen)
//
// A data set of an asset catalog (ADR-0045): `<name>.dataset/Contents.json` names the file and
// its UTI. The catalogs are the uncompiled `*.xcassets` folders SwiftPM copies off macOS, looked
// up in the bundle's resources (for the main bundle: Resources/, the executable target's SwiftPM
// bundle and the executable's folder).

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdataasset
@available(macOS 10.11, *)
open class NSDataAsset: NSObject, NSCopying {
    private let _name: NSDataAsset.Name
    private let _data: Data
    private let _typeIdentifier: String

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdataasset/init(name:)
    public convenience init?(name: NSDataAsset.Name) { self.init(name: name, bundle: Bundle.main) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdataasset/init(name:bundle:)
    /// Nil when no catalog in the bundle has a data set of that name.
    public init?(name: NSDataAsset.Name, bundle: Bundle) {
        _AppBundle.installMainBundle()
        guard let found = _NSAssetCatalog.data(named: name, roots: _AppBundle.forBundle(bundle).layout.resourceRoots) else { return nil }
        _name = name
        _data = found.data
        _typeIdentifier = found.typeIdentifier
        super.init()
    }
    private init(name: NSDataAsset.Name, data: Data, typeIdentifier: String) {
        _name = name; _data = data; _typeIdentifier = typeIdentifier
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdataasset/data
    open var data: Data { _data }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdataasset/name
    open var name: NSDataAsset.Name { _name }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdataasset/typeidentifier
    open var typeIdentifier: String { _typeIdentifier }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any { NSDataAsset(name: _name, data: _data, typeIdentifier: _typeIdentifier) }
}

@available(macOS 10.11, *)
extension NSDataAsset {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdataasset/name
    @available(macOS 10.11, *)
    public typealias Name = String
}
