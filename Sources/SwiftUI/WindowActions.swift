// Opening and dismissing scene windows by id: `@Environment(\.openWindow)` and
// `@Environment(\.dismissWindow)` over the runner's registry of `Window` and identified
// `WindowGroup` scenes.
//
// As on macOS, only the app's first scene opens at launch: a later `Window` (or a
// `WindowGroup` with an id) waits for `openWindow(id:)`. Opening a `Window` that is open
// brings it forward; opening a `WindowGroup` makes another of its windows.

import Foundation

/// A scene `openWindow(id:)` can open: how to make its window, with the scene modifiers it
/// was declared under, and the windows it has open.
@MainActor
final class _WindowScene {
    let isSingle: Bool
    var make: () -> NSWindow
    /// Re-evaluates the content into one of this scene's open windows (an App state
    /// change re-ran the scenes, App.swift `_updateScenes`).
    var refresh: (NSWindow) -> Void
    var windows: [NSWindow] = []
    init(isSingle: Bool, make: @escaping () -> NSWindow, refresh: @escaping (NSWindow) -> Void) {
        self.isSingle = isSingle; self.make = make; self.refresh = refresh
    }
}

extension _AppRunner {
    /// A `Window` scene: registered by id, opened now only when it is the first scene.
    func _runWindowScene<Content: View>(id: String, title: String, content: @escaping () -> Content) {
        let size = pendingDefaultSize, resizability = pendingResizability, hides = pendingHidesTitleBar, toolbar = pendingToolbarStyle
        let make: () -> NSWindow = { [unowned self] in
            let w = self._makeWindow(title: title, content: content(), defaultSize: size, resizability: resizability, hidesTitleBar: hides, toolbarStyle: toolbar)
            w.center()
            return w
        }
        let refresh: (NSWindow) -> Void = { w in (w.contentView as? NSHostingView<Content>)?.rootView = content() }
        if _isUpdatingScenes, let scene = _windowScenes[id] {
            scene.make = make; scene.refresh = refresh
            _refresh(scene)
            return
        }
        let scene = _WindowScene(isSingle: true, make: make, refresh: refresh)
        _windowScenes[id] = scene
        guard !_launchSceneOpened else { return }
        _launchSceneOpened = true
        _present(scene)
    }

