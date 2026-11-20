// Split containers over AppKit's NSSplitView: HSplitView and VSplitView, NavigationSplitView
// (two or three columns) and the inspector column.
//
// Each column is a pane: a flipped NSView that holds the column's backing views, so the
// split view's arranged subviews are exactly the panes. SwiftUI's layout decides the pane
// sizes (each column's minimum, ideal and maximum along the split axis, one column taking
// up the slack); the split view draws the dividers and moves them under the pointer, and a
// moved divider becomes the columns' new sizes for the next layout pass.

import Foundation

// MARK: Column widths

/// Which split container a column width modifier speaks to.
enum _SplitColumnWidthKind { case navigation, inspector }

/// `.navigationSplitViewColumnWidth` / `.inspectorColumnWidth`: a transparent wrapper the
/// enclosing split container finds in its column.
struct _SplitColumnWidth<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let kind: _SplitColumnWidthKind
    let min: CGFloat?, ideal: CGFloat, max: CGFloat?
    func _makePrimitive(node: _ViewNode) -> _Primitive {
        _SplitColumnWidthPrimitive(kind: kind, min: min, ideal: ideal, max: max, content: _ViewBox(content))
    }
}

@MainActor
final class _SplitColumnWidthPrimitive: _Primitive {
    var kind: _SplitColumnWidthKind
    var min: CGFloat?, ideal: CGFloat, max: CGFloat?
    init(kind: _SplitColumnWidthKind, min: CGFloat?, ideal: CGFloat, max: CGFloat?, content: _AnyViewBox) {
        self.kind = kind; self.min = min; self.ideal = ideal; self.max = max
        super.init()
        children = [content]
    }
    override var isLayoutTransparent: Bool { true }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _SplitColumnWidthPrimitive else { return }
        kind = o.kind; min = o.min; ideal = o.ideal; max = o.max
    }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/navigationsplitviewcolumnwidth(_:)
    /// A fixed width: the column's minimum, ideal and maximum.
    public func navigationSplitViewColumnWidth(_ width: CGFloat) -> some View {
        _SplitColumnWidth(content: self, kind: .navigation, min: width, ideal: width, max: width)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/navigationsplitviewcolumnwidth(min:ideal:max:)
    public func navigationSplitViewColumnWidth(min: CGFloat? = nil, ideal: CGFloat, max: CGFloat? = nil) -> some View {
        _SplitColumnWidth(content: self, kind: .navigation, min: min, ideal: ideal, max: max)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/inspectorcolumnwidth(_:)
    public func inspectorColumnWidth(_ width: CGFloat) -> some View {
        _SplitColumnWidth(content: self, kind: .inspector, min: width, ideal: width, max: width)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/inspectorcolumnwidth(min:ideal:max:)
    public func inspectorColumnWidth(min: CGFloat? = nil, ideal: CGFloat, max: CGFloat? = nil) -> some View {
        _SplitColumnWidth(content: self, kind: .inspector, min: min, ideal: ideal, max: max)
    }
}

// MARK: Panes

/// What a pane is, which decides its default width range.
enum _SplitPaneRole {
    /// An HSplitView/VSplitView child, or the content beside an inspector: its range is
    /// its content's (minimum, ideal and maximum size along the axis).
    case measured
    /// A navigation split view's sidebar or content column (a column width modifier
    /// inside sets the range; else the defaults).
    case column(defaults: (min: CGFloat, ideal: CGFloat, max: CGFloat))
    /// The inspector column.
    case inspector
}

/// One pane of a split container: its own flipped view, so the split view arranges exactly
/// the panes and each column's views stay inside it.
struct _SplitPane: View, _PrimitiveView {
    typealias Body = Never
    let box: _AnyViewBox
    /// The navigation split view's sidebar column (its pane draws the sidebar material).
    var isSidebar = false
    func _makePrimitive(node: _ViewNode) -> _Primitive { _SplitPanePrimitive(content: box, isSidebar: isSidebar) }
}

@MainActor
final class _SplitPaneView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    /// The navigation split view's sidebar column: with Liquid Glass on it draws the
    /// sidebar material under its list (ADR-0051); off, nothing, as before.
    var isSidebar = false { didSet { if isSidebar != oldValue { needsDisplay = true } } }
    override func draw(_ dirtyRect: NSRect) {
        guard isSidebar else { return }
        _MaterialBackground.draw(.sidebar, in: bounds, of: self)
    }
}

@MainActor
final class _SplitPanePrimitive: _Primitive {
    private(set) lazy var view: _SplitPaneView = {
        let v = _SplitPaneView(frame: .zero)
        v.clipsToBounds = true
        return v
    }()
    init(content: _AnyViewBox, isSidebar: Bool = false) {
        super.init()
        children = [content]
        if isSidebar { view.isSidebar = true }
    }
    override var nsView: NSView? { view }
    /// The column's content fills the pane (a list, a form), or sits centred in it when it
    /// is smaller (a placeholder text), as in SwiftUI.
    override func place(node: _ViewNode, in rect: CGRect) {
        for l in node.children.flatMap(\.layoutLeaves) {
            let s = l.sizeThatFits(ProposedViewSize(rect.size))
            let w = min(s.width, rect.width), h = min(s.height, rect.height)
            l.place(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h).integralIfNeeded)
        }
    }
}

