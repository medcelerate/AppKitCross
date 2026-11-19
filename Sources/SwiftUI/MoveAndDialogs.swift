// `onMove(perform:)` on dynamic content (drag reordering in a `List`), and the
// `presenting:` forms of `alert` and `confirmationDialog`.

import Foundation

// MARK: onMove

extension DynamicViewContent {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/dynamicviewcontent/onmove(perform:)
    ///
    /// In a `List`, dragging one of this content's rows up or down shows an insertion line
    /// and, on release, calls the action with the row's offset and the destination offset
    /// (an offset in the data before the move, as `move(fromOffsets:toOffset:)` takes). One
    /// row moves at a time; a nil action leaves the rows fixed.
    public func onMove(perform action: ((IndexSet, Int) -> Void)?) -> some DynamicViewContent {
        _MoveActionContent(base: self, action: action)
    }
}

struct _MoveActionContent<Base: DynamicViewContent>: DynamicViewContent, _PrimitiveView {
    typealias Body = Never
    let base: Base
    let action: ((IndexSet, Int) -> Void)?
    var data: Base.Data { base.data }
    func _makePrimitive(node: _ViewNode) -> _Primitive { _RowMovePrimitive(onMove: action, content: _ViewBox(base)) }
}

/// The content with its move action: a transparent group the list's rows read.
@MainActor
final class _RowMovePrimitive: _Primitive {
    var onMove: ((IndexSet, Int) -> Void)?
    init(onMove: ((IndexSet, Int) -> Void)?, content: _AnyViewBox) {
        self.onMove = onMove
        super.init()
        children = [content]
    }
    override var isLayoutTransparent: Bool { true }
    override func update(from other: _Primitive) {
        super.update(from: other)
        if let o = other as? _RowMovePrimitive { onMove = o.onMove }
    }
}

// MARK: Dialogs presenting data

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:presenting:actions:)-9ibgk
    ///
    /// Shown, like the port's other confirmation dialogs, as an alert sheet; the actions are
    /// built from `data` while it is non-nil.
    public func confirmationDialog<A: View, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?, @ViewBuilder actions: (T) -> A) -> some View {
        _presentingAlert(Text(titleKey)._string, isPresented: isPresented, actions: data.map(actions))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:presenting:actions:)-4l3pu
    @_disfavoredOverload
    public func confirmationDialog<S: StringProtocol, A: View, T>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?, @ViewBuilder actions: (T) -> A) -> some View {
        _presentingAlert(String(title), isPresented: isPresented, actions: data.map(actions))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:presenting:actions:)-2s7pa
    public func confirmationDialog<A: View, T>(_ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?, @ViewBuilder actions: (T) -> A) -> some View {
        _presentingAlert(title._string, isPresented: isPresented, actions: data.map(actions))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:presenting:actions:)-42vot
    public func alert<A: View, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A) -> some View {
        _presentingAlert(Text(titleKey)._string, isPresented: isPresented, actions: data.map(actions))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:presenting:actions:)-3ycso
    @_disfavoredOverload
    public func alert<S: StringProtocol, A: View, T>(_ title: S, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A) -> some View {
        _presentingAlert(String(title), isPresented: isPresented, actions: data.map(actions))
    }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:presenting:actions:message:)-1jcl6
    public func confirmationDialog<A: View, M: View, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?, @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View {
        _presentingAlert(Text(titleKey)._string, isPresented: isPresented, actions: data.map(actions), message: data.map(message))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:presenting:actions:message:)-8y541
    @_disfavoredOverload
    public func confirmationDialog<S: StringProtocol, A: View, M: View, T>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?, @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View {
        _presentingAlert(String(title), isPresented: isPresented, actions: data.map(actions), message: data.map(message))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:presenting:actions:message:)-8fpb1
    public func alert<A: View, M: View, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View {
        _presentingAlert(Text(titleKey)._string, isPresented: isPresented, actions: data.map(actions), message: data.map(message))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:presenting:actions:message:)-3w6jc
    @_disfavoredOverload
    public func alert<S: StringProtocol, A: View, M: View, T>(_ title: S, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View {
        _presentingAlert(String(title), isPresented: isPresented, actions: data.map(actions), message: data.map(message))
    }

    private func _presentingAlert<A: View, M: View>(_ title: String, isPresented: Binding<Bool>, actions: A?, message: M?) -> some View {
        // The message reads as the alert's informative text when it is a `Text`, as elsewhere.
        _AlertModified(content: self, isPresented: isPresented) {
            Alert._fromViews(title: Text(title), actions: AnyView(Group { if let actions { actions } }), message: message as? Text)
        }
    }

    private func _presentingAlert<A: View>(_ title: String, isPresented: Binding<Bool>, actions: A?) -> some View {
        alert(title, isPresented: isPresented) { if let actions { actions } }
    }
}
