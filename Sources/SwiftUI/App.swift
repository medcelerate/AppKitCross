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
        app._runWindowGroup(id: id, title: title ?? app.applicationName, content: content, defaultSize: defaultSize)
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
    /// Opens at launch only as the app's first scene; otherwise `openWindow(id:)` opens it
    /// (WindowActions.swift).
    @MainActor public func _makeWindows(app: _AppRunner) { app._runWindowScene(id: id, title: title, content: content) }
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
        // The Settings scene's content knows where it is: a TabView there draws the
        // Settings tab bar (Navigation.swift), on first open and on every scene re-run.
        app.settingsContent = { AnyView(make().environment(\._isSettingsScene, true)) }
        if app._isUpdatingScenes { app._refreshSettingsWindow() }
    }
}

extension Scene {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/scene/defaultsize(_:)
    public func defaultSize(_ size: CGSize) -> some Scene { _SizedScene(base: self, size: size) }
    public func defaultSize(width: CGFloat, height: CGFloat) -> some Scene { _SizedScene(base: self, size: CGSize(width: width, height: height)) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/scene/windowstyle(_:)
    public func windowStyle<S: WindowStyle>(_ style: S) -> some Scene { _StyledScene(base: self, hidesTitleBar: style.hidesTitleBar) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/scene/windowresizability(_:)
    public func windowResizability(_ resizability: WindowResizability) -> some Scene { _ResizabilityScene(base: self, resizability: resizability) }
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

struct _ResizabilityScene<Base: Scene>: Scene, _PrimitiveScene {
    typealias Body = Never
    let base: Base
    let resizability: WindowResizability
    var body: Never { fatalError() }
    @MainActor func _makeWindows(app: _AppRunner) {
        let previous = app.pendingResizability
        app.pendingResizability = resizability
        app.run(scene: base)
        app.pendingResizability = previous
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/windowresizability
public struct WindowResizability: Sendable, Equatable {
    enum Kind { case automatic, contentSize, contentMinSize }
    let kind: Kind
    public static let automatic = WindowResizability(kind: .automatic)
    public static let contentSize = WindowResizability(kind: .contentSize)
    public static let contentMinSize = WindowResizability(kind: .contentMinSize)
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
        runner._nameIsExecutableStem = _AppRunner.bundleName == nil
        runner.install(app)
        runner._runScenes(of: app)
        // Launching finishes once the scenes exist, as on macOS: the delegate's
        // `applicationDidFinishLaunching` sees the scenes' windows, and a DocumentGroup's
        // document controller opens the files named on the command line, or an untitled
        // document, between the will- and did-finish messages.
        NSApplication.shared.finishLaunching()
        NSApplication.shared.run()
    }
}

/// The Settings scene's window: a dialog that carries no in-window menu bar on Windows
/// and Linux (NSWindow+MenuBar: `_MenuBarExemptWindow`).
final class _SettingsWindow: NSWindow, _MenuBarExemptWindow {}

/// Runs an App: creates the NSApplication, installs the delegate adaptor, opens windows.
@MainActor
public final class _AppRunner {
    public private(set) var applicationName: String
    public private(set) var windows: [NSWindow] = []
    /// The runner of the running App (nil in tests that make their own).
    static weak var _current: _AppRunner?
    /// The name is the executable's file stem, not a bundle's: the main window's navigation
    /// title is a better name and replaces it (`_adoptName`).
    var _nameIsExecutableStem = false
    var pendingDefaultSize: CGSize? = nil
    var pendingHidesTitleBar = false
    /// `.windowToolbarStyle(_:)` for the windows the next scene opens (Toolbar.swift).
    var pendingToolbarStyle: NSWindow.ToolbarStyle = .automatic
    var pendingResizability: WindowResizability = .automatic
    private var delegate: AnyObject?
    /// The Settings scene's content, opened from the app menu.
    var settingsContent: (() -> AnyView)?
    private var settingsWindow: NSWindow?
    /// Commands gathered from the scenes, applied to the menu bar by `installMenuBar`.
    var commands: [any Commands] = []
    /// The first WindowGroup, for File > New Window.
    var primaryWindowGroup: (() -> Void)?
    /// The `Window` and identified `WindowGroup` scenes `openWindow(id:)` opens, and
    /// whether a scene window opened at launch yet (WindowActions.swift).
    var _windowScenes: [String: _WindowScene] = [:]
    var _launchSceneOpened = false
    /// A DocumentGroup ran: the File menu gets the document commands (New, Open, Open
    /// Recent, Save, Save As, Revert) instead of New Window.
    var _hasDocumentGroups = false
    /// The App's own node: its `@State`, `@StateObject`, `@AppStorage` and `@Environment`
    /// properties are installed here as a view's are in its node, and the scene body and
    /// the commands are evaluated under observation tracking against it. A change to any
    /// of them re-runs the scenes in update mode (`_updateScenes`): open windows get their
    /// content re-evaluated and the menu bar is rebuilt, as SwiftUI re-renders a `Window`'s
    /// content and `.commands` when the App's state changes.
    let _appNode = _ViewNode(box: _ViewBox(EmptyView()), parent: nil, root: nil)
    private var _sceneBody: (() -> any Scene)?
    /// True while the scenes re-run for an update: scene kinds then refresh what they
    /// opened instead of opening it again.
    var _isUpdatingScenes = false
    private var _sceneUpdateScheduled = false
    /// Ordinal of the id-less `WindowGroup`s in declaration order, so an update finds them.
    var _windowGroupOrdinal = 0

    public init(name: String) {
        applicationName = name
        _AppRunner._current = self
    }

    /// Renames an app named after its executable (no bundle): the app menu follows.
    func _adoptName(_ name: String) {
        guard _nameIsExecutableStem, !name.isEmpty, name != applicationName else { return }
        applicationName = name
        if NSApplication.shared.mainMenu != nil { installMenuBar() }
    }

    /// The bundle's name: its Info.plist's `CFBundleName` (the app folder's Info.plist,
    /// ADR-0045, including one `APPKITWIN_INFO_PLIST` names), localized by InfoPlist.strings.
    static var bundleName: String? {
        if _AppBundle.main.layout.infoPlistURL != nil, let n = _AppBundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, !n.isEmpty { return n }
        if let n = Bundle.main.infoDictionary?["CFBundleName"] as? String, !n.isEmpty { return n }
        return nil
    }

    /// The bundle's name where there is an Info.plist, else the executable's name without
    /// its extension (Windows executables carry `.exe`; the app menu and window titles
    /// read "DailyTodo", not "DailyTodo.exe").
    static var defaultName: String {
        if let bundleName { return bundleName }
        let path = CommandLine.arguments.first ?? "App"
        let file = (path as NSString).lastPathComponent
        let stem = (file as NSString).deletingPathExtension
        return stem.isEmpty ? file : stem
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
    }

    public func run<S: Scene>(scene: S) {
        if let p = scene as? any _PrimitiveScene {
            p._makeWindows(app: self)
        } else {
            run(scene: scene.body)
        }
    }

    /// Runs an App's scenes for the first time and installs the menu bar; later state
    /// changes re-run them through `_updateScenes`. `App.main()` calls this.
    public func _runScenes<A: App>(of app: A) {
        var slot = 0
        _installDynamicProperties(in: app, node: _appNode, slot: &slot)
        _appNode.onNeedsUpdate = { [weak self] in self?._scheduleSceneUpdate() }
        _sceneBody = { app.body }
        _evaluateScenes()
    }

    private func _evaluateScenes() {
        guard let body = _sceneBody else { return }
        commands = []
        settingsContent = nil
        _windowGroupOrdinal = 0
        _appNode.needsUpdate = false
        // Only the scene body itself is tracked (the App's @State, and the model reads in
        // `.commands`, whose titles are built here). A window's content closure runs
        // outside the scope: what it reads belongs to the window's own view tree, which
        // re-renders by itself. Tracking it re-ran every scene, re-rendered every window
        // and rebuilt the menu bar on each keystroke into a field bound to the model.
        let scene = _trackingObservation(_appNode) { body() }
        run(scene: scene)
        installMenuBar()
    }

    private func _scheduleSceneUpdate() {
        guard !_sceneUpdateScheduled else { return }
        _sceneUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self._sceneUpdateScheduled = false
            self._updateScenes()
        }
    }

    /// Re-runs the scenes in update mode now: every open scene window's content is
    /// re-evaluated (its hosting view gets a new root view, so bindings such as a
    /// `.fileExporter(isPresented:)` see the new value) and the menu bar is rebuilt from
    /// the commands. Tests call it in place of the scheduled run.
    public func _updateScenes() {
        guard _sceneBody != nil else { return }
        _isUpdatingScenes = true
        defer { _isUpdatingScenes = false }
        _evaluateScenes()
    }

    /// The Settings scene re-ran: its open window shows the new content.
    func _refreshSettingsWindow() {
        guard let window = settingsWindow, let make = settingsContent, let hosting = window.contentView as? NSHostingView<AnyView> else { return }
        hosting.rootView = make()
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

    /// Opens (or brings forward) the Settings scene's window. It is sized like a scene
    /// window under `.windowResizability(.contentSize)`: fixed when the content has one
    /// size, resizable within the content's range otherwise (Apple's Settings window
    /// resizes when its content's frame is flexible), never taller than the screen. On
    /// Windows and Linux it carries no in-window menu bar, as a dialog does not; its
    /// shortcuts still reach the main menu through the application.
    public func openSettings() {
        if let w = settingsWindow { w.makeKeyAndOrderFront(nil); return }
        guard let make = settingsContent else { return }
        // The content knows it is the Settings scene's (a TabView shows the Settings tab bar).
        let hosting = NSHostingView(rootView: AnyView(make().environment(\._isSettingsScene, true)))
        var geometry = _windowGeometry(for: hosting, defaultSize: nil, resizability: .contentSize, hidesTitleBar: false)
        geometry.style.remove(.miniaturizable)
        let window = _SettingsWindow(contentRect: NSRect(origin: .zero, size: geometry.size), styleMask: geometry.style, backing: .buffered, defer: false)
        window.title = "\(applicationName) Settings"
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.minSize = geometry.contentMin
        if let max = geometry.contentMax { window.maxSize = max }
        hosting.frame = NSRect(origin: .zero, size: geometry.size)
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
        let window = _makeWindow(title: title, content: content, defaultSize: defaultSize ?? pendingDefaultSize,
                                 resizability: pendingResizability, hidesTitleBar: pendingHidesTitleBar, toolbarStyle: pendingToolbarStyle)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// A DocumentGroup document's window (not shown: its window controller shows it), with
    /// the scene modifiers the group was declared under. Each new one cascades from the
    /// last document window, as AppKit's document windows do.
    func _makeDocumentWindow<Content: View>(content: Content, entry: _DocumentGroupEntry) -> NSWindow {
        let window = _makeWindow(title: "", content: content, defaultSize: entry.defaultSize,
                                 resizability: entry.resizability, hidesTitleBar: entry.hidesTitleBar, toolbarStyle: entry.toolbarStyle)
        if let last = _lastDocumentWindow, last.isVisible {
            let frame = last.frame
            _ = window.cascadeTopLeft(from: window.cascadeTopLeft(from: NSPoint(x: frame.minX, y: frame.maxY)))
        } else {
            window.center()
        }
        _lastDocumentWindow = window
        return window
    }
    private weak var _lastDocumentWindow: NSWindow?

    /// A scene window hosting `content`, sized and styled as the scene modifiers say,
    /// tracked by the runner (closing the last one quits off macOS). Not yet shown.
    func _makeWindow<Content: View>(title: String, content: Content, defaultSize: CGSize?, resizability: WindowResizability,
                                            hidesTitleBar: Bool, toolbarStyle: NSWindow.ToolbarStyle) -> NSWindow {
        let hosting = NSHostingView(rootView: content)
        let geometry = _windowGeometry(for: hosting, defaultSize: defaultSize, resizability: resizability, hidesTitleBar: hidesTitleBar)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: geometry.size), styleMask: geometry.style, backing: .buffered, defer: false)
        window.title = title
        switch resizability.kind {
        case .contentSize: window.minSize = geometry.contentMin; if let contentMax = geometry.contentMax { window.maxSize = contentMax }
        case .contentMinSize: window.minSize = geometry.ideal
        case .automatic: break
        }
        observeClose(of: window)
        if hidesTitleBar { window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden }
        window.toolbarStyle = toolbarStyle
        hosting.frame = NSRect(origin: .zero, size: geometry.size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        windows.append(window)
        return window
    }

    struct _WindowGeometry {
        var size: NSSize
        var style: NSWindow.StyleMask
        var ideal: NSSize
        var contentMin: NSSize
        var contentMax: NSSize?
    }

    /// The opening size, style mask and size range of a window hosting `hosting`, from the
    /// scene modifiers (shared by scene windows and the Settings window).
    func _windowGeometry(for hosting: NSHostingView<some View>, defaultSize: CGSize?, resizability: WindowResizability, hidesTitleBar: Bool) -> _WindowGeometry {
        let pendingDefaultSize = defaultSize, pendingResizability = resizability, pendingHidesTitleBar = hidesTitleBar
        let ideal = hosting.sizeThatFits(.unspecified)
        var size: NSSize
        if let given = pendingDefaultSize {
            // `.defaultSize` is the window's size, grown only to the content's minimum (not
            // its ideal: a scroll view's ideal is its whole document, which opened MD Vault's
            // viewer 1460 points tall).
            let least = hosting.sizeThatFits(NSHostingSizeProposal(width: 0, height: 0))
            size = NSSize(width: max(given.width, least.width), height: max(given.height, least.height))
        } else {
            size = NSSize(width: max(ideal.width, 300), height: max(ideal.height, 200))
        }
        // A new window fits the screen's visible frame (less the title bar), as AppKit
        // constrains a window's first frame.
        if let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame, visible.width > 0, visible.height > 0 {
            size.width = min(size.width, visible.width)
            size.height = min(size.height, max(200, visible.height - 40))
        }
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        if pendingHidesTitleBar { style.insert(.fullSizeContentView) }
        // `.contentSize`: the window's size range is the content's (its minimum and
        // maximum frame sizes), so content with a minimum and no maximum still resizes;
        // only content of one size gives a fixed window with no resize frame and no zoom.
        // `.contentMinSize`: it cannot shrink below the content's ideal size.
        var contentMin = size, contentMax: NSSize? = nil
        if pendingResizability == .contentSize {
            let lo = hosting.sizeThatFits(NSHostingSizeProposal(width: 0, height: 0))
            let hi = hosting.sizeThatFits(NSHostingSizeProposal(width: .infinity, height: .infinity))
            contentMin = NSSize(width: max(lo.width, 1), height: max(lo.height, 1))
            contentMax = NSSize(width: hi.width.isFinite ? max(hi.width, contentMin.width) : .greatestFiniteMagnitude,
                                height: hi.height.isFinite ? max(hi.height, contentMin.height) : .greatestFiniteMagnitude)
            // The window opens at the content's ideal size (a default size if the scene
            // gave one), within the content's range: no 300×200 floor for fixed content.
            var s = pendingDefaultSize ?? ideal
            s.width = min(max(s.width, contentMin.width), contentMax!.width)
            s.height = min(max(s.height, contentMin.height), contentMax!.height)
            size = s
            if contentMin == contentMax { style.remove(.resizable) }
        }
        return _WindowGeometry(size: size, style: style, ideal: ideal, contentMin: contentMin, contentMax: contentMax)
    }

    private var closeObservers: [any NSObjectProtocol] = []
    /// Forgets a scene window once it closes. Where there is no Dock to reopen the app
    /// from (Windows, Linux), a SwiftUI app whose last window closed would linger with no
    /// window, no menu bar and no way back, so it terminates then, unless it keeps a status
    /// item (a menu-bar app) or its delegate took the decision. On macOS AppKit's rule
    /// applies: the app keeps running and the Dock reopens it.
    private func observeClose(of window: NSWindow) {
        let token = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: nil) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let self, let window else { return }
                self.windows.removeAll { $0 === window }
                self.lastWindowDidClose()
            }
        }
        closeObservers.append(token)
    }
    /// Test hook: false keeps a test process alive when it closes a runner's last window.
    static var _terminatesAfterLastWindowCloses = true
    private func lastWindowDidClose() {
        #if !canImport(Darwin)
        guard _AppRunner._terminatesAfterLastWindowCloses, windows.isEmpty, settingsWindow?.isVisible != true else { return }
        let app = NSApplication.shared
        guard !NSStatusBar.system._hasItems, app.delegate?.applicationShouldTerminateAfterLastWindowClosed(app) != true else { return }
        // After the close finishes: terminate from inside willClose would tear the window
        // down under its own notification.
        DispatchQueue.main.async { if NSApplication.shared.windows.allSatisfy({ !$0.isVisible }) { NSApplication.shared.terminate(nil) } }
        #endif
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