    /// A `WindowGroup`: one with an id is registered for `openWindow(id:)` and, after the
    /// first scene, waits for it; one without opens as it always has.
    func _runWindowGroup<Content: View>(id: String?, title: String, content: @escaping () -> Content, defaultSize: CGSize?) {
        // An id-less group is registered under an ordinal key so an update finds its windows.
        let key: String
        if let id { key = id } else { key = "\u{1}WindowGroup#\(_windowGroupOrdinal)"; _windowGroupOrdinal += 1 }
        let size = defaultSize ?? pendingDefaultSize, resizability = pendingResizability, hides = pendingHidesTitleBar, toolbar = pendingToolbarStyle
        let make: () -> NSWindow = { [unowned self] in
            let w = self._makeWindow(title: title, content: content(), defaultSize: size, resizability: resizability, hidesTitleBar: hides, toolbarStyle: toolbar)
            w.center()
            return w
        }
        let refresh: (NSWindow) -> Void = { w in (w.contentView as? NSHostingView<Content>)?.rootView = content() }
        if _isUpdatingScenes, let scene = _windowScenes[key] {
            scene.make = make; scene.refresh = refresh
            _refresh(scene)
            return
        }
        let scene = _WindowScene(isSingle: false, make: make, refresh: refresh)
        _windowScenes[key] = scene
        if id != nil, _launchSceneOpened { return }
        _launchSceneOpened = true
        let wasPrimary = primaryWindowGroup == nil
        openWindow(title: title, content: content(), defaultSize: defaultSize)
        if let w = windows.last { scene.windows.append(w) }
        if wasPrimary {
            // File > New Window opens another of this group's windows, tracked so that an
            // App state update refreshes it too.
            primaryWindowGroup = { [weak scene] in
                guard let scene else { return }
                let w = scene.make()
                scene.windows.append(w)
                w.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func _refresh(_ scene: _WindowScene) {
        scene.windows.removeAll { !_isOpen($0) }
        for w in scene.windows { scene.refresh(w) }
    }

    private func _isOpen(_ w: NSWindow) -> Bool { windows.contains { $0 === w } }

    private func _present(_ scene: _WindowScene) {
        scene.windows.removeAll { !_isOpen($0) }
        if scene.isSingle, let w = scene.windows.first {
            w.makeKeyAndOrderFront(nil)
        } else {
            let w = scene.make()
            scene.windows.append(w)
            w.makeKeyAndOrderFront(nil)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// `openWindow(id:)`: opens the scene's window, or brings an open `Window` forward.
    public func _openScene(id: String) {
        guard let scene = _windowScenes[id] else {
            fputs("SwiftUI: openWindow(id: \"\(id)\") names no Window or WindowGroup scene\n", stderr)
            return
        }
        _present(scene)
    }

    /// `dismissWindow(id:)`: closes the scene's open windows.
    public func _dismissScene(id: String) {
        guard let scene = _windowScenes[id] else { return }
        for w in scene.windows where _isOpen(w) { w.close() }
        scene.windows.removeAll()
    }

    /// The open windows of a scene (tests).
    public func _windows(ofScene id: String) -> [NSWindow] { _windowScenes[id]?.windows.filter { _isOpen($0) } ?? [] }
}

// MARK: Actions

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/openwindowaction
/// `callAsFunction(id:)` opens the `Window` or `WindowGroup` with that id (an open `Window`
/// comes forward). Value-presenting window groups (`WindowGroup(for:)`) are not built, so
/// the value forms trap.
@MainActor @preconcurrency
public struct OpenWindowAction {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/openwindowaction/sharingbehavior
    public struct SharingBehavior: Sendable {
        let raw: Int
        public static let requested = SharingBehavior(raw: 0)
        public static let required = SharingBehavior(raw: 1)
    }
    let open: @MainActor (String) -> Void
    nonisolated init(open: @escaping @MainActor (String) -> Void) { self.open = open }

    public func callAsFunction(id: String) { open(id) }
    public func callAsFunction<D: Decodable & Encodable & Hashable>(value: D) {
        unimplemented("OpenWindowAction(value:) (WindowGroup(for:) is not built)")
    }
    public func callAsFunction<D: Decodable & Encodable & Hashable>(id: String, value: D) {
        unimplemented("OpenWindowAction(id:value:) (WindowGroup(for:) is not built)")
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/dismisswindowaction
/// `callAsFunction(id:)` closes that scene's windows; `callAsFunction()` closes the key
/// window (the window whose view runs the action, as a button press makes it key). The
/// value forms trap (see `OpenWindowAction`).
@MainActor @preconcurrency
public struct DismissWindowAction {
    nonisolated init() {}
    public func callAsFunction() { NSApplication.shared.keyWindow?.close() }
    public func callAsFunction(id: String) { _AppRunner._current?._dismissScene(id: id) }
    public func callAsFunction<D: Decodable & Encodable & Hashable>(value: D) {
        unimplemented("DismissWindowAction(value:) (WindowGroup(for:) is not built)")
    }
    public func callAsFunction<D: Decodable & Encodable & Hashable>(id: String, value: D) {
        unimplemented("DismissWindowAction(id:value:) (WindowGroup(for:) is not built)")
    }
}

private struct _OpenWindowKey: EnvironmentKey {
    static var defaultValue: OpenWindowAction { OpenWindowAction { id in _AppRunner._current?._openScene(id: id) } }
}
private struct _DismissWindowKey: EnvironmentKey {
    static var defaultValue: DismissWindowAction { DismissWindowAction() }
}

extension EnvironmentValues {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/environmentvalues/openwindow
    public var openWindow: OpenWindowAction { self[_OpenWindowKey.self] }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/environmentvalues/dismisswindow
    public var dismissWindow: DismissWindowAction { self[_DismissWindowKey.self] }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion
    /// The system setting (`NSWorkspace.accessibilityDisplayShouldReduceMotion`), read
    /// when the view reads it.
    public var accessibilityReduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency
    public var accessibilityReduceTransparency: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilitydifferentiatewithoutcolor
    public var accessibilityDifferentiateWithoutColor: Bool { NSWorkspace.shared.accessibilityDisplayShouldDifferentiateWithoutColor }
}
