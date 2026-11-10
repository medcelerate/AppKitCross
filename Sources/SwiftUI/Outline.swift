// DisclosureGroup and OutlineGroup, and List over a tree (`children:`): the rows of the
// expanded part of a tree, each indented by its level with a disclosure triangle, so a
// List's row model (selection, keyboard) sees one row per visible node.

import Foundation

// MARK: Disclosure triangle

/// The triangle of a disclosure group or outline row: points right while collapsed and
/// down while expanded (mirrored right to left by the layout direction).
struct _DisclosureTriangleShape: Shape {
    let expanded: Bool
    let mirrored: Bool
    nonisolated func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX, cy = rect.midY
        let half = min(rect.width, rect.height) * 0.4
        let depth = half
        if expanded {
            p.move(to: CGPoint(x: cx - half, y: cy - depth / 2))
            p.addLine(to: CGPoint(x: cx + half, y: cy - depth / 2))
            p.addLine(to: CGPoint(x: cx, y: cy + depth / 2))
        } else if mirrored {
            p.move(to: CGPoint(x: cx + depth / 2, y: cy - half))
            p.addLine(to: CGPoint(x: cx + depth / 2, y: cy + half))
            p.addLine(to: CGPoint(x: cx - depth / 2, y: cy))
        } else {
            p.move(to: CGPoint(x: cx - depth / 2, y: cy - half))
            p.addLine(to: CGPoint(x: cx - depth / 2, y: cy + half))
            p.addLine(to: CGPoint(x: cx + depth / 2, y: cy))
        }
        p.closeSubpath()
        return p
    }
}

/// A button showing the triangle; its action toggles the expansion.
struct _DisclosureTriangle: View {
    @Environment(\.layoutDirection) private var layoutDirection
    let isExpanded: Bool
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            _DisclosureTriangleShape(expanded: isExpanded, mirrored: layoutDirection == .rightToLeft)
                .fill(Color(nsColor: .secondaryLabelColor))
                .frame(width: 12, height: 12)
        }
        .accessibilityLabel(Text(isExpanded ? "collapse" : "expand"))
    }
}

// MARK: DisclosureGroup

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/disclosuregroup
public struct DisclosureGroup<Label: View, Content: View>: View {
    @State private var internalExpanded = false
    let isExpanded: Binding<Bool>?
    let label: Label
    let content: Content

    public init(isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content, @ViewBuilder label: () -> Label) {
        self.isExpanded = isExpanded
        self.content = content()
        self.label = label()
    }
    public init(@ViewBuilder content: @escaping () -> Content, @ViewBuilder label: () -> Label) {
        isExpanded = nil
        self.content = content()
        self.label = label()
    }

    private var expanded: Bool { isExpanded?.wrappedValue ?? internalExpanded }
    private func toggle() {
        if let b = isExpanded { b.wrappedValue.toggle() } else { internalExpanded.toggle() }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                _DisclosureTriangle(isExpanded: expanded, toggle: toggle)
                label
            }
            if expanded {
                content.padding(.leading, 18)
            }
        }
    }
}

extension DisclosureGroup where Label == Text {
    public init(_ titleKey: LocalizedStringKey, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.init(isExpanded: isExpanded, content: content, label: { Text(titleKey) })
    }
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.init(content: content, label: { Text(titleKey) })
    }
    public init<S: StringProtocol>(_ label: S, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.init(isExpanded: isExpanded, content: content, label: { Text(label) })
    }
    public init<S: StringProtocol>(_ label: S, @ViewBuilder content: @escaping () -> Content) {
        self.init(content: content, label: { Text(label) })
    }
}

// MARK: OutlineGroup

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/outlinesubgroupchildren
public struct OutlineSubgroupChildren: View {
    public var body: some View { EmptyView() }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/outlinegroup
public struct OutlineGroup<Data, ID, Parent, Leaf, Subgroup>: View, _ListRowsProvider where Data: RandomAccessCollection, ID: Hashable, Parent: View, Leaf: View, Subgroup: View {
    /// One visible node of the tree.
    struct _Node {
        let element: Data.Element
        let key: AnyHashable
        let level: Int
        let hasChildren: Bool
    }

    let roots: [Data.Element]
    let children: KeyPath<Data.Element, Data?>
    let idForElement: (Data.Element) -> ID
    let leaf: (Data.Element) -> Leaf
    @State private var expanded: Set<AnyHashable> = []

    init(roots: [Data.Element], id: @escaping (Data.Element) -> ID, children: KeyPath<Data.Element, Data?>, content: @escaping (Data.Element) -> Leaf) {
        self.roots = roots
        self.children = children
        idForElement = id
        leaf = content
    }

    /// The expanded part of the tree, depth first.
    var visibleNodes: [_Node] {
        var out: [_Node] = []
        func visit(_ elements: [Data.Element], level: Int) {
            for e in elements {
                let kids = e[keyPath: children]
                let key = AnyHashable(idForElement(e))
                out.append(_Node(element: e, key: key, level: level, hasChildren: kids != nil))
                if let kids, expanded.contains(key) { visit(Array(kids), level: level + 1) }
            }
        }
        visit(roots, level: 0)
        return out
    }

    private func toggle(_ key: AnyHashable) {
        if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
    }