// MARK: Split view

/// The split view of a SwiftUI split container. SwiftUI sizes the panes; a divider the user
/// drags is clamped to the columns' ranges and reported back.
@MainActor
final class _SwiftUISplitView: NSSplitView {
    weak var owner: _SplitPrimitive?
    /// SwiftUI's layout sizes the panes (a resize would otherwise hand the difference to the
    /// lowest holding priority before the layout pass decides).
    override func resizeSubviews(withOldSize oldSize: NSSize) {}
    override func setPosition(_ position: CGFloat, ofDividerAt dividerIndex: Int) {
        let p = owner?.constrain(position, ofDividerAt: dividerIndex, in: self) ?? position
        super.setPosition(p, ofDividerAt: dividerIndex)
        owner?.dividerDidMove(in: self)
    }
}

/// The runtime object behind every split container: its children are panes (keyed by their
/// box ids), one of which takes up the slack when the container resizes.
@MainActor
final class _SplitPrimitive: _Primitive {
    /// Side by side (`NSSplitView.isVertical`, a vertical divider) or stacked.
    var sideBySide: Bool
    var roles: [AnyHashable: _SplitPaneRole]
    /// The key of the pane that grows and shrinks with the container.
    var flexibleKey: AnyHashable
    /// The current size of each pane along the axis (kept across layouts and set by a
    /// divider drag; a pane that appears starts at its ideal size).
    private var sizes: [AnyHashable: CGFloat] = [:]
    private var ranges: [AnyHashable: (min: CGFloat, ideal: CGFloat, max: CGFloat)] = [:]

    private(set) lazy var split: _SwiftUISplitView = {
        let s = _SwiftUISplitView(frame: .zero)
        s.isVertical = sideBySide
        s.dividerStyle = .thin
        s.owner = self
        return s
    }()

