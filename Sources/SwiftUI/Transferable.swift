// Transferable (CoreTransferable, which Apple's SwiftUI re-exports) and the drag-and-drop
// modifiers built on it: `draggable` and `dropDestination` over the `onDrag`/`onDrop`
// machinery, an item's representations becoming NSItemProvider data under their content
// types.
//
// A representation turns into entries: a content type with an exporter (item to data)
// and/or an importer (data to item). Drops hand items over synchronously, so an
// asynchronous exporter or importer (DataRepresentation's, an async ProxyRepresentation's)
// runs on a detached task and the caller waits for it, at most five seconds. File
// representations are not built.

import Foundation
import UniformTypeIdentifiers

// MARK: Entries

/// One content type a representation can export or import.
public struct _TransferEntry: @unchecked Sendable {
    let contentType: UTType
    let exporter: ((Any) throws -> Data)?
    let importer: ((Data) throws -> Any)?
}

enum _TransferError: Error { case timedOut, wrongItem, noRepresentation }

private final class _ResultBox<T>: @unchecked Sendable { var result: Result<T, any Error>? }

/// Runs an async transfer closure to completion from synchronous code.
func _transferAwait<T>(_ op: @escaping @Sendable () async throws -> T) throws -> T {
    let box = _ResultBox<T>()
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        do { box.result = .success(try await op()) } catch { box.result = .failure(error) }
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 5) == .success, let r = box.result else { throw _TransferError.timedOut }
    return try r.get()
}

/// A transfer closure, synchronous or not.
enum _TransferFunction<A, B>: @unchecked Sendable {
    case sync(@Sendable (A) throws -> B)
    case async(@Sendable (A) async throws -> B)
    func callAsFunction(_ a: A) throws -> B {
        switch self {
        case .sync(let f): return try f(a)
        case .async(let f):
            nonisolated(unsafe) let arg = a
            return try _transferAwait { try await f(arg) }
        }
    }
}

// MARK: Protocols

/// - SeeAlso: https://developer.apple.com/documentation/coretransferable/transferrepresentation
public protocol TransferRepresentation<Item>: Sendable {
    associatedtype Item: Transferable
    associatedtype Body: TransferRepresentation
    @TransferRepresentationBuilder<Self.Item> var body: Self.Body { get }
    /// The content types this representation exports and imports (the port's hook;
    /// composed representations answer with their body's).
    var _entries: [_TransferEntry] { get }
}

extension TransferRepresentation {
    public var _entries: [_TransferEntry] { body._entries }
}

/// - SeeAlso: https://developer.apple.com/documentation/coretransferable/transferable
@preconcurrency
public protocol Transferable: Sendable {
    associatedtype Representation: TransferRepresentation
    @TransferRepresentationBuilder<Self> static var transferRepresentation: Self.Representation { get }
}

extension Never: TransferRepresentation {
    public typealias Item = Never
    public var _entries: [_TransferEntry] { [] }
}

extension Never: Transferable {
    public typealias Representation = Never
    public static var transferRepresentation: Never { fatalError("Never has no transfer representation") }
}

extension Transferable {
    static var _entries: [_TransferEntry] { transferRepresentation._entries }

