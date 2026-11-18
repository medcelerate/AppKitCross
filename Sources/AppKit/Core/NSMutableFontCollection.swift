// NSMutableFontCollection (hand-written; seeded from the generated stub, see tools/apigen)

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutablefontcollection
open class NSMutableFontCollection: NSFontCollection {
    internal override init(_queries: [NSFontDescriptor], exclusions: [NSFontDescriptor] = [], name: NSFontCollection.Name? = nil, visibility: NSFontCollection.Visibility = .process) {
        super.init(_queries: _queries, exclusions: exclusions, name: name, visibility: visibility)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutablefontcollection/init(descriptors:)
    public override init(descriptors queryDescriptors: [NSFontDescriptor]) { super.init(descriptors: queryDescriptors) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutablefontcollection/init(locale:)
    public init(locale: Locale) { super.init(_locale: locale) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutablefontcollection/init(name:)
    public init?(name: NSFontCollection.Name) { super.init(name: name, visibility: [.process, .user, .computer]) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutablefontcollection/init(name:visibility:)
    public override init?(name: NSFontCollection.Name, visibility: NSFontCollection.Visibility) { super.init(name: name, visibility: visibility) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutablefontcollection/addquery(for:)
    open func addQuery(for descriptors: [NSFontDescriptor]) {
        for d in descriptors where !_queryDescriptors.contains(d) { _queryDescriptors.append(d) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutablefontcollection/exclusiondescriptors
    open override var exclusionDescriptors: [NSFontDescriptor]? {
        get { super.exclusionDescriptors }
        set { _exclusionDescriptors = newValue ?? [] }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutablefontcollection/querydescriptors
    open override var queryDescriptors: [NSFontDescriptor]? {
        get { super.queryDescriptors }
        set { _queryDescriptors = newValue ?? [] }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutablefontcollection/removequery(for:)
    open func removeQuery(for descriptors: [NSFontDescriptor]) {
        _queryDescriptors.removeAll { descriptors.contains($0) }
    }
    // SKIPPED (override type NSMutableFontCollection differs from superclass NSFontCollection): class var withAllAvailableDescriptors: NSMutableFontCollection { get }
    // Required by the superclass (NSCoding).
    public required init?(coder: NSCoder) { super.init(coder: coder) }
}
