// NSViewRepresentable and NSViewControllerRepresentable: AppKit views inside SwiftUI.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/nsviewrepresentable
@MainActor @preconcurrency
public protocol NSViewRepresentable: View where Body == Never {
    associatedtype NSViewType: NSView
    associatedtype Coordinator = Void
    typealias Context = NSViewRepresentableContext<Self>
    func makeNSView(context: Context) -> NSViewType
    func updateNSView(_ nsView: NSViewType, context: Context)
    static func dismantleNSView(_ nsView: NSViewType, coordinator: Coordinator)
    func makeCoordinator() -> Coordinator
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSViewType, context: Context) -> CGSize?
}

extension NSViewRepresentable {
    public static func dismantleNSView(_ nsView: NSViewType, coordinator: Coordinator) {}
    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSViewType, context: Context) -> CGSize? { nil }
    public var body: Never { fatalError() }
}

extension NSViewRepresentable where Coordinator == Void {
    public func makeCoordinator() -> Void { () }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/nsviewrepresentablecontext
@MainActor
public struct NSViewRepresentableContext<Representable: NSViewRepresentable> {
    public let coordinator: Representable.Coordinator
    public var environment: EnvironmentValues
    public var transaction: Transaction
    init(coordinator: Representable.Coordinator, environment: EnvironmentValues) {
        self.coordinator = coordinator
        self.environment = environment
        transaction = Transaction()
    }
}

extension NSViewRepresentable {
    public func _makePrimitive(node: _ViewNode) -> _Primitive { _RepresentablePrimitive(self) }
}

@MainActor
final class _RepresentablePrimitive<R: NSViewRepresentable>: _Primitive {
    var representable: R
    var coordinator: R.Coordinator?
    var view: R.NSViewType?
    init(_ r: R) { representable = r }
    override var nsView: NSView? { view }
    private func context(_ node: _ViewNode?) -> NSViewRepresentableContext<R> {
        if coordinator == nil { coordinator = representable.makeCoordinator() }
        return NSViewRepresentableContext(coordinator: coordinator!, environment: node?.environment ?? EnvironmentValues())
    }
    override func attach(to node: _ViewNode) {
        super.attach(to: node)
        let v = representable.makeNSView(context: context(node))
        view = v
        representable.updateNSView(v, context: context(node))
    }
    override func detach() {
        if let v = view, let c = coordinator { R.dismantleNSView(v, coordinator: c) }
        view?.removeFromSuperview()
        view = nil
    }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _RepresentablePrimitive<R> else { return }
        representable = o.representable
        if let v = view { representable.updateNSView(v, context: context(node)) }
    }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        guard let v = view else { return .zero }
        if let s = representable.sizeThatFits(proposal, nsView: v, context: context(node)) { return s }
        let i = v.intrinsicContentSize
        let fit = v.fittingSize
        return CGSize(width: i.width == NSView.noIntrinsicMetric ? (proposal.width.map { $0.isFinite ? $0 : fit.width } ?? fit.width) : i.width,
                      height: i.height == NSView.noIntrinsicMetric ? (proposal.height.map { $0.isFinite ? $0 : fit.height } ?? fit.height) : i.height)
    }
    override func place(node: _ViewNode, in rect: CGRect) {}
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/nsviewcontrollerrepresentable
@MainActor @preconcurrency
public protocol NSViewControllerRepresentable: View where Body == Never {
    associatedtype NSViewControllerType: NSViewController
    associatedtype Coordinator = Void
    typealias Context = NSViewControllerRepresentableContext<Self>
    func makeNSViewController(context: Context) -> NSViewControllerType
    func updateNSViewController(_ nsViewController: NSViewControllerType, context: Context)
    static func dismantleNSViewController(_ nsViewController: NSViewControllerType, coordinator: Coordinator)
    func makeCoordinator() -> Coordinator
    func sizeThatFits(_ proposal: ProposedViewSize, nsViewController: NSViewControllerType, context: Context) -> CGSize?
}

extension NSViewControllerRepresentable {
    public static func dismantleNSViewController(_ nsViewController: NSViewControllerType, coordinator: Coordinator) {}
    public func sizeThatFits(_ proposal: ProposedViewSize, nsViewController: NSViewControllerType, context: Context) -> CGSize? { nil }
    public var body: Never { fatalError() }
}

extension NSViewControllerRepresentable where Coordinator == Void {
    public func makeCoordinator() -> Void { () }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/nsviewcontrollerrepresentablecontext
@MainActor
public struct NSViewControllerRepresentableContext<Representable: NSViewControllerRepresentable> {
    public let coordinator: Representable.Coordinator
    public var environment: EnvironmentValues
    public var transaction: Transaction
    init(coordinator: Representable.Coordinator, environment: EnvironmentValues) {
        self.coordinator = coordinator
        self.environment = environment
        transaction = Transaction()
    }
}

extension NSViewControllerRepresentable {
    public func _makePrimitive(node: _ViewNode) -> _Primitive { _ControllerRepresentablePrimitive(self) }
}

@MainActor
final class _ControllerRepresentablePrimitive<R: NSViewControllerRepresentable>: _Primitive {
    var representable: R
    var coordinator: R.Coordinator?
    var controller: R.NSViewControllerType?
    init(_ r: R) { representable = r }
    override var nsView: NSView? { controller?.view }
    private func context(_ node: _ViewNode?) -> NSViewControllerRepresentableContext<R> {
        if coordinator == nil { coordinator = representable.makeCoordinator() }
        return NSViewControllerRepresentableContext(coordinator: coordinator!, environment: node?.environment ?? EnvironmentValues())
    }
    override func attach(to node: _ViewNode) {
        super.attach(to: node)
        let c = representable.makeNSViewController(context: context(node))
        controller = c
        _ = c.view
        representable.updateNSViewController(c, context: context(node))
    }
    override func detach() {
        if let c = controller, let co = coordinator { R.dismantleNSViewController(c, coordinator: co) }
        controller?.view.removeFromSuperview()
        controller = nil
    }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _ControllerRepresentablePrimitive<R> else { return }
        representable = o.representable
        if let c = controller { representable.updateNSViewController(c, context: context(node)) }
    }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        guard let c = controller else { return .zero }
        if let s = representable.sizeThatFits(proposal, nsViewController: c, context: context(node)) { return s }
        let p = c.preferredContentSize
        if p != .zero { return p }
        let fit = c.view.fittingSize
        return CGSize(width: proposal.width.map { $0.isFinite ? $0 : fit.width } ?? fit.width, height: proposal.height.map { $0.isFinite ? $0 : fit.height } ?? fit.height)
    }
    override func place(node: _ViewNode, in rect: CGRect) {}
}
