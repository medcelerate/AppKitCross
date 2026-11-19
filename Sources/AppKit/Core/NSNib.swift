// NSNib (hand-written; seeded from the generated stub, see tools/apigen)
//
// The port builds its interfaces in code (ARCHITECTURE: nibs and storyboards are out of scope),
// so a nib is found but never decoded (ADR-0045): `init(nibNamed:bundle:)` looks up
// `<name>.nib` (a file or a folder) or `<name>.xib` in the bundle's resources, the main
// bundle's search path included, and answers nil when there is none, as macOS does;
// instantiating one stops with the reason.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsnib
open class NSNib: NSObject, NSCoding {
    /// Where the nib was found (nil for one made from data).
    internal let _url: URL?
    internal let _data: Data?

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsnib/init(nibdata:bundle:)
    public init(nibData: Data, bundle: Bundle?) {
        _url = nil
        _data = nibData
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsnib/init(nibnamed:bundle:)
    public init?(nibNamed nibName: NSNib.Name, bundle: Bundle?) {
        _AppBundle.installMainBundle()
        let app = bundle.map(_AppBundle.forBundle) ?? _AppBundle.main
        var name = nibName
        for ext in [".nib", ".xib"] where name.hasSuffix(ext) { name.removeLast(ext.count) }
        guard let url = app.url(forResource: name, withExtension: "nib") ?? app.url(forResource: name, withExtension: "xib") else { return nil }
        _url = url
        _data = nil
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsnib/instantiate(withowner:toplevelobjects:)
    open func instantiate(withOwner owner: Any?, topLevelObjects: AutoreleasingUnsafeMutablePointer<NSArray?>?) -> Bool {
        unimplemented("NSNib.instantiate — Interface Builder archives are not decoded on Windows and Linux; build the interface in code (\(_url?.lastPathComponent ?? "nib data"))")
    }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) {
        unimplemented("NSNib.encode(with:) — nib archives are not supported off macOS")
    }
    // Requirement of NSCoding
    public required init?(coder: NSCoder) {
        unimplemented("NSNib.init(coder:) — nib archives are not supported off macOS")
    }
}

extension NSNib {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsnib/name
    public typealias Name = String
}
