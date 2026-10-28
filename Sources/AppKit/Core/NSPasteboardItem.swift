// NSPasteboardItem (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboarditem
open class NSPasteboardItem: NSObject, NSPasteboardWriting, NSPasteboardReading {
    internal var _entries: [NSPasteboard.PasteboardType: Data] = [:]
    private var _providers: [NSPasteboard.PasteboardType: any NSPasteboardItemDataProvider] = [:]

    public override init() { super.init() }

    private func _resolve(_ type: NSPasteboard.PasteboardType) -> Data? {
        if let d = _entries[type] { return d }
        if let p = _providers[type] {
            MainActor.assumeIsolated { p.pasteboard(nil, item: self, provideDataForType: type) }
            _providers[type] = nil
            return _entries[type]
        }
        return nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboarditem/availabletype(from:)
    open func availableType(from types: [NSPasteboard.PasteboardType]) -> NSPasteboard.PasteboardType? { let mine = self.types; return types.first { mine.contains($0) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboarditem/data(fortype:)
    open func data(forType type: NSPasteboard.PasteboardType) -> Data? { _resolve(type) }
    /// Determines available metadata from the specified metadata types for this pasteboard item, without notifying the person using the app.
    /// 
    /// This method only gives access to limited types of metadata and doesn’t allow the app to access the item's contents. As a result, the system doesn’t notify the person using the app about reading the contents of the pasteboard.
    /// 
    /// For details about the metadata returned for each type, see ``NSPasteboard/DetectedMetadata``.
    /// 
    /// The following example shows how to iterate over each pasteboard item and, if the item is a URL that points to a file, get its content type with this method.
    /// 
    /// ```swift
    /// guard let pasteboardItems = NSPasteboard.general.pasteboardItems else { return }
    /// for (index, item) in pasteboardItems.enumerated() {
    ///     do {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboarditem/detectedmetadata(for:)
    @available(macOS 15.4, *)
    open func detectedMetadata(for keyPaths: Set<PartialKeyPath<NSPasteboardItem.DetectedMetadata>>) async throws -> NSPasteboardItem.DetectedMetadata { unimplemented() }
    /// Determines whether the pasteboard item matches the specified patterns, without notifying the person using the app.
    /// 
    /// This method only gives an indication of whether a pasteboard item matches a particular pattern and doesn’t allow the app to access the contents. As a result, the system doesn’t notify the person using the app about reading the contents of the pasteboard.
    /// 
    /// The following example shows how to use this method to find calendar events in each item on the pasteboard:
    /// 
    /// ```swift
    /// guard let pasteboardItems = NSPasteboard.general.pasteboardItems else { return }
    /// for (index, item) in pasteboardItems.enumerated() {
    ///     do {
    ///         let patternResults = try await item.detectedPatterns(for: [\.calendarEvents])
    ///         if patternResults.contains(\.calendarEvents) {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboarditem/detectedpatterns(for:)
    @available(macOS 15.4, *)
    open func detectedPatterns(for keyPaths: Set<PartialKeyPath<NSPasteboardItem.DetectedValues>>) async throws -> Set<PartialKeyPath<NSPasteboardItem.DetectedValues>> { unimplemented() }
    /// Determines whether this pasteboard item matches the specified patterns, reading the contents if it finds a match.
    /// 
    /// For details about the types returned for each pattern, see ``NSPasteboard/DetectedValues``.
    /// 
    /// The following example shows how to use this method to find links in each item on the pasteboard:
    /// 
    /// ```swift
    /// guard let pasteboardItems = NSPasteboard.general.pasteboardItems else { return }
    /// for (index, item) in pasteboardItems.enumerated() {
    ///     do {
    ///         let valueResults = try await item.detectedValues(for: [\.links])
    ///         let links = valueResults.links
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboarditem/detectedvalues(for:)
    @available(macOS 15.4, *)
    open func detectedValues(for keyPaths: Set<PartialKeyPath<NSPasteboardItem.DetectedValues>>) async throws -> NSPasteboardItem.DetectedValues { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboarditem/propertylist(fortype:)
    open func propertyList(forType type: NSPasteboard.PasteboardType) -> Any? { _resolve(type).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboarditem/setdata(_:fortype:)
    open func setData(_ data: Data, forType type: NSPasteboard.PasteboardType) -> Bool { _entries[type] = data; return true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboarditem/setdataprovider(_:fortypes:)
    open func setDataProvider(_ dataProvider: any NSPasteboardItemDataProvider, forTypes types: [NSPasteboard.PasteboardType]) -> Bool { for t in types { _providers[t] = dataProvider }; return true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboarditem/setpropertylist(_:fortype:)
    open func setPropertyList(_ propertyList: Any, forType type: NSPasteboard.PasteboardType) -> Bool {
        guard let d = try? PropertyListSerialization.data(fromPropertyList: propertyList, format: .xml, options: 0) else { return false }
        _entries[type] = d
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboarditem/setstring(_:fortype:)
    open func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool { _entries[type] = Data(string.utf8); return true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboarditem/string(fortype:)
    open func string(forType type: NSPasteboard.PasteboardType) -> String? { _resolve(type).map { String(decoding: $0, as: UTF8.self) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboarditem/types
    open var types: [NSPasteboard.PasteboardType] { Array(_entries.keys) + _providers.keys.filter { _entries[$0] == nil } }
    // Requirement of NSPasteboardReading
    public required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) { unimplemented() }
}
