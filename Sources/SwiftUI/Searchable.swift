// `.searchable`: an NSSearchField bound to the text, in the window's toolbar (the trailing
// end, as macOS places a search field) or above the modified view.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/searchfieldplacement
public struct SearchFieldPlacement: Sendable {
    enum Kind: Sendable { case automatic, toolbar, toolbarPrincipal, sidebar }
    let kind: Kind
    public static let automatic = SearchFieldPlacement(kind: .automatic)
    public static let toolbar = SearchFieldPlacement(kind: .toolbar)
    public static var toolbarPrincipal: SearchFieldPlacement { SearchFieldPlacement(kind: .toolbarPrincipal) }
    public static var sidebar: SearchFieldPlacement { SearchFieldPlacement(kind: .sidebar) }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/searchable(text:placement:prompt:)-18a8f
    /// An `NSSearchField` bound to `text` (updated as the user types; its cancel button and
    /// Escape clear it). `.automatic` and `.toolbar` put it at the trailing end of the
    /// window's toolbar, `.toolbarPrincipal` in the toolbar's centre; `.sidebar` puts it
    /// above this view (not inside a navigation split view's sidebar column). The prompt is
    /// the field's placeholder ("Search" when nil). Suggestions and tokens are not built.
    public func searchable(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil) -> some View {
        _Searchable(content: self, text: text, placement: placement, prompt: prompt?._string ?? "Search")
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/searchable(text:placement:prompt:)-co5e
    public func searchable(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: LocalizedStringKey) -> some View {
        _Searchable(content: self, text: text, placement: placement, prompt: Text(prompt)._string)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/searchable(text:placement:prompt:)-6royb
    @_disfavoredOverload
    public func searchable<S: StringProtocol>(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: S) -> some View {
        _Searchable(content: self, text: text, placement: placement, prompt: String(prompt))
    }
}

struct _Searchable<Content: View>: View {
    let content: Content
    let text: Binding<String>
    let placement: SearchFieldPlacement
    let prompt: String

    var body: some View {
        switch placement.kind {
        case .sidebar:
            VStack(spacing: 0) {
                _SearchField(text: text, prompt: prompt).padding(8)
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .automatic, .toolbar, .toolbarPrincipal:
            content.toolbar {
                ToolbarItem(placement: placement.kind == .toolbarPrincipal ? .principal : .automatic) {
                    _SearchField(text: text, prompt: prompt)
                }
            }
        }
    }
}

/// The search field itself: a text field primitive over `NSSearchField`.
struct _SearchField: View, _PrimitiveView {
    typealias Body = Never
    let text: Binding<String>
    let prompt: String
    func _makePrimitive(node: _ViewNode) -> _Primitive { _SearchFieldPrimitive(placeholder: prompt, text: text) }
}

@MainActor
final class _SearchFieldPrimitive: _TextFieldPrimitive {
    init(placeholder: String, text: Binding<String>) {
        super.init(placeholder: placeholder, text: text, onCommit: {}, field: NSSearchField(frame: NSRect(x: 0, y: 0, width: 200, height: 22)))
    }
    /// A toolbar's search field is 200 points wide unless offered a width.
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        let s = super.sizeThatFits(proposal, node: node)
        guard proposal.width == nil || proposal.width?.isFinite == false else { return s }
        return CGSize(width: 200, height: s.height)
    }
}
