// NSPasteboard (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard
open class NSPasteboard: NSObject {
    // MARK: Storage
    private let _name: NSPasteboard.Name
    private var _items: [NSPasteboardItem] = []
    private var _localChangeCount = 0
    private var _lastSyncedPlatformCount = -1
    nonisolated(unsafe) private static var _named: [NSPasteboard.Name: NSPasteboard] = [:]
    nonisolated(unsafe) private static var _uniqueCounter = 0

    private var _isSystem: Bool { _name == .general }

    /// Pulls the system clipboard into `_items` when another process changed it.
    private func _syncFromPlatform() {
        guard _isSystem else { return }
        MainActor.assumeIsolated {
            let pb = Platform.backend.systemPasteboard
            let count = pb.changeCount
            guard count != _lastSyncedPlatformCount else { return }
            _lastSyncedPlatformCount = count
            let item = NSPasteboardItem()
            for e in pb.read() { item._entries[NSPasteboard.PasteboardType(e.type)] = e.data }
            _items = item._entries.isEmpty ? [] : [item]
            _localChangeCount += 1
        }
    }

    private func _pushToPlatform() {
        guard _isSystem else { return }
        MainActor.assumeIsolated {
            var entries: [PlatformPasteboardEntry] = []
            for item in _items { for t in item.types { if let d = item.data(forType: t) { entries.append(PlatformPasteboardEntry(type: t.rawValue, data: d)) } } }
            let pb = Platform.backend.systemPasteboard
            pb.write(entries)
            _lastSyncedPlatformCount = pb.changeCount
        }
    }

    private var _firstItem: NSPasteboardItem {
        if let i = _items.first { return i }
        let i = NSPasteboardItem()
        _items = [i]
        return i
    }

