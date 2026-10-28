// SwiftUI for AppKitWin (ADR-0010): the View protocol, the result builder and the
// structural views the builder produces.

import Foundation
@_exported import AppKit
#if canImport(Combine)
import Combine
#endif

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/view
public protocol View: NSHostingContent {
    associatedtype Body: View
    @ViewBuilder @MainActor var body: Self.Body { get }
}

extension Never: View {
    public var body: Never { fatalError("Never has no body") }
}

extension View where Body == Never {
    public var body: Never { fatalError("\(Self.self) is a primitive view and has no body") }
}

/// A view that renders itself (no `body`): it supplies the runtime object that measures,
/// places and backs it with AppKit.
public protocol _PrimitiveView {
    @MainActor func _makePrimitive(node: _ViewNode) -> _Primitive
}

// MARK: Hosting bridge

extension View {
    @MainActor public func _makeHostingRoot() -> any NSHostingRoot { _ViewRoot(content: self) }
    @MainActor public func _updateHostingRoot(_ root: any NSHostingRoot) { (root as? _ViewRoot)?.setContent(self) }
}

// MARK: ViewBuilder

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/viewbuilder
@resultBuilder
public struct ViewBuilder {
    public static func buildBlock() -> EmptyView { EmptyView() }
    public static func buildBlock<C: View>(_ c: C) -> C { c }
    public static func buildBlock<C0: View, C1: View>(_ c0: C0, _ c1: C1) -> TupleView<(C0, C1)> { TupleView((c0, c1)) }
    public static func buildBlock<C0: View, C1: View, C2: View>(_ c0: C0, _ c1: C1, _ c2: C2) -> TupleView<(C0, C1, C2)> { TupleView((c0, c1, c2)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> TupleView<(C0, C1, C2, C3)> { TupleView((c0, c1, c2, c3)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> TupleView<(C0, C1, C2, C3, C4)> { TupleView((c0, c1, c2, c3, c4)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5) -> TupleView<(C0, C1, C2, C3, C4, C5)> { TupleView((c0, c1, c2, c3, c4, c5)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6) -> TupleView<(C0, C1, C2, C3, C4, C5, C6)> { TupleView((c0, c1, c2, c3, c4, c5, c6)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7)> { TupleView((c0, c1, c2, c3, c4, c5, c6, c7)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8)> { TupleView((c0, c1, c2, c3, c4, c5, c6, c7, c8)) }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View, C9: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)> { TupleView((c0, c1, c2, c3, c4, c5, c6, c7, c8, c9)) }
    public static func buildExpression<C: View>(_ c: C) -> C { c }
    public static func buildOptional<C: View>(_ c: C?) -> C? { c }
    public static func buildEither<T: View, F: View>(first: T) -> _ConditionalContent<T, F> { _ConditionalContent(storage: .trueContent(first)) }
    public static func buildEither<T: View, F: View>(second: F) -> _ConditionalContent<T, F> { _ConditionalContent(storage: .falseContent(second)) }
    public static func buildLimitedAvailability<C: View>(_ c: C) -> AnyView { AnyView(c) }
    public static func buildArray<C: View>(_ cs: [C]) -> ForEach<[Int], Int, C> {
        ForEach(Array(cs.indices), id: \.self) { cs[$0] }
    }
}

// MARK: Structural views

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/emptyview
public struct EmptyView: View, _PrimitiveView {
    public typealias Body = Never
    public init() {}
    public func _makePrimitive(node: _ViewNode) -> _Primitive { _GroupPrimitive(children: []) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/tupleview
public struct TupleView<T>: View, _PrimitiveView {
    public typealias Body = Never
    public var value: T
    public init(_ value: T) { self.value = value }
    public func _makePrimitive(node: _ViewNode) -> _Primitive {
        _GroupPrimitive(children: _tupleChildren(value))
    }
}

/// The views inside a tuple, in order.
@MainActor
func _tupleChildren(_ value: Any) -> [_AnyViewBox] {
    Mirror(reflecting: value).children.compactMap { _boxView($0.value) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/_conditionalcontent
public struct _ConditionalContent<TrueContent: View, FalseContent: View>: View, _PrimitiveView {
    public typealias Body = Never
    enum Storage { case trueContent(TrueContent), falseContent(FalseContent) }
    let storage: Storage
    public func _makePrimitive(node: _ViewNode) -> _Primitive {
        switch storage {
        case .trueContent(let v): return _GroupPrimitive(children: [_ViewBox(v, id: "true")])
        case .falseContent(let v): return _GroupPrimitive(children: [_ViewBox(v, id: "false")])
        }
    }
}

extension Optional: NSHostingContent where Wrapped: View {}
extension Optional: View, _PrimitiveView where Wrapped: View {
    public typealias Body = Never
    public func _makePrimitive(node: _ViewNode) -> _Primitive {
        _GroupPrimitive(children: self.map { [_ViewBox($0)] } ?? [])
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/group
public struct Group<Content>: View, _PrimitiveView where Content: View {
    public typealias Body = Never
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public func _makePrimitive(node: _ViewNode) -> _Primitive { _GroupPrimitive(children: [_ViewBox(content)]) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/anyview
public struct AnyView: View, _PrimitiveView {
    public typealias Body = Never
    let box: _AnyViewBox
    public init<V: View>(_ view: V) { box = _ViewBox(view) }
    public init<V: View>(erasing view: V) { self.init(view) }
    public init?(_fromValue value: Any) {
        guard let b = _boxView(value) else { return nil }
        box = b
    }
    public func _makePrimitive(node: _ViewNode) -> _Primitive { _GroupPrimitive(children: [box]) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/foreach
public struct ForEach<Data, ID, Content>: View, _PrimitiveView where Data: RandomAccessCollection, ID: Hashable, Content: View {
    public typealias Body = Never
    public var data: Data
    public var content: (Data.Element) -> Content
    let idForElement: (Data.Element) -> ID

    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
        idForElement = { $0[keyPath: id] }
    }
    public func _makePrimitive(node: _ViewNode) -> _Primitive {
        _GroupPrimitive(children: data.map { _ViewBox(content($0), id: AnyHashable(idForElement($0))) })
    }
}

extension ForEach where Data.Element: Identifiable, ID == Data.Element.ID {
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.init(data, id: \.id, content: content)
    }
}

extension ForEach where Data == Range<Int>, ID == Int {
    public init(_ data: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content) {
        self.init(data, id: \.self, content: content)
    }
}

// MARK: Identifiable helpers

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/id(_:)
extension View {
    public func id<ID: Hashable>(_ id: ID) -> some View { _IdentifiedView(content: self, id: AnyHashable(id)) }
}

struct _IdentifiedView<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let id: AnyHashable
    func _makePrimitive(node: _ViewNode) -> _Primitive { _GroupPrimitive(children: [_ViewBox(content, id: id)]) }
}

// MARK: Modifiers

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/viewmodifier
public protocol ViewModifier {
    associatedtype Body: View
    typealias Content = _ViewModifier_Content<Self>
    @ViewBuilder @MainActor func body(content: Content) -> Body
}

/// The content a `ViewModifier` wraps.
public struct _ViewModifier_Content<Modifier: ViewModifier>: View, _PrimitiveView {
    public typealias Body = Never
    let box: _AnyViewBox
    public func _makePrimitive(node: _ViewNode) -> _Primitive { _GroupPrimitive(children: [box]) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/modifiedcontent
public struct ModifiedContent<Content, Modifier>: View where Content: View, Modifier: ViewModifier {
    public var content: Content
    public var modifier: Modifier
    public init(content: Content, modifier: Modifier) {
        self.content = content
        self.modifier = modifier
    }
    public var body: Modifier.Body {
        modifier.body(content: _ViewModifier_Content(box: _ViewBox(content)))
    }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/modifier(_:)
    public func modifier<M: ViewModifier>(_ modifier: M) -> ModifiedContent<Self, M> { ModifiedContent(content: self, modifier: modifier) }
}

/// A modifier whose body is its content with environment or layout changes applied by the
/// runtime rather than by a `body` (the built-in modifiers).
public struct _EmptyModifier: ViewModifier {
    public init() {}
    public func body(content: Content) -> Content { content }
}
