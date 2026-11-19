// Editing dynamic content (ADR-0010 addendum, 2026-11-18): DynamicViewContent, onDelete in
// lists (Delete and Edit > Delete on the selected rows, as on macOS), and SwiftUI's
// offset-based collection helpers.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/dynamicviewcontent
@MainActor @preconcurrency
public protocol DynamicViewContent: View {
    associatedtype Data: Collection
    var data: Data { get }
}

extension ForEach: DynamicViewContent {}

extension ModifiedContent: DynamicViewContent where Content: DynamicViewContent {
    public var data: Content.Data { content.data }
}

extension DynamicViewContent {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/dynamicviewcontent/ondelete(perform:)
    ///
    /// In a `List` with a selection, Delete (and Edit > Delete) passes the offsets of the
    /// selected rows that this content produced.
    public func onDelete(perform action: ((IndexSet) -> Void)?) -> some DynamicViewContent {
        _DeleteActionContent(base: self, action: action)
    }
}

/// The content with its delete action: a transparent group the list's rows read.
struct _DeleteActionContent<Base: DynamicViewContent>: DynamicViewContent, _PrimitiveView {
    typealias Body = Never
    let base: Base
    let action: ((IndexSet) -> Void)?
    var data: Base.Data { base.data }
    func _makePrimitive(node: _ViewNode) -> _Primitive { _RowActionsPrimitive(onDelete: action, content: _ViewBox(base)) }
}

@MainActor
final class _RowActionsPrimitive: _Primitive {
    var onDelete: ((IndexSet) -> Void)?
    init(onDelete: ((IndexSet) -> Void)?, content: _AnyViewBox) {
        self.onDelete = onDelete
        super.init()
        children = [content]
    }
    override var isLayoutTransparent: Bool { true }
    override func update(from other: _Primitive) {
        super.update(from: other)
        if let o = other as? _RowActionsPrimitive { onDelete = o.onDelete }
    }
}

/// A `ForEach`'s elements: a transparent group whose children are the elements in order
/// (a list maps each row back to its element's offset through it).
@MainActor
final class _ForEachPrimitive: _Primitive {
    init(children: [_AnyViewBox]) {
        super.init()
        self.children = children
    }
    override var isLayoutTransparent: Bool { true }
}

// MARK: Offsets

extension RangeReplaceableCollection where Self: MutableCollection {
    /// - SeeAlso: https://developer.apple.com/documentation/swift/rangereplaceablecollection/remove(atoffsets:)
    public mutating func remove(atOffsets offsets: IndexSet) {
        guard let first = offsets.first else { return }
        // Keep everything not removed, in order, from the first removed element on.
        var write = index(startIndex, offsetBy: first)
        var read = write
        var offset = first
        while read != endIndex {
            if !offsets.contains(offset) {
                swapAt(write, read)
                formIndex(after: &write)
            }
            formIndex(after: &read)
            offset += 1
        }
        removeSubrange(write..<endIndex)
    }
}

extension MutableCollection {
    /// - SeeAlso: https://developer.apple.com/documentation/swift/mutablecollection/move(fromoffsets:tooffset:)
    ///
    /// Moves the elements at `source` so they sit before the element that was at
    /// `destination` (or at the end), keeping the order of both the moved and the rest.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let elements = Array(self)
        let moved = source.filter { $0 < elements.count }.map { elements[$0] }
        var before: [Element] = []
        var after: [Element] = []
        for (offset, element) in elements.enumerated() where !source.contains(offset) {
            if offset < destination { before.append(element) } else { after.append(element) }
        }
        var i = startIndex
        for element in before + moved + after {
            self[i] = element
            formIndex(after: &i)
        }
    }
}
