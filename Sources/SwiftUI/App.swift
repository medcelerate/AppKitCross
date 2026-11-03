// App, Scene and WindowGroup: an App runs NSApplication and opens a window per
// WindowGroup with an NSHostingView of its content.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/scene
public protocol Scene {
    associatedtype Body: Scene
    @SceneBuilder @MainActor var body: Self.Body { get }
}

extension Never: Scene {}

/// What a scene contributes to the running application.
public protocol _PrimitiveScene {
    @MainActor func _makeWindows(app: _AppRunner)
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/scenebuilder
@resultBuilder
public struct SceneBuilder {
    public static func buildBlock<S: Scene>(_ s: S) -> S { s }
    public static func buildBlock<S0: Scene, S1: Scene>(_ s0: S0, _ s1: S1) -> _TupleScene { _TupleScene([s0, s1]) }
    public static func buildBlock<S0: Scene, S1: Scene, S2: Scene>(_ s0: S0, _ s1: S1, _ s2: S2) -> _TupleScene { _TupleScene([s0, s1, s2]) }
    public static func buildBlock<S0: Scene, S1: Scene, S2: Scene, S3: Scene>(_ s0: S0, _ s1: S1, _ s2: S2, _ s3: S3) -> _TupleScene { _TupleScene([s0, s1, s2, s3]) }
}

public struct _TupleScene: Scene, _PrimitiveScene {
    public typealias Body = Never
    let scenes: [any Scene]
    init(_ scenes: [any Scene]) { self.scenes = scenes }
    public var body: Never { fatalError() }
    @MainActor public func _makeWindows(app: _AppRunner) { for s in scenes { app.run(scene: s) } }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/windowgroup
public struct WindowGroup<Content: View>: Scene, _PrimitiveScene {
    public typealias Body = Never
    let title: String?
    let id: String?
    let content: () -> Content
    var defaultSize: CGSize? = nil

    public init(@ViewBuilder content: @escaping () -> Content) {
        title = nil; id = nil
        self.content = content
    }
    public init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; id = nil
        self.content = content
    }
    public init(id: String, @ViewBuilder content: @escaping () -> Content) {
        title = nil; self.id = id
        self.content = content
    }
    public init(_ title: String, id: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.id = id
        self.content = content
    }
    public var body: Never { fatalError() }

