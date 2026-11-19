// Per-row list configuration: `listRowInsets`, `listRowBackground`, `listRowSeparator`,
// plus `badge` and the `VerticalEdge`/`HorizontalEdge` types those modifiers take.
//
// A decorated row is measured and placed by the list in its whole row frame; the
// decoration insets its content (by its own insets, else the list's) and draws its
// background behind the content across that frame.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/verticaledge
public enum VerticalEdge: Int8, CaseIterable, Codable, Hashable, Sendable {
    case top, bottom
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/verticaledge/set
    public struct Set: OptionSet, Equatable, Hashable, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public init(_ edge: VerticalEdge) { self.init(rawValue: 1 << edge.rawValue) }
        public static let top = Set(.top)
        public static let bottom = Set(.bottom)
        public static let all: Set = [.top, .bottom]
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/horizontaledge
public enum HorizontalEdge: Int8, CaseIterable, Codable, Hashable, Sendable {
    case leading, trailing
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/horizontaledge/set
    public struct Set: OptionSet, Equatable, Hashable, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public init(_ edge: HorizontalEdge) { self.init(rawValue: 1 << edge.rawValue) }
        public static let leading = Set(.leading)
        public static let trailing = Set(.trailing)
        public static let all: Set = [.leading, .trailing]
    }
}

// MARK: Row decorations

struct _ListRowTraits {
    var insets: EdgeInsets? = nil
    var background: AnyView? = nil
    var hasBackground = false
    var separatorHidden: VerticalEdge.Set = []
}

struct _ListRowDecorated<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let apply: (inout _ListRowTraits) -> Void
    func _makePrimitive(node: _ViewNode) -> _Primitive {
        var traits = _ListRowTraits()
        apply(&traits)
        return _ListRowDecorationPrimitive(traits: traits, content: _ViewBox(content))
    }
}

@MainActor
final class _ListRowDecorationPrimitive: _Primitive {
    var traits: _ListRowTraits
    let contentBox: _AnyViewBox
    /// The list's own row insets, used where the row does not set its own.
    static let defaultInsets = EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)

    init(traits: _ListRowTraits, content: _AnyViewBox) {
        self.traits = traits
        contentBox = content
        super.init()
        children = traits.background.map { [_ViewBox($0, id: AnyHashable("listRowBackground")), content] } ?? [content]
    }
    override func update(from other: _Primitive) {
        super.update(from: other)
        if let o = other as? _ListRowDecorationPrimitive { traits = o.traits }
    }
    /// All decorations from this row node down its single-child chain, outermost first
    /// winning for each trait.
    static func traits(of row: _ViewNode) -> _ListRowTraits? {
        var found: _ListRowTraits? = nil
        var n: _ViewNode? = row
        while let node = n {
            if let d = node.primitive as? _ListRowDecorationPrimitive {
                var t = found ?? _ListRowTraits()
                if t.insets == nil { t.insets = d.traits.insets }
                if !t.hasBackground, d.traits.hasBackground { t.hasBackground = true; t.background = d.traits.background }
                t.separatorHidden.formUnion(d.traits.separatorHidden)
                found = t
            }
            n = node.children.count == 1 ? node.children[0] : (node.primitive is _ListRowDecorationPrimitive ? node.children.last : nil)
        }
        return found
    }
    private var insets: EdgeInsets {
        guard let node else { return Self.defaultInsets }
        return Self.traits(of: node)?.insets ?? Self.defaultInsets
    }
    private var contentNode: _ViewNode? { node?.children.last }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        let i = insets
        let inner = ProposedViewSize(width: proposal.width.map { max(0, $0 - i.horizontal) }, height: proposal.height.map { max(0, $0 - i.vertical) })
        let s = contentNode?.sizeThatFits(inner) ?? .zero
        let width = proposal.width.map { $0.isFinite ? $0 : s.width + i.horizontal } ?? (s.width + i.horizontal)
        return CGSize(width: width, height: s.height + i.vertical)
    }
    override func place(node: _ViewNode, in rect: CGRect) {
        let i = insets
        let inner = CGRect(x: rect.minX + i.leading, y: rect.minY + i.top, width: max(0, rect.width - i.horizontal), height: max(0, rect.height - i.vertical))
        if node.children.count == 2 { node.children[0].place(in: rect) }
        if let c = node.children.last {
            let s = c.sizeThatFits(ProposedViewSize(inner.size))
            c.place(in: CGRect(x: inner.minX, y: inner.minY + (inner.height - s.height) / 2, width: inner.width, height: s.height).integralIfNeeded)
        }
    }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/listrowinsets(_:)
    public func listRowInsets(_ insets: EdgeInsets?) -> some View {
        _ListRowDecorated(content: self) { $0.insets = insets }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/listrowinsets(_:_:)
    public func listRowInsets(_ edges: Edge.Set = .all, _ length: CGFloat?) -> some View {
        let d = _ListRowDecorationPrimitive.defaultInsets
        let l = length ?? 0
        let insets = EdgeInsets(top: edges.contains(.top) ? l : d.top, leading: edges.contains(.leading) ? l : d.leading,
                                bottom: edges.contains(.bottom) ? l : d.bottom, trailing: edges.contains(.trailing) ? l : d.trailing)
        return _ListRowDecorated(content: self) { $0.insets = insets }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/listrowbackground(_:)
    ///
    /// The view fills the row's whole frame behind its content (and above the selection
    /// highlight, as on macOS); nil keeps the list's background.
    public func listRowBackground<V: View>(_ view: V?) -> some View {
        _ListRowDecorated(content: self) { t in
            t.hasBackground = true
            t.background = view.map { AnyView($0) }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/listrowseparator(_:edges:)
    ///
    /// `.hidden` removes the separator line above (`top`) or below (`bottom`) the row.
    public func listRowSeparator(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View {
        _ListRowDecorated(content: self) { t in
            if visibility == .hidden { t.separatorHidden = edges }
        }
    }
}

// MARK: badge

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/badge(_:)-84e43
    ///
    /// The count trails the view in secondary text (as in a sidebar row); zero shows no badge.
    public func badge(_ count: Int) -> some View { _badged(count == 0 ? nil : Text(verbatim: "\(count)")) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/badge(_:)-6k2u9
    public func badge(_ label: Text?) -> some View { _badged(label) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/badge(_:)-9zi7o
    public func badge(_ key: LocalizedStringKey?) -> some View { _badged(key.map { Text($0) }) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/badge(_:)-4hj0h
    @_disfavoredOverload
    public func badge<S: StringProtocol>(_ label: S?) -> some View { _badged(label.map { Text($0) }) }

    private func _badged(_ label: Text?) -> some View {
        HStack(spacing: 4) {
            self
            if let label {
                Spacer(minLength: 4)
                label.foregroundColor(Color(nsColor: .secondaryLabelColor)).monospacedDigit()
            }
        }
    }
}