    public var body: some View {
        ForEach(visibleNodes, id: \.key) { node in
            HStack(spacing: 6) {
                if node.hasChildren {
                    _DisclosureTriangle(isExpanded: expanded.contains(node.key), toggle: { toggle(node.key) })
                } else {
                    Spacer().frame(width: 12, height: 12)
                }
                leaf(node.element)
                Spacer(minLength: 0)        // rows keep their leading alignment in a wide list
            }
            .padding(.leading, CGFloat(node.level) * 18)
        }
    }
}

extension OutlineGroup where ID == Data.Element.ID, Parent: View, Parent == Leaf, Subgroup == DisclosureGroup<Parent, OutlineSubgroupChildren>, Data.Element: Identifiable {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/outlinegroup/init(_:children:content:)
    public init(_ root: Data.Element, children: KeyPath<Data.Element, Data?>, @ViewBuilder content: @escaping (Data.Element) -> Leaf) {
        self.init(roots: [root], id: { $0.id }, children: children, content: content)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/outlinegroup/init(_:children:content:)
    public init(_ data: Data, children: KeyPath<Data.Element, Data?>, @ViewBuilder content: @escaping (Data.Element) -> Leaf) {
        self.init(roots: Array(data), id: { $0.id }, children: children, content: content)
    }
}

extension OutlineGroup where Parent: View, Parent == Leaf, Subgroup == DisclosureGroup<Parent, OutlineSubgroupChildren> {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/outlinegroup/init(_:id:children:content:)
    public init(_ root: Data.Element, id: KeyPath<Data.Element, ID>, children: KeyPath<Data.Element, Data?>, @ViewBuilder content: @escaping (Data.Element) -> Leaf) {
        self.init(roots: [root], id: { $0[keyPath: id] }, children: children, content: content)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/outlinegroup/init(_:id:children:content:)
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, children: KeyPath<Data.Element, Data?>, @ViewBuilder content: @escaping (Data.Element) -> Leaf) {
        self.init(roots: Array(data), id: { $0[keyPath: id] }, children: children, content: content)
    }
}

// MARK: List over a tree

extension List where SelectionValue == Never {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/list/init(_:children:rowcontent:)
    public init<Data: RandomAccessCollection, RowContent: View>(_ data: Data, children: KeyPath<Data.Element, Data?>, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent)
    where Content == OutlineGroup<Data, Data.Element.ID, RowContent, RowContent, DisclosureGroup<RowContent, OutlineSubgroupChildren>>, Data.Element: Identifiable {
        content = OutlineGroup(data, children: children, content: rowContent); selection = nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/list/init(_:id:children:rowcontent:)
    public init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(_ data: Data, id: KeyPath<Data.Element, ID>, children: KeyPath<Data.Element, Data?>, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent)
    where Content == OutlineGroup<Data, ID, RowContent, RowContent, DisclosureGroup<RowContent, OutlineSubgroupChildren>> {
        content = OutlineGroup(data, id: id, children: children, content: rowContent); selection = nil
    }
}

extension List {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/list/init(_:children:selection:rowcontent:)
    public init<Data: RandomAccessCollection, RowContent: View>(_ data: Data, children: KeyPath<Data.Element, Data?>, selection: Binding<SelectionValue?>?, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent)
    where Content == OutlineGroup<Data, Data.Element.ID, RowContent, RowContent, DisclosureGroup<RowContent, OutlineSubgroupChildren>>, Data.Element: Identifiable, Data.Element.ID == SelectionValue {
        content = OutlineGroup(data, children: children, content: rowContent); self.selection = selection.map { _ListSelection(single: $0) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/list/init(_:children:selection:rowcontent:)
    public init<Data: RandomAccessCollection, RowContent: View>(_ data: Data, children: KeyPath<Data.Element, Data?>, selection: Binding<Set<SelectionValue>>?, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent)
    where Content == OutlineGroup<Data, Data.Element.ID, RowContent, RowContent, DisclosureGroup<RowContent, OutlineSubgroupChildren>>, Data.Element: Identifiable, Data.Element.ID == SelectionValue {
        content = OutlineGroup(data, children: children, content: rowContent); self.selection = selection.map { _ListSelection(multiple: $0) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/list/init(_:id:children:selection:rowcontent:)
    public init<Data: RandomAccessCollection, RowContent: View>(_ data: Data, id: KeyPath<Data.Element, SelectionValue>, children: KeyPath<Data.Element, Data?>, selection: Binding<SelectionValue?>?, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent)
    where Content == OutlineGroup<Data, SelectionValue, RowContent, RowContent, DisclosureGroup<RowContent, OutlineSubgroupChildren>> {
        content = OutlineGroup(data, id: id, children: children, content: rowContent); self.selection = selection.map { _ListSelection(single: $0) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/list/init(_:id:children:selection:rowcontent:)
    public init<Data: RandomAccessCollection, RowContent: View>(_ data: Data, id: KeyPath<Data.Element, SelectionValue>, children: KeyPath<Data.Element, Data?>, selection: Binding<Set<SelectionValue>>?, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent)
    where Content == OutlineGroup<Data, SelectionValue, RowContent, RowContent, DisclosureGroup<RowContent, OutlineSubgroupChildren>> {
        content = OutlineGroup(data, id: id, children: children, content: rowContent); self.selection = selection.map { _ListSelection(multiple: $0) }
    }
}
