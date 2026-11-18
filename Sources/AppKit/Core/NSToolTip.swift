// Tool tips (ADR-0036): `NSView.toolTip` and the rectangles of `NSView.addToolTip`
// appear in a small non-activating panel after the pointer rests over them, as AppKit's
// do. Hand-written support code, not an AppKit type.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The panel a tool tip shows in: borderless, never key, above menus, transparent to
/// the mouse.
@MainActor
final class _NSToolTipWindow: NSPanel {
    let label: NSTextField
    init() {
        label = NSTextField(labelWithString: "")
        label.font = NSFont.toolTipsFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .labelColor
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .popUpMenu
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        hasShadow = true
        backgroundColor = .windowBackgroundColor
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        box.addSubview(label)
        contentView = box
    }
    required init?(coder: NSCoder) { nil }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Sizes the panel around `text` with its top-left corner at `topLeft` (screen).
    func show(_ text: String, topLeft: NSPoint) {
        label.stringValue = text
        let size = label.fittingSize
        let inset = NSSize(width: 4, height: 2)
        let content = NSSize(width: ceil(size.width) + inset.width * 2, height: ceil(size.height) + inset.height * 2)
        label.frame = NSRect(origin: NSPoint(x: inset.width, y: inset.height), size: NSSize(width: ceil(size.width), height: ceil(size.height)))
        contentView?.frame = NSRect(origin: .zero, size: content)
        var frame = NSRect(x: topLeft.x, y: topLeft.y - content.height, width: content.width, height: content.height)
        if let visible = (NSScreen.screens.first { $0.frame.contains(topLeft) } ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = max(frame.minY, visible.minY)
        }
        setFrame(frame, display: true)
        orderFront(nil)
    }
}

/// Watches the pointer (windows report every move here) and shows the tip of what it
/// rests on: after `initialDelay`, again at once while the pointer moves between tips.
@MainActor
final class _NSToolTipManager {
    static let shared = _NSToolTipManager()
    /// AppKit's `NSInitialToolTipDelay` default, in seconds (a user default overrides it).
    var initialDelay: TimeInterval {
        let ms = UserDefaults.standard.double(forKey: "NSInitialToolTipDelay")
        return ms > 0 ? ms / 1000 : 1.0
    }
    private var window: _NSToolTipWindow?
    private var timer: Timer?
    /// What the pointer rests on: the view and the tip region in it (nil: its `toolTip`).
    private weak var view: NSView?
    private var tag: NSView.ToolTipTag?
    private var pending: (text: String, screenPoint: NSPoint)?
    /// The text on screen now (tests read it).
    private(set) var visibleText: String?

    /// The tip under `location` (window base coordinates) in `window`.
    func toolTip(in window: NSWindow, at location: NSPoint) -> (view: NSView, tag: NSView.ToolTipTag?, text: String)? {
        var v = window.contentView?.hitTest(location)
        while let view = v {
            let p = view.convert(location, from: nil)
            for entry in view._toolTipRects.reversed() where view.isMousePoint(p, in: entry.rect) {
                let text: String
                if let owner = entry.owner as? NSViewToolTipOwner {
                    text = owner.view(view, stringForToolTip: entry.tag, point: p, userData: entry.userData)
                } else {
                    text = (entry.owner as? String) ?? "\(entry.owner)"
                }
                if !text.isEmpty { return (view, entry.tag, text) }
            }
            if let text = view.toolTip, !text.isEmpty { return (view, nil, text) }
            v = view.superview
        }
        return nil
    }

    func mouseMoved(in window: NSWindow, at location: NSPoint) {
        guard window.isKeyWindow || window.allowsToolTipsWhenApplicationIsInactive || NSApplication.shared.isActive,
              let hit = toolTip(in: window, at: location) else { dismiss(); return }
        if hit.view === view && hit.tag == tag { return }   // still on the same tip
        let wasShowing = visibleText != nil
        dismiss()
        view = hit.view
        tag = hit.tag
        let screen = window.convertPoint(toScreen: location)
        pending = (hit.text, NSPoint(x: screen.x, y: screen.y - 18))   // below the arrow cursor
        if wasShowing { showPending(); return }
        timer = Timer.scheduledTimer(withTimeInterval: initialDelay, repeats: false) { _ in
            MainActor.assumeIsolated { _NSToolTipManager.shared.showPending() }
        }
    }

    /// Shows the tip the pointer rests on now (the timer's action; tests call it directly).
    func showPending() {
        timer?.invalidate(); timer = nil
        guard let pending, view?.window != nil else { return }
        let w = window ?? _NSToolTipWindow()
        window = w
        w.show(pending.text, topLeft: pending.screenPoint)
        visibleText = pending.text
    }

    /// A click, a key, the pointer leaving: the tip goes away.
    func dismiss() {
        timer?.invalidate(); timer = nil
        pending = nil
        view = nil
        tag = nil
        if visibleText != nil { window?.orderOut(nil) }
        visibleText = nil
    }

    /// The view's tips changed: drop the one showing for it.
    func viewChanged(_ changed: NSView) {
        if view === changed { dismiss() }
    }
}