    init(sideBySide: Bool, panes: [(key: AnyHashable, role: _SplitPaneRole, box: _AnyViewBox)], flexibleKey: AnyHashable) {
        self.sideBySide = sideBySide
        self.flexibleKey = flexibleKey
        var roles: [AnyHashable: _SplitPaneRole] = [:]
        for p in panes { roles[p.key] = p.role }
        self.roles = roles
        super.init()
        children = panes.map { _ViewBox(_SplitPane(box: $0.box, isSidebar: $0.key == AnyHashable("sidebar")), id: $0.key) }
    }
    override var nsView: NSView? { split }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _SplitPrimitive else { return }
        roles = o.roles; flexibleKey = o.flexibleKey
        if sideBySide != o.sideBySide { sideBySide = o.sideBySide; split.isVertical = sideBySide }
    }
    override func detach() {
        super.detach()
        split.owner = nil
    }

    private var dividerThickness: CGFloat { split.dividerThickness }
    private func along(_ s: CGSize) -> CGFloat { sideBySide ? s.width : s.height }
    private func across(_ s: CGSize) -> CGFloat { sideBySide ? s.height : s.width }
    private func proposal(along a: CGFloat?, across c: CGFloat?) -> ProposedViewSize {
        sideBySide ? ProposedViewSize(width: a, height: c) : ProposedViewSize(width: c, height: a)
    }

    /// The column width modifier for this container inside a pane (not inside a nested
    /// split container, whose columns it describes).
    private func columnWidth(in node: _ViewNode, kind: _SplitColumnWidthKind) -> _SplitColumnWidthPrimitive? {
        if let p = node.primitive as? _SplitColumnWidthPrimitive, p.kind == kind { return p }
        if node.primitive is _SplitPrimitive { return nil }
        for c in node.children { if let f = columnWidth(in: c, kind: kind) { return f } }
        return nil
    }

    /// A pane's range along the axis, measured across the given breadth.
    private func range(of pane: _ViewNode, across breadth: CGFloat?) -> (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        let key = pane.box.id ?? AnyHashable(0)
        func fromModifier(_ kind: _SplitColumnWidthKind, _ d: (min: CGFloat, ideal: CGFloat, max: CGFloat)) -> (CGFloat, CGFloat, CGFloat) {
            guard let w = columnWidth(in: pane, kind: kind) else { return d }
            let lo = w.min ?? Swift.min(d.min, w.ideal), hi = w.max ?? Swift.max(d.max, w.ideal)
            return (lo, Swift.min(Swift.max(w.ideal, lo), hi), Swift.max(hi, lo))
        }
        switch roles[key] ?? .measured {
        case .column(let d): return fromModifier(.navigation, d)
        case .inspector: return fromModifier(.inspector, (200, 270, 400))
        case .measured:
            let lo = along(pane.sizeThatFits(proposal(along: 0, across: breadth)))
            let ideal = along(pane.sizeThatFits(proposal(along: nil, across: breadth)))
            let hi = along(pane.sizeThatFits(proposal(along: .infinity, across: breadth)))
            let mn = lo.isFinite ? Swift.max(0, lo) : 0
            let id = ideal.isFinite ? Swift.max(ideal, mn) : mn
            // The pane that takes up the slack grows past its content (which then sits
            // centred in it), as a split view's last pane or a detail column does.
            if key == flexibleKey { return (mn, id, .infinity) }
            return (mn, id, hi.isFinite ? Swift.max(hi, id) : .infinity)
        }
    }

    override func sizeThatFits(_ p: ProposedViewSize, node: _ViewNode) -> CGSize {
        let panes = node.children
        guard !panes.isEmpty else { return .zero }
        let crossProposal = sideBySide ? p.height : p.width
        let alongProposal = sideBySide ? p.width : p.height
        let r = panes.map { range(of: $0, across: crossProposal) }
        let dividers = CGFloat(panes.count - 1) * dividerThickness
        let lo = r.map(\.min).reduce(0, +) + dividers
        let hi = r.map(\.max).reduce(0, +) + dividers
        let ideal = r.map(\.ideal).reduce(0, +) + dividers
        let a: CGFloat
        if let given = alongProposal { a = given.isFinite ? Swift.min(Swift.max(given, lo), hi) : hi } else { a = ideal }
        let c: CGFloat
        if let given = crossProposal, given.isFinite, given > 0 {
            c = given
        } else {
            c = zip(panes, r).map { across($0.0.sizeThatFits(proposal(along: $0.1.ideal, across: crossProposal))) }.max() ?? 0
        }
        return sideBySide ? CGSize(width: a, height: c) : CGSize(width: c, height: a)
    }

    override func place(node: _ViewNode, in rect: CGRect) {
        let panes = node.children
        guard !panes.isEmpty else { return }
        let keys = panes.map { $0.box.id ?? AnyHashable(0) }
        let breadth = across(rect.size)
        var r: [(min: CGFloat, ideal: CGFloat, max: CGFloat)] = []
        for (k, p) in zip(keys, panes) { let x = range(of: p, across: breadth); r.append(x); ranges[k] = x }
        let available = Swift.max(0, along(rect.size) - CGFloat(panes.count - 1) * dividerThickness)
        var s = keys.indices.map { i in Swift.min(Swift.max(sizes[keys[i]] ?? r[i].ideal, r[i].min), r[i].max).rounded() }
        // The flexible pane takes up the difference first, then the others from the last.
        let flex = keys.firstIndex(of: flexibleKey) ?? keys.count - 1
        var delta = available - s.reduce(0, +)
        for i in [flex] + keys.indices.reversed().filter({ $0 != flex }) where delta != 0 {
            let room = delta > 0 ? r[i].max - s[i] : r[i].min - s[i]
            let take = delta > 0 ? Swift.min(delta, room) : Swift.max(delta, room)
            s[i] += take; delta -= take
        }
        // Ranges that cannot fit (a window narrower than every minimum) overflow the
        // flexible pane rather than leave a gap.
        if delta != 0 { s[flex] = Swift.max(0, s[flex] + delta) }
        var offset = sideBySide ? rect.minX : rect.minY
        for (i, pane) in panes.enumerated() {
            sizes[keys[i]] = s[i]
            let f = sideBySide ? CGRect(x: offset, y: rect.minY, width: s[i], height: rect.height)
                               : CGRect(x: rect.minX, y: offset, width: rect.width, height: s[i])
            pane.place(in: f)
            offset += s[i] + dividerThickness
        }
    }

    /// The panes in tree order (a pane shown again, say a sidebar, is added last by the
    /// backing-view sync), then the split view recomputes its dividers from their frames.
    /// The split's size and pane frames after its last arrangement: a pass that changes
    /// neither leaves the split alone (arranging marks the whole split for display, and a
    /// 50 Hz meter in a pane re-ran this on every tick).
    private var arranged: (size: CGSize, panes: [ObjectIdentifier], frames: [CGRect], hidden: [Bool])?

    override func didSyncBackingViews(node: _ViewNode) {
        let want = node.children.compactMap(\.backingView)
        let have = split.subviews.filter { v in want.contains { $0 === v } }
        let reordered = have.map(ObjectIdentifier.init) != want.map(ObjectIdentifier.init)
        if reordered {
            for v in want { v.removeFromSuperview() }
            for v in want { split.addSubview(v) }
        }
        if !reordered, let a = arranged, a.size == split.bounds.size,
           a.panes == want.map(ObjectIdentifier.init), a.frames == want.map(\.frame), a.hidden == want.map(\.isHidden) { return }
        split.needsLayout = true
        split.layoutSubtreeIfNeeded()
        if reordered || arranged == nil { split.needsDisplay = true }
        arranged = (split.bounds.size, want.map(ObjectIdentifier.init), want.map(\.frame), want.map(\.isHidden))
    }

    // MARK: Divider drags

    /// Keeps a dragged divider inside both neighbouring panes' ranges.
    func constrain(_ position: CGFloat, ofDividerAt index: Int, in split: NSSplitView) -> CGFloat {
        guard let node else { return position }
        let views = split.arrangedSubviews
        guard index >= 0, index + 1 < views.count, index + 1 < node.children.count else { return position }
        let k0 = node.children[index].box.id ?? AnyHashable(0), k1 = node.children[index + 1].box.id ?? AnyHashable(0)
        guard let r0 = ranges[k0], let r1 = ranges[k1] else { return position }
        let start = sideBySide ? views[index].frame.minX : views[index].frame.minY
        let end = sideBySide ? views[index + 1].frame.maxX : views[index + 1].frame.maxY
        let lo = Swift.max(start + r0.min, end - dividerThickness - r1.max)
        let hi = Swift.min(start + r0.max, end - dividerThickness - r1.min)
        guard lo <= hi else { return sideBySide ? views[index].frame.maxX : views[index].frame.maxY }
        return Swift.min(Swift.max(position, lo), hi)
    }

    /// A divider moved: the panes' new sizes are kept and the columns lay out again.
    func dividerDidMove(in split: NSSplitView) {
        guard let node else { return }
        for pane in node.children {
            guard let v = pane.backingView else { continue }
            sizes[pane.box.id ?? AnyHashable(0)] = sideBySide ? v.frame.width : v.frame.height
        }
        node.invalidateMeasurement()
    }

    /// The current pane sizes (tests).
    var _paneSizes: [CGFloat] { node?.children.map { sizes[$0.box.id ?? AnyHashable(0)] ?? 0 } ?? [] }
}

