// GeometryReader: content built from the size the reader is given.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/coordinatespace
public enum CoordinateSpace: Equatable, Hashable {
    case global
    case local
    case named(AnyHashable)
    public var isGlobal: Bool { self == .global }
    public var isLocal: Bool { self == .local }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/geometryproxy
public struct GeometryProxy {
    public let size: CGSize
    public let safeAreaInsets: EdgeInsets
    let globalFrame: CGRect

    public func frame(in coordinateSpace: CoordinateSpace) -> CGRect {
        switch coordinateSpace {
        case .local: return CGRect(origin: .zero, size: size)
        case .global, .named: return globalFrame
        }
    }
    public subscript<T>(anchor: Anchor<T>) -> T { anchor.value }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/anchor
public struct Anchor<Value> {
    let value: Value
    public struct Source {}
}

@MainActor
final class _GeometryReaderPrimitive: _Primitive {
    var make: (GeometryProxy) -> _AnyViewBox
    private var lastProxy: (size: CGSize, frame: CGRect)?

    init(make: @escaping (GeometryProxy) -> _AnyViewBox) {
        self.make = make
        super.init()
    }
    override func update(from other: _Primitive) {
        guard let o = other as? _GeometryReaderPrimitive else { return }
        make = o.make
        if let p = lastProxy { children = [make(GeometryProxy(size: p.size, safeAreaInsets: EdgeInsets(), globalFrame: p.frame))] }
    }
    /// A reader takes whatever it is offered; unspecified dimensions use 10 points.
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        CGSize(width: proposal.width.map { $0.isFinite ? $0 : 10 } ?? 10, height: proposal.height.map { $0.isFinite ? $0 : 10 } ?? 10)
    }
    override func place(node: _ViewNode, in rect: CGRect) {
        if lastProxy?.size != rect.size || lastProxy?.frame != rect {
            lastProxy = (rect.size, rect)
            // The content depends on the size: rebuild it and let the root settle the pass.
            children = [make(GeometryProxy(size: rect.size, safeAreaInsets: EdgeInsets(), globalFrame: rect))]
            node.setNeedsUpdate()
        }
        // Content sits at the top-leading corner with its own size.
        for c in node.children {
            let s = c.sizeThatFits(ProposedViewSize(rect.size))
            c.place(in: CGRect(origin: rect.origin, size: s).integralIfNeeded)
        }
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/geometryreader
public struct GeometryReader<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public var content: (GeometryProxy) -> Content
    public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) { self.content = content }
    public func _makePrimitive(node: _ViewNode) -> _Primitive {
        let c = content
        return _GeometryReaderPrimitive { _ViewBox(c($0)) }
    }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/coordinatespace(_:)
    public func coordinateSpace<T: Hashable>(name: T) -> some View { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/coordinatespace(_:)
    public func coordinateSpace(_ name: NamedCoordinateSpace) -> some View { self }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/namedcoordinatespace
public struct NamedCoordinateSpace: Hashable, Sendable {
    let name: AnyHashable
    public static func named<T: Hashable>(_ name: T) -> NamedCoordinateSpace { NamedCoordinateSpace(name: AnyHashable(name)) }
    public static func == (a: NamedCoordinateSpace, b: NamedCoordinateSpace) -> Bool { a.name == b.name }
    public func hash(into h: inout Hasher) { h.combine(name) }
}
