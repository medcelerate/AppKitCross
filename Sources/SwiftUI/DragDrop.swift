// Drag and drop: onDrag starts an AppKit dragging session from a view's snapshot with the
// item provider's data; onDrop registers the view as a dragging destination and hands the
// dropped items back as item providers.

import Foundation
import UniformTypeIdentifiers

// MARK: Drop types

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/dropoperation
public enum DropOperation: Sendable, Equatable {
    case cancel
    case forbidden
    case copy
    case move
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/dropproposal
public struct DropProposal: Sendable {
    public let operation: DropOperation
    public init(operation: DropOperation) { self.operation = operation }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/dropinfo
public struct DropInfo {
    /// The pointer location in the destination view's coordinates (origin top-left).
    public let location: CGPoint
    let items: [NSPasteboardItem]

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/dropinfo/hasitemsconforming(to:)
    public func hasItemsConforming(to contentTypes: [UTType]) -> Bool {
        items.contains { item in item.types.contains { t in contentTypes.contains { _dropTypeMatches(t.rawValue, $0) } } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/dropinfo/itemproviders(for:)
    public func itemProviders(for contentTypes: [UTType]) -> [NSItemProvider] {
        items.compactMap { item -> NSItemProvider? in
            let provider = NSItemProvider()
            var any = false
            for t in item.types where contentTypes.contains(where: { _dropTypeMatches(t.rawValue, $0) }) {
                guard let data = item.data(forType: t) else { continue }
                any = true
                provider.registerDataRepresentation(forTypeIdentifier: t.rawValue, visibility: .all) { completion in
                    completion(data, nil)
                    return nil
                }
            }
            return any ? provider : nil
        }
    }
}

func _dropTypeMatches(_ pasteboardType: String, _ type: UTType) -> Bool {
    if pasteboardType == type.identifier { return true }
    if let dragged = UTType(pasteboardType), dragged.conforms(to: type) { return true }
    return _NSPasteboardTypeConformance.conforms(pasteboardType, to: type.identifier)
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/dropdelegate
@MainActor
public protocol DropDelegate {
    func validateDrop(info: DropInfo) -> Bool
    func dropEntered(info: DropInfo)
    func dropUpdated(info: DropInfo) -> DropProposal?
    func dropExited(info: DropInfo)
    func performDrop(info: DropInfo) -> Bool
}

extension DropDelegate {
    public func validateDrop(info: DropInfo) -> Bool { true }
    public func dropEntered(info: DropInfo) { }
    public func dropUpdated(info: DropInfo) -> DropProposal? { nil }
    public func dropExited(info: DropInfo) { }
}

/// The perform-closure forms of onDrop as a delegate.
struct _ClosureDropDelegate: DropDelegate {
    let types: [UTType]
    let isTargeted: Binding<Bool>?
    let perform: ([NSItemProvider], CGPoint) -> Bool
    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: types) }
    func dropEntered(info: DropInfo) { isTargeted?.wrappedValue = true }
    func dropExited(info: DropInfo) { isTargeted?.wrappedValue = false }
    func performDrop(info: DropInfo) -> Bool {
        isTargeted?.wrappedValue = false
        return perform(info.itemProviders(for: types), info.location)
    }
}

// MARK: Drop destination

/// Hosts content and takes drags of the registered types.
@MainActor
final class _DropTargetView: NSView {
    var types: [UTType] = [] {
        didSet { unregisterDraggedTypes(); registerForDraggedTypes(types.map { NSPasteboard.PasteboardType($0.identifier) }) }
    }
    var delegate: (any DropDelegate)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) }   // self where no child hits

    private func info(_ sender: any NSDraggingInfo) -> DropInfo {
        let p = convert(sender.draggingLocation, from: nil)
        return DropInfo(location: CGPoint(x: p.x, y: p.y), items: sender.draggingPasteboard.pasteboardItems ?? [])
    }
    private func operation(_ proposal: DropProposal?) -> NSDragOperation {
        switch proposal?.operation ?? .copy {
        case .cancel: return []
        case .forbidden: return []
        case .copy: return .copy
        case .move: return .move
        }
    }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let delegate else { return [] }
        let i = info(sender)
        guard delegate.validateDrop(info: i) else { return [] }
        delegate.dropEntered(info: i)
        return operation(delegate.dropUpdated(info: i))
    }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let delegate else { return [] }
        let i = info(sender)
        guard delegate.validateDrop(info: i) else { return [] }
        return operation(delegate.dropUpdated(info: i))
    }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        guard let delegate, let sender else { return }
        delegate.dropExited(info: info(sender))
    }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { delegate != nil }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let delegate else { return false }
        return delegate.performDrop(info: info(sender))
    }
}