    /// - SeeAlso: https://developer.apple.com/documentation/coretransferable/transferable/exportedcontenttypes(visibility:)
    /// Every representation is visible to every process on the port.
    public static func exportedContentTypes(visibility: TransferRepresentationVisibility = .all) -> [UTType] {
        _unique(_entries.filter { $0.exporter != nil }.map(\.contentType))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/coretransferable/transferable/importedcontenttypes()
    public static func importedContentTypes() -> [UTType] {
        _unique(_entries.filter { $0.importer != nil }.map(\.contentType))
    }
    public func exportedContentTypes(_ visibility: TransferRepresentationVisibility = .all) -> [UTType] { Self.exportedContentTypes(visibility: visibility) }
    public func importedContentTypes() -> [UTType] { Self.importedContentTypes() }

    /// - SeeAlso: https://developer.apple.com/documentation/coretransferable/transferable/init(importing:contenttype:)-6a3mw
    public init(importing data: Data, contentType: UTType?) async throws {
        let entries = Self._entries.filter { e in e.importer != nil && (contentType.map { $0 == e.contentType || $0.conforms(to: e.contentType) } ?? true) }
        guard let e = entries.first, let item = try e.importer?(data) as? Self else { throw _TransferError.noRepresentation }
        self = item
    }
    /// - SeeAlso: https://developer.apple.com/documentation/coretransferable/transferable/exported(as:)
    public func exported(as contentType: UTType?) async throws -> Data {
        let entries = Self._entries.filter { e in e.exporter != nil && (contentType.map { $0 == e.contentType || e.contentType.conforms(to: $0) } ?? true) }
        guard let e = entries.first, let export = e.exporter else { throw _TransferError.noRepresentation }
        return try export(self)
    }
}

func _unique(_ types: [UTType]) -> [UTType] {
    var seen = Set<String>(), out: [UTType] = []
    for t in types where seen.insert(t.identifier).inserted { out.append(t) }
    return out
}

/// - SeeAlso: https://developer.apple.com/documentation/coretransferable/transferrepresentationvisibility
public struct TransferRepresentationVisibility: Sendable, Equatable {
    let raw: Int
    public static let all = TransferRepresentationVisibility(raw: 0)
    public static let group = TransferRepresentationVisibility(raw: 1)
    public static let ownProcess = TransferRepresentationVisibility(raw: 2)
}

// MARK: Builder

/// - SeeAlso: https://developer.apple.com/documentation/coretransferable/transferrepresentationbuilder
@resultBuilder
public struct TransferRepresentationBuilder<Item: Transferable> {
    public static func buildExpression<Encoder, Decoder>(_ content: CodableRepresentation<Item, Encoder, Decoder>) -> CodableRepresentation<Item, Encoder, Decoder>
        where Item: Decodable, Item: Encodable, Encoder: TopLevelEncoder, Decoder: TopLevelDecoder, Encoder.Output == Data, Decoder.Input == Data { content }
    public static func buildExpression<R: TransferRepresentation>(_ content: R) -> R where Item == R.Item { content }
    public static func buildBlock<Content: TransferRepresentation>(_ content: Content) -> Content where Item == Content.Item { content }
    public static func buildBlock<C1: TransferRepresentation, C2: TransferRepresentation>(_ c1: C1, _ c2: C2) -> TupleTransferRepresentation<Item, (C1, C2)>
        where Item == C1.Item, C1.Item == C2.Item {
        TupleTransferRepresentation(entries: c1._entries + c2._entries)
    }
    public static func buildBlock<C1: TransferRepresentation, C2: TransferRepresentation, C3: TransferRepresentation>(_ c1: C1, _ c2: C2, _ c3: C3) -> TupleTransferRepresentation<Item, (C1, C2, C3)>
        where Item == C1.Item, C1.Item == C2.Item, C2.Item == C3.Item {
        TupleTransferRepresentation(entries: c1._entries + c2._entries + c3._entries)
    }
    public static func buildBlock<C1: TransferRepresentation, C2: TransferRepresentation, C3: TransferRepresentation, C4: TransferRepresentation>(_ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> TupleTransferRepresentation<Item, (C1, C2, C3, C4)>
        where Item == C1.Item, C1.Item == C2.Item, C2.Item == C3.Item, C3.Item == C4.Item {
        TupleTransferRepresentation(entries: c1._entries + c2._entries + c3._entries + c4._entries)
    }
    public static func buildBlock<C1: TransferRepresentation, C2: TransferRepresentation, C3: TransferRepresentation, C4: TransferRepresentation, C5: TransferRepresentation>(_ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5) -> TupleTransferRepresentation<Item, (C1, C2, C3, C4, C5)>
        where Item == C1.Item, C1.Item == C2.Item, C2.Item == C3.Item, C3.Item == C4.Item, C4.Item == C5.Item {
        TupleTransferRepresentation(entries: c1._entries + c2._entries + c3._entries + c4._entries + c5._entries)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/coretransferable/tupletransferrepresentation
public struct TupleTransferRepresentation<Item: Transferable, Value: Sendable>: TransferRepresentation {
    let entries: [_TransferEntry]
    init(entries: [_TransferEntry]) { self.entries = entries }
    public var body: some TransferRepresentation { return _TransferEntriesRepresentation<Item>(entries: entries) }
    public var _entries: [_TransferEntry] { entries }
}

/// A composed representation's entries as one representation (TupleTransferRepresentation's body).
struct _TransferEntriesRepresentation<Item: Transferable>: TransferRepresentation {
    typealias Body = Never
    let entries: [_TransferEntry]
    var body: Never { return fatalError("a composed representation has no body") }
    var _entries: [_TransferEntry] { entries }
}

// MARK: Representations

/// - SeeAlso: https://developer.apple.com/documentation/coretransferable/codablerepresentation
/// The item encoded with the encoder (JSON by default) as data of the content type.
public struct CodableRepresentation<Item, Encoder, Decoder>: TransferRepresentation, @unchecked Sendable
    where Item: Transferable, Item: Decodable, Item: Encodable, Encoder: TopLevelEncoder, Decoder: TopLevelDecoder, Encoder.Output == Data, Decoder.Input == Data {
    public typealias Body = Never
    let contentType: UTType
    let encoder: Encoder
    let decoder: Decoder
    public init(for itemType: Item.Type = Item.self, contentType: UTType) where Encoder == JSONEncoder, Decoder == JSONDecoder {
        self.contentType = contentType; encoder = JSONEncoder(); decoder = JSONDecoder()
    }
    public init(for itemType: Item.Type = Item.self, contentType: UTType, encoder: Encoder, decoder: Decoder) {
        self.contentType = contentType; self.encoder = encoder; self.decoder = decoder
    }
    public var body: Never { return fatalError("CodableRepresentation has no body") }
    public var _entries: [_TransferEntry] {
        let encoder = encoder, decoder = decoder
        return [_TransferEntry(contentType: contentType,
                               exporter: { item in
                                   guard let item = item as? Item else { throw _TransferError.wrongItem }
                                   return try encoder.encode(item)
                               },
                               importer: { data in try decoder.decode(Item.self, from: data) })]
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/coretransferable/datarepresentation
public struct DataRepresentation<Item: Transferable>: TransferRepresentation {
    public typealias Body = Never
    let contentType: UTType
    let exporting: _TransferFunction<Item, Data>?
    let importing: _TransferFunction<Data, Item>?
    public init(contentType: UTType, exporting: @escaping @Sendable (Item) async throws -> Data, importing: @escaping @Sendable (Data) async throws -> Item) {
        self.contentType = contentType; self.exporting = .async(exporting); self.importing = .async(importing)
    }
    public init(exportedContentType: UTType, exporting: @escaping @Sendable (Item) async throws -> Data) {
        contentType = exportedContentType; self.exporting = .async(exporting); importing = nil
    }
    public init(importedContentType: UTType, importing: @escaping @Sendable (Data) async throws -> Item) {
        contentType = importedContentType; exporting = nil; self.importing = .async(importing)
    }
    public var body: Never { return fatalError("DataRepresentation has no body") }
    public var _entries: [_TransferEntry] {
        let exporting = exporting, importing = importing
        return [_TransferEntry(contentType: contentType,
                               exporter: exporting.map { f in { item in
                                   guard let item = item as? Item else { throw _TransferError.wrongItem }
                                   return try f(item)
                               } },
                               importer: importing.map { f in { data in try f(data) } })]
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/coretransferable/proxyrepresentation
/// The item through another Transferable type's representations.
public struct ProxyRepresentation<Item: Transferable, ProxyRepresentation: Transferable>: TransferRepresentation {
    public typealias Body = Never
    let exporting: _TransferFunction<Item, ProxyRepresentation>?
    let importing: _TransferFunction<ProxyRepresentation, Item>?
    public init(importing: @escaping @Sendable (ProxyRepresentation) throws -> Item) { exporting = nil; self.importing = .sync(importing) }
    public init(importing: @escaping @Sendable (ProxyRepresentation) async throws -> Item) { exporting = nil; self.importing = .async(importing) }
    public init(exporting: @escaping @Sendable (Item) throws -> ProxyRepresentation) { self.exporting = .sync(exporting); importing = nil }
    public init(exporting: @escaping @Sendable (Item) async throws -> ProxyRepresentation) { self.exporting = .async(exporting); importing = nil }
    public init(exporting: @escaping @Sendable (Item) throws -> ProxyRepresentation, importing: @escaping @Sendable (ProxyRepresentation) throws -> Item) {
        self.exporting = .sync(exporting); self.importing = .sync(importing)
    }
    public init(exporting: @escaping @Sendable (Item) async throws -> ProxyRepresentation, importing: @escaping @Sendable (ProxyRepresentation) async throws -> Item) {
        self.exporting = .async(exporting); self.importing = .async(importing)
    }
    public init(exporting: @escaping @Sendable (Item) throws -> ProxyRepresentation, importing: @escaping @Sendable (ProxyRepresentation) async throws -> Item) {
        self.exporting = .sync(exporting); self.importing = .async(importing)
    }
    public var body: Never { return fatalError("ProxyRepresentation has no body") }
    public var _entries: [_TransferEntry] {
        let exporting = exporting, importing = importing
        return ProxyRepresentation._entries.map { e in
            _TransferEntry(contentType: e.contentType,
                           exporter: exporting.flatMap { f in e.exporter.map { export in { item in
                               guard let item = item as? Item else { throw _TransferError.wrongItem }
                               return try export(try f(item))
                           } } },
                           importer: importing.flatMap { f in e.importer.map { load in { data in
                               guard let proxy = try load(data) as? ProxyRepresentation else { throw _TransferError.wrongItem }
                               return try f(proxy)
                           } } })
        }
    }
}

// MARK: Standard conformances

extension String: Transferable {
    /// UTF-8 plain text.
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation<String>(contentType: .utf8PlainText, exporting: { Data($0.utf8) }, importing: { String(decoding: $0, as: UTF8.self) })
    }
}

extension Data: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation<Data>(contentType: .data, exporting: { $0 }, importing: { $0 })
    }
}

// MARK: Item providers

/// An item provider carrying every exported representation of `item`.
func _itemProvider<T: Transferable>(for item: T) -> NSItemProvider {
    let provider = NSItemProvider()
    provider.register(item)
    return provider
}

extension NSItemProvider {
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsitemprovider/register(_:)-3qeqg
    public func register<T: Transferable>(_ transferable: @autoclosure @escaping @Sendable () -> T) {
        for e in T._entries {
            guard let export = e.exporter else { continue }
            registerDataRepresentation(forTypeIdentifier: e.contentType.identifier, visibility: .all) { completion in
                do { completion(try export(transferable()), nil) } catch { completion(nil, error) }
                return nil
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsitemprovider/loadtransferable(type:completionhandler:)
    @discardableResult
    public func loadTransferable<T: Transferable>(type transferableType: T.Type, completionHandler: @escaping @Sendable (Result<T, any Error>) -> Void) -> Progress {
        let registered = registeredTypeIdentifiers
        let entry = T._entries.first { e in e.importer != nil && registered.contains { _dropTypeMatches($0, e.contentType) } }
        guard let entry, let load = entry.importer, let typeID = registered.first(where: { _dropTypeMatches($0, entry.contentType) }) else {
            completionHandler(.failure(_TransferError.noRepresentation))
            return Progress(totalUnitCount: 0)
        }
        return loadDataRepresentation(forTypeIdentifier: typeID) { data, error in
            guard let data else { completionHandler(.failure(error ?? _TransferError.noRepresentation)); return }
            do {
                guard let item = try load(data) as? T else { throw _TransferError.wrongItem }
                completionHandler(.success(item))
            } catch { completionHandler(.failure(error)) }
        }
    }
}

// MARK: Drag and drop

/// Drops of a Transferable type: each dropped item decoded through the first
/// representation whose content type it carries.
struct _TransferDropDelegate<T: Transferable>: DropDelegate {
    let entries: [_TransferEntry]
    let action: ([T], CGPoint) -> Bool
    let isTargeted: (Bool) -> Void
    var types: [UTType] { _unique(entries.map(\.contentType)) }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: types) }
    func dropEntered(info: DropInfo) { isTargeted(true) }
    func dropExited(info: DropInfo) { isTargeted(false) }
    func performDrop(info: DropInfo) -> Bool {
        isTargeted(false)
        let items = decode(info.items)
        guard !items.isEmpty else { return false }
        return action(items, info.location)
    }
    func decode(_ pasteboardItems: [NSPasteboardItem]) -> [T] {
        pasteboardItems.compactMap { item -> T? in
            for e in entries {
                guard let load = e.importer else { continue }
                for t in item.types where _dropTypeMatches(t.rawValue, e.contentType) {
                    if let data = item.data(forType: t), let value = try? load(data) as? T { return value }
                }
            }
            return nil
        }
    }
}

/// The image of a drag preview view, rendered offscreen at its ideal size.
@MainActor
func _renderDragPreview<V: View>(_ view: V) -> NSImage? {
    let hosting = NSHostingView(rootView: view)
    let size = hosting.sizeThatFits(.unspecified)
    guard size.width > 0, size.height > 0 else { return nil }
    hosting.frame = NSRect(origin: .zero, size: NSSize(width: size.width.rounded(.up), height: size.height.rounded(.up)))
    hosting.layoutSubtreeIfNeeded()
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    guard let cg = rep.cgImage else { return nil }
    return NSImage(cgImage: cg, size: hosting.bounds.size)
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/draggable(_:)
    /// Drags the payload's exported representations (an NSItemProvider through
    /// `onDrag`), with a snapshot of this view as the drag image.
    public func draggable<T: Transferable>(_ payload: @autoclosure @escaping () -> T) -> some View {
        _DragSource(content: self, makeProvider: { _itemProvider(for: payload()) })
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/draggable(_:preview:)
    /// As `draggable(_:)`, with the preview view rendered as the drag image.
    public func draggable<V: View, T: Transferable>(_ payload: @autoclosure @escaping () -> T, @ViewBuilder preview: () -> V) -> some View {
        let p = preview()
        return _DragSource(content: self, makeProvider: { _itemProvider(for: payload()) }, makePreview: { _renderDragPreview(p) })
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/dropdestination(for:action:istargeted:)
    /// Takes drops carrying any of the type's imported content types; `action` gets the
    /// decoded items and the drop location (top-left origin) and is not called when no item
    /// decodes. `isTargeted` follows the drag entering and leaving.
    public func dropDestination<T: Transferable>(for payloadType: T.Type = T.self, action: @escaping (_ items: [T], _ location: CGPoint) -> Bool, isTargeted: @escaping (Bool) -> Void = { _ in }) -> some View {
        let entries = T._entries.filter { $0.importer != nil }
        let delegate = _TransferDropDelegate<T>(entries: entries, action: action, isTargeted: isTargeted)
        return _DropTarget(content: self, types: delegate.types, delegate: delegate)
    }
}