    @MainActor public func _makeWindows(app: _AppRunner) {
        app.openWindow(title: title ?? app.applicationName, content: content(), defaultSize: defaultSize)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/window
public struct Window<Content: View>: Scene, _PrimitiveScene {
    public typealias Body = Never
    let title: String
    let id: String
    let content: () -> Content
    public init(_ title: String, id: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.id = id; self.content = content
    }
    public var body: Never { fatalError() }
    @MainActor public func _makeWindows(app: _AppRunner) { app.openWindow(title: title, content: content(), defaultSize: nil) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/settings
public struct Settings<Content: View>: Scene, _PrimitiveScene {
    public typealias Body = Never
    let content: () -> Content
    public init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    public var body: Never { fatalError() }
    /// Registers the content: the app menu's "Settings…" item (Cmd-,) opens it in its own window.
    @MainActor public func _makeWindows(app: _AppRunner) {
        let make = content
        app.settingsContent = { AnyView(make()) }
    }
}

extension Scene {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/scene/defaultsize(_:)
    public func defaultSize(_ size: CGSize) -> some Scene { _SizedScene(base: self, size: size) }
    public func defaultSize(width: CGFloat, height: CGFloat) -> some Scene { _SizedScene(base: self, size: CGSize(width: width, height: height)) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/scene/windowstyle(_:)
    public func windowStyle<S: WindowStyle>(_ style: S) -> some Scene { _StyledScene(base: self, hidesTitleBar: style.hidesTitleBar) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/scene/windowresizability(_:)
    public func windowResizability(_ resizability: WindowResizability) -> some Scene { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/scene/commands(content:)
    public func commands<C: Commands>(@CommandsBuilder content: () -> C) -> some Scene { _CommandsScene(base: self, commands: content()) }
}

struct _CommandsScene<Base: Scene, C: Commands>: Scene, _PrimitiveScene {
    typealias Body = Never
    let base: Base
    let commands: C
    var body: Never { fatalError() }
    @MainActor func _makeWindows(app: _AppRunner) {
        app.run(scene: base)
        app.commands.append(commands)
    }
}

struct _SizedScene<Base: Scene>: Scene, _PrimitiveScene {
    typealias Body = Never
    let base: Base
    let size: CGSize
    var body: Never { fatalError() }
    @MainActor func _makeWindows(app: _AppRunner) {
        let previous = app.pendingDefaultSize
        app.pendingDefaultSize = size
        app.run(scene: base)
        app.pendingDefaultSize = previous
    }
}

struct _StyledScene<Base: Scene>: Scene, _PrimitiveScene {
    typealias Body = Never
    let base: Base
    let hidesTitleBar: Bool
    var body: Never { fatalError() }
    @MainActor func _makeWindows(app: _AppRunner) {
        let previous = app.pendingHidesTitleBar
        app.pendingHidesTitleBar = hidesTitleBar
        app.run(scene: base)
        app.pendingHidesTitleBar = previous
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/windowstyle
public protocol WindowStyle { var hidesTitleBar: Bool { get } }
public struct DefaultWindowStyle: WindowStyle { public init() {}; public var hidesTitleBar: Bool { false } }
public struct HiddenTitleBarWindowStyle: WindowStyle { public init() {}; public var hidesTitleBar: Bool { true } }
public struct TitleBarWindowStyle: WindowStyle { public init() {}; public var hidesTitleBar: Bool { false } }
extension WindowStyle where Self == DefaultWindowStyle { public static var automatic: DefaultWindowStyle { DefaultWindowStyle() } }
extension WindowStyle where Self == HiddenTitleBarWindowStyle { public static var hiddenTitleBar: HiddenTitleBarWindowStyle { HiddenTitleBarWindowStyle() } }
extension WindowStyle where Self == TitleBarWindowStyle { public static var titleBar: TitleBarWindowStyle { TitleBarWindowStyle() } }

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/windowresizability
public struct WindowResizability: Sendable {
    public static let automatic = WindowResizability()
    public static let contentSize = WindowResizability()
    public static let contentMinSize = WindowResizability()
}

// MARK: App

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/app
@MainActor
public protocol App {
    associatedtype Body: Scene
    @SceneBuilder var body: Self.Body { get }
    init()
}

extension App {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/app/main()
    public static func main() {
        let app = Self()
        let runner = _AppRunner(name: _AppRunner.defaultName)
        runner.install(app)
        runner.run(scene: app.body)
        runner.installMenuBar()
        NSApplication.shared.run()
    }
}

/// Runs an App: creates the NSApplication, installs the delegate adaptor, opens windows.
@MainActor
public final class _AppRunner {
    public let applicationName: String
    public private(set) var windows: [NSWindow] = []
    var pendingDefaultSize: CGSize? = nil
    var pendingHidesTitleBar = false
    private var delegate: AnyObject?
    /// The Settings scene's content, opened from the app menu.
    var settingsContent: (() -> AnyView)?
    private var settingsWindow: NSWindow?
    /// Commands gathered from the scenes, applied to the menu bar by `installMenuBar`.
    var commands: [any Commands] = []
    /// The first WindowGroup, for File > New Window.
    var primaryWindowGroup: (() -> Void)?

    public init(name: String) { applicationName = name }

    static var defaultName: String {
        let path = CommandLine.arguments.first ?? "App"
        return (path as NSString).lastPathComponent
    }

    func install<A: App>(_ app: A) {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.regular)
        // An @NSApplicationDelegateAdaptor property supplies the delegate.
        for child in Mirror(reflecting: app).children {
            if let adaptor = child.value as? _DelegateAdaptor {
                delegate = adaptor.makeDelegate()
                NSApplication.shared.delegate = delegate as? NSApplicationDelegate
            }
        }
        NSApplication.shared.finishLaunching()
    }

    public func run<S: Scene>(scene: S) {
        if let p = scene as? any _PrimitiveScene {
            p._makeWindows(app: self)
        } else {
            run(scene: scene.body)
        }
    }

    public func run(scene: any Scene) {
        if let p = scene as? any _PrimitiveScene { p._makeWindows(app: self) } else { _runBody(scene) }
    }

    private func _runBody<S: Scene>(_ scene: S) { run(scene: scene.body) }

    /// Builds the standard menu bar (app, File, Edit, View, Window, Help) and applies the
    /// scenes' commands to it. Called once after the scenes ran.
    public func installMenuBar() {
        let builder = _MenuBarBuilder(appName: applicationName, hasSettings: settingsContent != nil, runner: self)
        for c in commands { builder.apply(c) }
        NSApplication.shared.mainMenu = builder.makeMenu()
    }

    /// Opens (or brings forward) the Settings scene's window.
    public func openSettings() {
        if let w = settingsWindow { w.makeKeyAndOrderFront(nil); return }
        guard let make = settingsContent else { return }
        let hosting = NSHostingView(rootView: make())
        let ideal = hosting.sizeThatFits(.unspecified)
        let size = NSSize(width: max(ideal.width, 320), height: max(ideal.height, 200))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "\(applicationName) Settings"
        window.isReleasedWhenClosed = false
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }

    public func openWindow<Content: View>(title: String, content: Content, defaultSize: CGSize?) {
        if primaryWindowGroup == nil {
            let size = defaultSize ?? pendingDefaultSize
            primaryWindowGroup = { [weak self] in self?.openWindow(title: title, content: content, defaultSize: size) }
        }
        let hosting = NSHostingView(rootView: content)
        let ideal = hosting.sizeThatFits(.unspecified)
        var size = defaultSize ?? pendingDefaultSize ?? NSSize(width: max(ideal.width, 300), height: max(ideal.height, 200))
        size.width = max(size.width, ideal.width)
        size.height = max(size.height, ideal.height)
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        if pendingHidesTitleBar { style.insert(.fullSizeContentView) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        if pendingHidesTitleBar { window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden }
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/nsapplicationdelegateadaptor
@propertyWrapper
public struct NSApplicationDelegateAdaptor<DelegateType: NSObject & NSApplicationDelegate>: DynamicProperty, _DelegateAdaptor {
    let box: _DelegateBox<DelegateType>
    public init(_ delegateType: DelegateType.Type = DelegateType.self) { box = _DelegateBox() }
    public var wrappedValue: DelegateType { box.instance }
    func makeDelegate() -> AnyObject { box.instance }
}

@MainActor
protocol _DelegateAdaptor { func makeDelegate() -> AnyObject }

/// On Windows and Linux corelibs' NSObject has no required initializer, so a delegate
/// class adopts this (adding `required init()`) to be created by the adaptor.
public protocol _NSApplicationDelegateConstructible: AnyObject { init() }

final class _DelegateBox<T: NSObject & NSApplicationDelegate> {
    lazy var instance: T = {
        #if canImport(Darwin)
        return T()
        #else
        guard let type = T.self as? any _NSApplicationDelegateConstructible.Type, let d = type.init() as? T else {
            fatalError("\(T.self) must adopt _NSApplicationDelegateConstructible (a required init()) to be used with @NSApplicationDelegateAdaptor on this platform")
        }
        return d
        #endif
    }()
}