@MainActor
final class _DropTargetPrimitive: _Primitive {
    let view = _DropTargetView(frame: .zero)
    init(content: _AnyViewBox, types: [UTType], delegate: any DropDelegate) {
        super.init()
        children = [content]
        view.types = types
        view.delegate = delegate
    }
    override var nsView: NSView? { view }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _DropTargetPrimitive else { return }
        if o.view.types.map(\.identifier) != view.types.map(\.identifier) { view.types = o.view.types }
        view.delegate = o.view.delegate
    }
}

struct _DropTarget<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let types: [UTType]
    let delegate: any DropDelegate
    func _makePrimitive(node: _ViewNode) -> _Primitive { _DropTargetPrimitive(content: _ViewBox(content), types: types, delegate: delegate) }
}

// MARK: Drag source

/// Hosts content and starts a drag when the mouse moves a few points after a press.
@MainActor
final class _DragSourceView: NSView, NSDraggingSource {
    var makeProvider: (() -> NSItemProvider)?
    private var pressed: NSPoint?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) { pressed = event.locationInWindow }
    override func mouseUp(with event: NSEvent) { pressed = nil; super.mouseUp(with: event) }
    override func mouseDragged(with event: NSEvent) {
        guard let start = pressed, let makeProvider else { super.mouseDragged(with: event); return }
        let p = event.locationInWindow
        guard abs(p.x - start.x) > 3 || abs(p.y - start.y) > 3 else { return }
        pressed = nil
        let item = _ItemProviderPasteboardSource.pasteboardItem(for: makeProvider())
        let dragging = NSDraggingItem(pasteboardWriter: item)
        dragging.setDraggingFrame(bounds, contents: snapshot())
        _ = beginDraggingSession(with: [dragging], event: event, source: self)
    }
    private func snapshot() -> NSImage? {
        guard bounds.width > 0, bounds.height > 0, let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        guard let cg = rep.cgImage else { return nil }
        return NSImage(cgImage: cg, size: bounds.size)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}

/// Feeds an item provider's representations to a pasteboard item on demand. Foundation's
/// provider delivers data through a completion handler, possibly on another queue, so the
/// request waits for it (bounded) when the destination asks.
final class _ItemProviderPasteboardSource: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    let provider: NSItemProvider
    init(provider: NSItemProvider) { self.provider = provider }

    static func pasteboardItem(for provider: NSItemProvider) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        let source = _ItemProviderPasteboardSource(provider: provider)
        let types = provider.registeredTypeIdentifiers.map { NSPasteboard.PasteboardType($0) }
        _ = item.setDataProvider(source, forTypes: types)
        return item
    }
    nonisolated func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var loaded: Data?
        provider.loadDataRepresentation(forTypeIdentifier: type.rawValue) { data, _ in
            loaded = data
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
        if let loaded { _ = item.setData(loaded, forType: type) }
    }
    nonisolated func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) { }
}

@MainActor
final class _DragSourcePrimitive: _Primitive {
    let view = _DragSourceView(frame: .zero)
    init(content: _AnyViewBox, makeProvider: @escaping () -> NSItemProvider) {
        super.init()
        children = [content]
        view.makeProvider = makeProvider
    }
    override var nsView: NSView? { view }
    override func update(from other: _Primitive) {
        super.update(from: other)
        if let o = other as? _DragSourcePrimitive { view.makeProvider = o.view.makeProvider }
    }
}

struct _DragSource<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let makeProvider: () -> NSItemProvider
    func _makePrimitive(node: _ViewNode) -> _Primitive { _DragSourcePrimitive(content: _ViewBox(content), makeProvider: makeProvider) }
}

// MARK: Modifiers

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/ondrag(_:)
    public func onDrag(_ data: @escaping () -> NSItemProvider) -> some View {
        _DragSource(content: self, makeProvider: data)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/ondrop(of:istargeted:perform:)
    public func onDrop(of supportedContentTypes: [UTType], isTargeted: Binding<Bool>?, perform action: @escaping ([NSItemProvider]) -> Bool) -> some View {
        _DropTarget(content: self, types: supportedContentTypes, delegate: _ClosureDropDelegate(types: supportedContentTypes, isTargeted: isTargeted) { providers, _ in action(providers) })
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/ondrop(of:istargeted:perform:)
    public func onDrop(of supportedContentTypes: [UTType], isTargeted: Binding<Bool>?, perform action: @escaping ([NSItemProvider], CGPoint) -> Bool) -> some View {
        _DropTarget(content: self, types: supportedContentTypes, delegate: _ClosureDropDelegate(types: supportedContentTypes, isTargeted: isTargeted, perform: action))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/ondrop(of:delegate:)
    public func onDrop(of supportedContentTypes: [UTType], delegate: any DropDelegate) -> some View {
        _DropTarget(content: self, types: supportedContentTypes, delegate: delegate)
    }
}
