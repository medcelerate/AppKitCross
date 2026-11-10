// NSPrinter (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
//
// A printer the platform's print backend knows (Printing.swift, ADR-0022). Paper sizes
// come from a built-in table of the common names (the same names AppKit reports:
// "na-letter", "iso-a4", ...); the backends do not read per-printer paper lists yet.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprinter
open class NSPrinter: NSObject, NSCopying, NSCoding {
    private let _name: String
    private let _type: NSPrinter.TypeName
    /// Hardware margins (the paper the printer cannot reach), points. Zero for the PDF
    /// and generic printers; device backends do not report theirs yet.
    internal var _imageableInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

    /// A printer by its platform name and type.
    internal init(_name name: String, type: NSPrinter.TypeName) {
        _name = name
        _type = type
        super.init()
    }

    /// The printer AppKit falls back on when the platform has none: output goes to PDF.
    internal static let genericTypeName = NSPrinter.TypeName("Generic PDF")
    internal static let genericName = "PDF"
    internal static func _generic() -> NSPrinter { NSPrinter(_name: genericName, type: genericTypeName) }

    /// The platform's printers (`PlatformPrintBackend.printers`), default first.
    internal static func _platformPrinters() -> [PlatformPrinter] {
        MainActor.assumeIsolated { Platform.backend.printing?.printers ?? [] }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprinter/init(name:)
    public init?(name: String) {
        if name == NSPrinter.genericName {
            _name = name
            _type = NSPrinter.genericTypeName
        } else {
            guard let p = NSPrinter._platformPrinters().first(where: { $0.name == name }) else { return nil }
            _name = p.name
            _type = NSPrinter.TypeName(p.type)
        }
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprinter/init(type:)
    public init?(type: NSPrinter.TypeName) {
        if type == NSPrinter.genericTypeName {
            _name = NSPrinter.genericName
            _type = type
        } else {
            guard let p = NSPrinter._platformPrinters().first(where: { $0.type == type.rawValue }) else { return nil }
            _name = p.name
            _type = type
        }
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprinter/devicedescription
    open var deviceDescription: [NSDeviceDescriptionKey : Any] {
        [.isPrinter: true, .resolution: NSSize(width: 72, height: 72), .colorSpaceName: NSColorSpaceName.calibratedRGB.rawValue]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprinter/languagelevel
    open var languageLevel: Int { 3 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprinter/name
    open var name: String { _name }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprinter/pagesize(forpaper:)
    open func pageSize(forPaper paperName: NSPrinter.PaperName) -> NSSize {
        NSPrinter._paperSize(for: paperName) ?? .zero
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprinter/printernames
    class public var printerNames: [String] { _platformPrinters().map(\.name) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprinter/printertypes
    class public var printerTypes: [NSPrinter.TypeName] {
        var seen: [NSPrinter.TypeName] = []
        for p in _platformPrinters() where !seen.contains(NSPrinter.TypeName(p.type)) { seen.append(NSPrinter.TypeName(p.type)) }
        return seen
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprinter/type
    open var type: NSPrinter.TypeName { _type }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any { self }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) {
        coder.encode(_name, forKey: "NSName")
        coder.encode(_type.rawValue, forKey: "NSType")
    }
    // Requirement of NSCoding
    public required init?(coder: NSCoder) {
        guard let name = coder.decodeObject(forKey: "NSName") as? String else { return nil }
        _name = name
        _type = NSPrinter.TypeName((coder.decodeObject(forKey: "NSType") as? String) ?? NSPrinter.genericTypeName.rawValue)
        super.init()
    }

    open override var description: String { "NSPrinter \(_name) (\(_type.rawValue))" }
    open override func isEqual(_ object: Any?) -> Bool { (object as? NSPrinter).map { $0._name == _name } ?? false }
    open override var hash: Int { _name.hashValue }

    // MARK: Paper table

    /// The papers every printer here offers: AppKit's names, localized names and sizes in
    /// points (portrait).
    internal struct Paper { let name: NSPrinter.PaperName; let localized: String; let size: NSSize }
    internal static let papers: [Paper] = [
        Paper(name: .init("na-letter"), localized: "US Letter", size: NSSize(width: 612, height: 792)),
        Paper(name: .init("na-legal"), localized: "US Legal", size: NSSize(width: 612, height: 1008)),
        Paper(name: .init("tabloid"), localized: "Tabloid", size: NSSize(width: 792, height: 1224)),
        Paper(name: .init("executive"), localized: "Executive", size: NSSize(width: 522, height: 756)),
        Paper(name: .init("iso-a3"), localized: "A3", size: NSSize(width: 842, height: 1191)),
        Paper(name: .init("iso-a4"), localized: "A4", size: NSSize(width: 595, height: 842)),
        Paper(name: .init("iso-a5"), localized: "A5", size: NSSize(width: 420, height: 595)),
        Paper(name: .init("iso-a6"), localized: "A6", size: NSSize(width: 298, height: 420)),
        Paper(name: .init("jis-b4"), localized: "JIS B4", size: NSSize(width: 729, height: 1032)),
        Paper(name: .init("jis-b5"), localized: "JIS B5", size: NSSize(width: 516, height: 729)),
        Paper(name: .init("na-number-10-envelope"), localized: "Envelope #10", size: NSSize(width: 297, height: 684)),
        Paper(name: .init("iso-designated"), localized: "Envelope DL", size: NSSize(width: 312, height: 624)),
    ]
    internal static func _paperSize(for name: NSPrinter.PaperName) -> NSSize? { papers.first { $0.name == name }?.size }
    internal static func _paperName(for size: NSSize) -> Paper? {
        papers.first { abs($0.size.width - size.width) < 1 && abs($0.size.height - size.height) < 1 }
    }
    internal static func _localizedPaperName(_ name: NSPrinter.PaperName) -> String? { papers.first { $0.name == name }?.localized }
}

extension NSPrinter {
    public struct PaperName: RawRepresentable, Hashable, Equatable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
    }
}

extension NSPrinter {
    public enum TableStatus: Int, Sendable, Equatable, Hashable {
        case error = 2
        case notFound = 1
        case ok = 0
    }
}

extension NSPrinter {
    public struct TypeName: RawRepresentable, Hashable, Equatable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
    }
}