    open override var description: String { "<NSPasteboard '\(_name.rawValue)' \(_items.count) items>" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/init(byfilteringdata:oftype:)
    public convenience init(byFilteringData data: Data, ofType type: NSPasteboard.PasteboardType) {
        self.init(name: NSPasteboard.Name("filter-\(NSPasteboard._uniqueCounter)"))
        NSPasteboard._uniqueCounter += 1
        _ = setData(data, forType: type)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/init(byfilteringfile:)
    public convenience init(byFilteringFile filename: String) {
        self.init(name: NSPasteboard.Name("filter-\(NSPasteboard._uniqueCounter)"))
        NSPasteboard._uniqueCounter += 1
        if let d = try? Data(contentsOf: URL(fileURLWithPath: filename)) { _ = setData(d, forType: .fileContents) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/init(byfilteringtypesinpasteboard:)
    public convenience init(byFilteringTypesInPasteboard pboard: NSPasteboard) {
        self.init(name: NSPasteboard.Name("filter-\(NSPasteboard._uniqueCounter)"))
        NSPasteboard._uniqueCounter += 1
        _items = pboard.pasteboardItems ?? []
    }
    // DUPLICATE: public init(byFilteringTypesInPasteboard pboard: NSPasteboard)
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/init(name:)
    public init(name: NSPasteboard.Name) {
        _name = name
        super.init()
    }
    /// The current pasteboard access behavior. The user can customize this behavior per-app in System Settings for any app that has triggered a pasteboard access alert in the past.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior
    @available(macOS 15.4, *)
    open var accessBehavior: NSPasteboard.AccessBehavior {
        get { .default }
        set { }
    }
    // DUPLICATE: open var accessBehavior: NSPasteboard.AccessBehavior
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/addtypes(_:owner:)
    open func addTypes(_ newTypes: [NSPasteboard.PasteboardType], owner newOwner: Any?) -> Int {
        let item = _firstItem
        for t in newTypes where item._entries[t] == nil { item._entries[t] = Data() }
        _localChangeCount += 1
        return _localChangeCount
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/availabletype(from:)
    open func availableType(from types: [NSPasteboard.PasteboardType]) -> NSPasteboard.PasteboardType? { let mine = self.types ?? []; return types.first { mine.contains($0) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/canreaditem(withdataconformingtotypes:)
    open func canReadItem(withDataConformingToTypes types: [String]) -> Bool { let mine = (self.types ?? []).map { $0.rawValue }; return types.contains { mine.contains($0) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/canreadobject(forclasses:options:)
    open func canReadObject(forClasses classArray: [AnyClass], options: [NSPasteboard.ReadingOptionKey : Any]? = nil) -> Bool { readObjects(forClasses: classArray, options: options) != nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/changecount
    open var changeCount: Int { _syncFromPlatform(); return _localChangeCount }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/clearcontents()
    open func clearContents() -> Int {
        _items.removeAll()
        _localChangeCount += 1
        _pushToPlatform()
        return _localChangeCount
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/data(fortype:)
    open func data(forType dataType: NSPasteboard.PasteboardType) -> Data? { _syncFromPlatform(); for i in _items { if let d = i.data(forType: dataType) { return d } }; return nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/declaretypes(_:owner:)
    open func declareTypes(_ newTypes: [NSPasteboard.PasteboardType], owner newOwner: Any?) -> Int {
        _ = clearContents()
        return addTypes(newTypes, owner: newOwner)
    }
    /// Determines available metadata from the specified metadata types for the first pasteboard item, without notifying the person using the app.
    /// 
    /// This method only gives access to limited types of metadata and doesn’t allow the app to access the contents. As a result, the system doesn’t notify the person using the app about reading the contents of the pasteboard.
    /// 
    /// For details about the metadata returned for each type, see ``NSPasteboard/DetectedMetadata``.
    /// 
    /// The following example shows how to use this method to find the content type of a file reference in the first item on the pasteboard:
    /// 
    /// ```swift
    /// do {
    ///     let metadataResults = try await NSPasteboard.general.detectedMetadata(for:     /// [\.contentType])
    ///     if let contentType = metadataResults.contentType {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/detectedmetadata(for:)
    @available(macOS 15.4, *)
    open func detectedMetadata(for keyPaths: Set<PartialKeyPath<NSPasteboard.DetectedMetadata>>) async throws -> NSPasteboard.DetectedMetadata { unimplemented() }
    /// Determines whether the first pasteboard item matches the specified patterns, without notifying the person using the app.
    /// 
    /// This method only gives an indication of whether the first pasteboard item matches a particular pattern, and doesn’t allow the app to access the item's contents. As a result, the system doesn’t notify the person using the app about reading the contents of the pasteboard.
    /// 
    /// The following example shows how to use this method to find calendar events in the first pasteboard item:
    /// 
    /// ```swift
    /// do {
    ///     let patternResults = try await NSPasteboard.general.detectedPatterns(for: [\.calendarEvents])
    ///     if patternResults.contains(\.calendarEvents) {
    ///         print("Calendar event(s) detected.")
    ///     } else {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/detectedpatterns(for:)
    @available(macOS 15.4, *)
    open func detectedPatterns(for keyPaths: Set<PartialKeyPath<NSPasteboard.DetectedValues>>) async throws -> Set<PartialKeyPath<NSPasteboard.DetectedValues>> { unimplemented() }
    /// Determines whether the first pasteboard item matches the specified patterns, reading the contents if it finds a match.
    /// 
    /// For details about the types returned for each pattern, see ``NSPasteboard/DetectedValues``.
    /// 
    /// The following example shows how to use this method to find links in the first pasteboard item:
    /// 
    /// ```swift
    /// do {
    ///     let valueResults = try await NSPasteboard.general.detectedValues(for: [\.links])
    ///     let links = valueResults.links
    ///     guard !links.isEmpty else {
    ///         print ("No links found in item.")
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/detectedvalues(for:)
    @available(macOS 15.4, *)
    open func detectedValues(for keyPaths: Set<PartialKeyPath<NSPasteboard.DetectedValues>>) async throws -> NSPasteboard.DetectedValues { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/general
    class public var general: NSPasteboard {
        if let p = _named[.general] { return p }
        let p = NSPasteboard(name: .general)
        _named[.general] = p
        return p
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/index(of:)
    open func index(of pasteboardItem: NSPasteboardItem) -> Int { _items.firstIndex { $0 === pasteboardItem } ?? NSNotFound }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/name
    open var name: NSPasteboard.Name { _name }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/pasteboarditems
    open var pasteboardItems: [NSPasteboardItem]? { _syncFromPlatform(); return _items }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/preparefornewcontents(with:)
    @available(macOS 10.12, *)
    open func prepareForNewContents(with options: NSPasteboard.ContentsOptions = []) -> Int { clearContents() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/propertylist(fortype:)
    open func propertyList(forType dataType: NSPasteboard.PasteboardType) -> Any? { data(forType: dataType).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/readfilecontentstype(_:tofile:)
    open func readFileContentsType(_ type: NSPasteboard.PasteboardType?, toFile filename: String) -> String? {
        guard let d = data(forType: type ?? .fileContents), (try? d.write(to: URL(fileURLWithPath: filename))) != nil else { return nil }
        return filename
    }
    // SKIPPED (Foundation.FileWrapper not in corelibs): func readFileWrapper() -> FileWrapper?
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/readobjects(forclasses:options:)
    open func readObjects(forClasses classArray: [AnyClass], options: [NSPasteboard.ReadingOptionKey : Any]? = nil) -> [Any]? {
        _syncFromPlatform()
        var result: [Any] = []
        for cls in classArray {
            if cls == NSString.self || cls == NSPasteboardItem.self {
                if cls == NSPasteboardItem.self { result += _items as [Any] } else if let s = string(forType: .string) { result.append(s as NSString) }
            } else if cls == NSImage.self {
                for t in [NSPasteboard.PasteboardType.png, .tiff] { if let d = data(forType: t), let img = NSImage(data: d) { result.append(img); break } }
            }
        }
        return result.isEmpty ? nil : result
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/releaseglobally()
    open func releaseGlobally() { NSPasteboard._named[_name] = nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/setdata(_:fortype:)
    open func setData(_ data: Data?, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        _firstItem._entries[dataType] = data ?? Data()
        _localChangeCount += 1
        _pushToPlatform()
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/setpropertylist(_:fortype:)
    open func setPropertyList(_ plist: Any, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        guard let d = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return false }
        return setData(d, forType: dataType)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/setstring(_:fortype:)
    open func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool { setData(Data(string.utf8), forType: dataType) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/string(fortype:)
    open func string(forType dataType: NSPasteboard.PasteboardType) -> String? { data(forType: dataType).map { String(decoding: $0, as: UTF8.self) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/types
    open var types: [NSPasteboard.PasteboardType]? { _syncFromPlatform(); var seen: [NSPasteboard.PasteboardType] = []; for i in _items { for t in i.types where !seen.contains(t) { seen.append(t) } }; return seen }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/types(filterableto:)
    public class func types(filterableTo type: NSPasteboard.PasteboardType) -> [NSPasteboard.PasteboardType] { [type] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/withuniquename()
    public class func withUniqueName() -> NSPasteboard {
        _uniqueCounter += 1
        return NSPasteboard(name: NSPasteboard.Name("unique-\(_uniqueCounter)"))
    }
    // SKIPPED (Foundation.FileWrapper not in corelibs): func write(_ wrapper: FileWrapper) -> Bool
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/writefilecontents(_:)
    open func writeFileContents(_ filename: String) -> Bool {
        guard let d = try? Data(contentsOf: URL(fileURLWithPath: filename)) else { return false }
        return setData(d, forType: .fileContents)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboard/writeobjects(_:)
    open func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool {
        MainActor.assumeIsolated {
            for o in objects {
                if let item = o as? NSPasteboardItem { _items.append(item); continue }
                if let s = o as? NSString { _ = setString(s as String, forType: .string); continue }
                let item = NSPasteboardItem()
                for t in o.writableTypes(for: self) {
                    if let v = o.pasteboardPropertyList(forType: t) {
                        if let d = v as? Data { item._entries[t] = d } else if let s = v as? String { item._entries[t] = Data(s.utf8) } else { _ = item.setPropertyList(v, forType: t) }
                    }
                }
                _items.append(item)
            }
            _localChangeCount += 1
            _pushToPlatform()
            return true
        }
    }
}