// MARK: HSplitView / VSplitView

/// The children of a split view's content, one per pane.
@MainActor
private func _splitChildren(_ content: _AnyViewBox) -> [(key: AnyHashable, role: _SplitPaneRole, box: _AnyViewBox)] {
    _flattenBoxes(content).enumerated().map { (key: AnyHashable("pane.\($0.offset)"), role: .measured, box: $0.element) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/hsplitview
/// Its children side by side over an `NSSplitView` with vertical dividers the user drags;
/// each child keeps to its own minimum and maximum width (`.frame(minWidth:maxWidth:)`),
/// and the last one takes up the slack when the container resizes.
public struct HSplitView<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public func _makePrimitive(node: _ViewNode) -> _Primitive {
        let panes = _splitChildren(_ViewBox(content))
        return _SplitPrimitive(sideBySide: true, panes: panes, flexibleKey: panes.last?.key ?? AnyHashable("pane.0"))
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/vsplitview
/// Its children stacked over an `NSSplitView` with horizontal dividers (see `HSplitView`).
public struct VSplitView<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public func _makePrimitive(node: _ViewNode) -> _Primitive {
        let panes = _splitChildren(_ViewBox(content))
        return _SplitPrimitive(sideBySide: false, panes: panes, flexibleKey: panes.last?.key ?? AnyHashable("pane.0"))
    }
}

// MARK: NavigationSplitView

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/navigationsplitviewvisibility
public struct NavigationSplitViewVisibility: Equatable, Codable, Sendable {
    let raw: String
    public static var detailOnly: NavigationSplitViewVisibility { NavigationSplitViewVisibility(raw: "detailOnly") }
    public static var doubleColumn: NavigationSplitViewVisibility { NavigationSplitViewVisibility(raw: "doubleColumn") }
    public static var all: NavigationSplitViewVisibility { NavigationSplitViewVisibility(raw: "all") }
    public static var automatic: NavigationSplitViewVisibility { NavigationSplitViewVisibility(raw: "automatic") }
    public func encode(to encoder: any Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(raw) }
    public init(from decoder: any Decoder) throws { raw = try decoder.singleValueContainer().decode(String.self) }
    init(raw: String) { self.raw = raw }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/navigationsplitviewcolumn
public struct NavigationSplitViewColumn: Hashable, Sendable {
    let raw: Int
    public static var sidebar: NavigationSplitViewColumn { NavigationSplitViewColumn(raw: 0) }
    public static var content: NavigationSplitViewColumn { NavigationSplitViewColumn(raw: 1) }
    public static var detail: NavigationSplitViewColumn { NavigationSplitViewColumn(raw: 2) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/navigationsplitview
/// Columns side by side over an `NSSplitView` with thin vertical dividers: the sidebar (and
/// the content column) at their ideal widths, 200 (and 250) points unless a
/// `.navigationSplitViewColumnWidth` inside says otherwise, within their minimum and maximum
/// as the user drags; the detail takes the rest. `columnVisibility` hides columns
/// (`.detailOnly`; `.doubleColumn` hides a three-column view's sidebar). Not built: the
/// toolbar's sidebar toggle, collapsing a column by dragging past its minimum, and the
/// translucent sidebar material. `preferredCompactColumn` has no effect on macOS.
public struct NavigationSplitView<Sidebar: View, Content: View, Detail: View>: View, _PrimitiveView {
    public typealias Body = Never
    let sidebar: Sidebar
    let content: Content?
    let detail: Detail
    let columnVisibility: Binding<NavigationSplitViewVisibility>?

    public init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content, @ViewBuilder detail: () -> Detail) {
        self.sidebar = sidebar(); self.content = content(); self.detail = detail(); columnVisibility = nil
    }
    public init(columnVisibility: Binding<NavigationSplitViewVisibility>, @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content, @ViewBuilder detail: () -> Detail) {
        self.sidebar = sidebar(); self.content = content(); self.detail = detail(); self.columnVisibility = columnVisibility
    }
    public init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) where Content == EmptyView {
        self.sidebar = sidebar(); content = nil; self.detail = detail(); columnVisibility = nil
    }
    public init(columnVisibility: Binding<NavigationSplitViewVisibility>, @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) where Content == EmptyView {
        self.sidebar = sidebar(); content = nil; self.detail = detail(); self.columnVisibility = columnVisibility
    }
    public init(preferredCompactColumn: Binding<NavigationSplitViewColumn>, @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content, @ViewBuilder detail: () -> Detail) {
        self.init(sidebar: sidebar, content: content, detail: detail)
    }
    public init(columnVisibility: Binding<NavigationSplitViewVisibility>, preferredCompactColumn: Binding<NavigationSplitViewColumn>, @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content, @ViewBuilder detail: () -> Detail) {
        self.init(columnVisibility: columnVisibility, sidebar: sidebar, content: content, detail: detail)
    }
    public init(preferredCompactColumn: Binding<NavigationSplitViewColumn>, @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) where Content == EmptyView {
        self.init(sidebar: sidebar, detail: detail)
    }
    public init(columnVisibility: Binding<NavigationSplitViewVisibility>, preferredCompactColumn: Binding<NavigationSplitViewColumn>, @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) where Content == EmptyView {
        self.init(columnVisibility: columnVisibility, sidebar: sidebar, detail: detail)
    }

    public func _makePrimitive(node: _ViewNode) -> _Primitive {
        let visibility = columnVisibility?.wrappedValue ?? .automatic
        var panes: [(key: AnyHashable, role: _SplitPaneRole, box: _AnyViewBox)] = []
        if visibility != .detailOnly {
            if content == nil || visibility != .doubleColumn {
                // A list in the sidebar column takes the sidebar style.
                panes.append((AnyHashable("sidebar"), .column(defaults: (150, 200, 400)), _ViewBox(sidebar.environment(\._inSidebarColumn, true))))
            }
            if let content { panes.append((AnyHashable("content"), .column(defaults: (150, 250, 400)), _ViewBox(content))) }
        }
        panes.append((AnyHashable("detail"), .measured, _ViewBox(detail)))
        return _SplitPrimitive(sideBySide: true, panes: panes, flexibleKey: AnyHashable("detail"))
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/navigationsplitviewstyleconfiguration
public struct NavigationSplitViewStyleConfiguration {}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/navigationsplitviewstyle
/// The port lays out every navigation split view the same way (on macOS `.balanced` and
/// `.prominentDetail` look alike: the columns sit side by side), so a style is accepted and
/// has no effect, and the built-in styles' `makeBody` is not used.
@MainActor @preconcurrency
public protocol NavigationSplitViewStyle {
    associatedtype Body: View
    @ViewBuilder @MainActor func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = NavigationSplitViewStyleConfiguration
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/automaticnavigationsplitviewstyle
public struct AutomaticNavigationSplitViewStyle: NavigationSplitViewStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> Never { unimplemented("AutomaticNavigationSplitViewStyle.makeBody (the port lays out NavigationSplitView itself)") }
}
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/balancednavigationsplitviewstyle
public struct BalancedNavigationSplitViewStyle: NavigationSplitViewStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> Never { unimplemented("BalancedNavigationSplitViewStyle.makeBody (the port lays out NavigationSplitView itself)") }
}
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/prominentdetailnavigationsplitviewstyle
public struct ProminentDetailNavigationSplitViewStyle: NavigationSplitViewStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> Never { unimplemented("ProminentDetailNavigationSplitViewStyle.makeBody (the port lays out NavigationSplitView itself)") }
}
extension NavigationSplitViewStyle where Self == AutomaticNavigationSplitViewStyle {
    public static var automatic: AutomaticNavigationSplitViewStyle { AutomaticNavigationSplitViewStyle() }
}
extension NavigationSplitViewStyle where Self == BalancedNavigationSplitViewStyle {
    public static var balanced: BalancedNavigationSplitViewStyle { BalancedNavigationSplitViewStyle() }
}
extension NavigationSplitViewStyle where Self == ProminentDetailNavigationSplitViewStyle {
    public static var prominentDetail: ProminentDetailNavigationSplitViewStyle { ProminentDetailNavigationSplitViewStyle() }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/navigationsplitviewstyle(_:)
    /// Accepted; no effect (see `NavigationSplitViewStyle`).
    public func navigationSplitViewStyle<S: NavigationSplitViewStyle>(_ style: S) -> some View { self }
}

// MARK: Inspector

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/inspector(ispresented:content:)
    /// A trailing column beside this view while `isPresented` is true, behind a thin
    /// divider the user drags: 270 points wide unless an `.inspectorColumnWidth` inside the
    /// content says otherwise (200 to 400 by default). This view takes up the rest; it keeps
    /// its identity and state when the inspector opens and closes. Not animated.
    public func inspector<V: View>(isPresented: Binding<Bool>, @ViewBuilder content: () -> V) -> some View {
        _Inspector(content: self, inspector: content(), isPresented: isPresented)
    }
}

struct _Inspector<Content: View, Inspector: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let inspector: Inspector
    let isPresented: Binding<Bool>
    func _makePrimitive(node: _ViewNode) -> _Primitive {
        var panes: [(key: AnyHashable, role: _SplitPaneRole, box: _AnyViewBox)] = [(AnyHashable("inspector.content"), .measured, _ViewBox(content))]
        if isPresented.wrappedValue { panes.append((AnyHashable("inspector"), .inspector, _ViewBox(inspector))) }
        return _SplitPrimitive(sideBySide: true, panes: panes, flexibleKey: AnyHashable("inspector.content"))
    }
}
