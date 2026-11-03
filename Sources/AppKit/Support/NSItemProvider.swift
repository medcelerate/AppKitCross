// NSItemProvider for platforms whose Foundation lacks it (corelibs on Windows and Linux).
// Apple's Foundation provides it on macOS, where this file compiles to nothing. The API
// follows Foundation's: data representations registered per type identifier, loaded
// through completion handlers; here loading completes synchronously.

#if !canImport(Darwin)
import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/foundation/nsitemproviderwriting
public protocol NSItemProviderWriting: NSObjectProtocol {
    static var writableTypeIdentifiersForItemProvider: [String] { get }
    func loadData(withTypeIdentifier typeIdentifier: String, forItemProviderCompletionHandler completionHandler: @escaping (Data?, (any Error)?) -> Void) -> Progress?
}

/// - SeeAlso: https://developer.apple.com/documentation/foundation/nsitemproviderreading
public protocol NSItemProviderReading: NSObjectProtocol {
    static var readableTypeIdentifiersForItemProvider: [String] { get }
    static func object(withItemProviderData data: Data, typeIdentifier: String) throws -> Self
}

/// - SeeAlso: https://developer.apple.com/documentation/foundation/nsitemprovider
open class NSItemProvider: NSObject {
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsitemprovider/representationvisibility
    public enum RepresentationVisibility: Int, Sendable {
        case all = 0
        case team = 1
        case group = 2
        case ownProcess = 3
    }
    public typealias CompletionHandler = (NSSecureCoding?, (any Error)?) -> Void

    private struct Representation {
        let load: (@escaping (Data?, (any Error)?) -> Void) -> Void
    }
    private var representations: [(type: String, rep: Representation)] = []
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsitemprovider/suggestedname
    open var suggestedName: String?

    public override init() { super.init() }

    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsitemprovider/init(item:typeidentifier:)
    public convenience init(item: NSSecureCoding?, typeIdentifier: String?) {
        self.init()
        guard let typeIdentifier else { return }
        let data = NSItemProvider._data(of: item)
        registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsitemprovider/init(contentsof:)
    public convenience init?(contentsOf fileURL: URL?) {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        self.init(item: data as NSData, typeIdentifier: "public.data")
        suggestedName = fileURL.lastPathComponent
    }
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsitemprovider/init(object:)
    public convenience init(object: any NSItemProviderWriting) {
        self.init()
        registerObject(object, visibility: .all)
    }

    private static func _data(of item: NSSecureCoding?) -> Data? {
        switch item {
        case let d as Data: return d
        case let d as NSData: return d as Data
        case let s as String: return Data(s.utf8)
        case let s as NSString: return Data((s as String).utf8)
        case let u as URL: return Data(u.absoluteString.utf8)
        case let u as NSURL: return Data(u.absoluteString.utf8)
        default: return nil
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsitemprovider/registereddatarepresentation(fortypeidentifier:visibility:loadhandler:)
    open func registerDataRepresentation(forTypeIdentifier typeIdentifier: String, visibility: RepresentationVisibility, loadHandler: @escaping (@escaping (Data?, (any Error)?) -> Void) -> Progress?) {
        representations.append((typeIdentifier, Representation(load: { completion in _ = loadHandler(completion) })))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsitemprovider/registeritem(fortypeidentifier:loadhandler:)
    open func registerItem(forTypeIdentifier typeIdentifier: String, loadHandler: @escaping (CompletionHandler?, AnyClass?, [AnyHashable: Any]?) -> Void) {
        representations.append((typeIdentifier, Representation(load: { completion in
            loadHandler({ item, error in completion(NSItemProvider._data(of: item), error) }, nil, nil)
        })))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsitemprovider/registerobject(_:visibility:)
    open func registerObject(_ object: any NSItemProviderWriting, visibility: RepresentationVisibility) {
        for type in type(of: object).writableTypeIdentifiersForItemProvider {
            representations.append((type, Representation(load: { completion in
                _ = object.loadData(withTypeIdentifier: type, forItemProviderCompletionHandler: completion)
            })))
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsitemprovider/registeredtypeidentifiers
    open var registeredTypeIdentifiers: [String] { representations.map(\.type) }
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsitemprovider/hasitemconformingtotypeidentifier(_:)
    open func hasItemConformingToTypeIdentifier(_ typeIdentifier: String) -> Bool {
        representations.contains { $0.type == typeIdentifier || _NSPasteboardTypeConformance.conforms($0.type, to: typeIdentifier) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsitemprovider/loaddatarepresentation(fortypeidentifier:completionhandler:)
    @discardableResult
    open func loadDataRepresentation(forTypeIdentifier typeIdentifier: String, completionHandler: @escaping (Data?, (any Error)?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        guard let rep = representations.first(where: { $0.type == typeIdentifier || _NSPasteboardTypeConformance.conforms($0.type, to: typeIdentifier) }) else {
            completionHandler(nil, NSError(domain: NSCocoaErrorDomain, code: 260, userInfo: [NSLocalizedDescriptionKey: "No representation for \(typeIdentifier)"]))
            return progress
        }
        rep.rep.load { data, error in
            progress.completedUnitCount = 1
            completionHandler(data, error)
        }
        return progress
    }
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsitemprovider/loaditem(fortypeidentifier:options:completionhandler:)
    open func loadItem(forTypeIdentifier typeIdentifier: String, options: [AnyHashable: Any]? = nil, completionHandler: CompletionHandler? = nil) {
        loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
            completionHandler?(data.map { $0 as NSData }, error)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsitemprovider/canloadobject(ofclass:)
    open func canLoadObject(ofClass aClass: any NSItemProviderReading.Type) -> Bool {
        aClass.readableTypeIdentifiersForItemProvider.contains { hasItemConformingToTypeIdentifier($0) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsitemprovider/loadobject(ofclass:completionhandler:)
    @discardableResult
    open func loadObject(ofClass aClass: any NSItemProviderReading.Type, completionHandler: @escaping ((any NSItemProviderReading)?, (any Error)?) -> Void) -> Progress {
        guard let type = aClass.readableTypeIdentifiersForItemProvider.first(where: { hasItemConformingToTypeIdentifier($0) }) else {
            completionHandler(nil, NSError(domain: NSCocoaErrorDomain, code: 260, userInfo: nil))
            return Progress(totalUnitCount: 1)
        }
        return loadDataRepresentation(forTypeIdentifier: type) { data, error in
            guard let data else { completionHandler(nil, error); return }
            do { completionHandler(try aClass.object(withItemProviderData: data, typeIdentifier: type), nil) } catch { completionHandler(nil, error) }
        }
    }
}

extension NSString: NSItemProviderWriting, NSItemProviderReading {
    public static var writableTypeIdentifiersForItemProvider: [String] { ["public.utf8-plain-text"] }
    public func loadData(withTypeIdentifier typeIdentifier: String, forItemProviderCompletionHandler completionHandler: @escaping (Data?, (any Error)?) -> Void) -> Progress? {
        completionHandler(Data((self as String).utf8), nil)
        return nil
    }
    public static var readableTypeIdentifiersForItemProvider: [String] { ["public.utf8-plain-text", "public.plain-text", "public.text"] }
    public static func object(withItemProviderData data: Data, typeIdentifier: String) throws -> Self {
        NSString(string: String(decoding: data, as: UTF8.self)) as! Self
    }
}

extension NSData: NSItemProviderWriting, NSItemProviderReading {
    public static var writableTypeIdentifiersForItemProvider: [String] { ["public.data"] }
    public func loadData(withTypeIdentifier typeIdentifier: String, forItemProviderCompletionHandler completionHandler: @escaping (Data?, (any Error)?) -> Void) -> Progress? {
        completionHandler(self as Data, nil)
        return nil
    }
    public static var readableTypeIdentifiersForItemProvider: [String] { ["public.data"] }
    public static func object(withItemProviderData data: Data, typeIdentifier: String) throws -> Self {
        NSData(data: data) as! Self
    }
}

extension NSURL: NSItemProviderWriting, NSItemProviderReading {
    public static var writableTypeIdentifiersForItemProvider: [String] { ["public.url"] }
    public func loadData(withTypeIdentifier typeIdentifier: String, forItemProviderCompletionHandler completionHandler: @escaping (Data?, (any Error)?) -> Void) -> Progress? {
        completionHandler(Data(absoluteString.utf8), nil)
        return nil
    }
    public static var readableTypeIdentifiersForItemProvider: [String] { ["public.url", "public.file-url"] }
    public static func object(withItemProviderData data: Data, typeIdentifier: String) throws -> Self {
        guard let u = NSURL(string: String(decoding: data, as: UTF8.self)) else {
            throw NSError(domain: NSCocoaErrorDomain, code: 260, userInfo: nil)
        }
        return u as! Self
    }
}
#endif
