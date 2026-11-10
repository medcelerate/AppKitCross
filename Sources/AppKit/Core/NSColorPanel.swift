// NSColorPanel (hand-written; seeded from the generated stub, see tools/apigen)
//
// The shared Colors panel, drawn by the package on every backend (ADR-0022): a mode bar
// (wheel, sliders, lists, crayons), the current colour as a draggable swatch with its
// hex value, the picker for the mode, an opacity slider when alpha is shown, the
// accessory view and a row of favourite swatches, in the current appearance. A change
// made in the panel posts `colorDidChangeNotification` and sends the action
// (`changeColor:` by default) to the target, or with no target through the responder
// chain, as the colour changes when `isContinuous` and otherwise when the mouse goes up.
// With `APPKITWIN_COLOR_PANEL=native`, a backend that has a system colour dialog
// (Windows' ChooseColor) runs it instead when the panel is ordered front; the colour
// it returns arrives the same way.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(QuartzCore)
import QuartzCore
#endif
#if canImport(CoreText)
import CoreText
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorpanel
@MainActor open class NSColorPanel: NSPanel {
    // MARK: Storage
    nonisolated(unsafe) private static var _shared: NSColorPanel? = nil
    nonisolated(unsafe) private static var _defaultMode: NSColorPanel.Mode = .wheel
    nonisolated(unsafe) private static var _pickerMask: NSColorPanel.Options = .allModesMask
    internal static let defaultAction = Selector(("changeColor:"))
    internal static let contentWidth: CGFloat = 280

    private var _color: NSColor = .white
    private var _mode: NSColorPanel.Mode = .wheel
    private var _showsAlpha = false
    private var _isContinuous = true
    internal weak var _target: AnyObject? = nil
    private var _action: Selector? = nil
    private var _accessoryView: NSView? = nil
    private var _attachedLists: [NSColorList] = []
    internal let _view: _NSColorPanelView

    @MainActor public override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        _view = _NSColorPanelView(frame: NSRect(origin: .zero, size: contentRect.size))
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        title = "Colors"
        isReleasedWhenClosed = false
        _mode = NSColorPanel._defaultMode
        _view.panel = self
        contentView = _view
        _view.setAvailableModes(NSColorPanel._pickerMask)
        _view.setMode(_mode)
        _view.sync(color: _color)
        _fitToContent()
    }
    @MainActor public required init?(coder: NSCoder) { nil }

    /// Resizes the window to the content the view wants (alpha row, accessory view).
    internal func _fitToContent() {
        let height = _view.preferredHeight
        if contentView?.frame.height != height || contentView?.frame.width != NSColorPanel.contentWidth {
            let old = frame
            setContentSize(NSSize(width: NSColorPanel.contentWidth, height: height))
            // Keep the top edge where it was, as AppKit panels do when they grow.
            setFrameOrigin(NSPoint(x: old.minX, y: old.maxY - frame.height))
        }
        _view.needsLayout = true
    }

    /// The user changed the colour in the panel: show it, tell observers, send the action
    /// (every change when continuous, else the final one).
    internal func _userSetColor(_ c: NSColor, final: Bool) {
        let changed = !_color.isEqual(c)
        _color = c
        _view.sync(color: c)
        if changed { NotificationCenter.default.post(name: NSColorPanel.colorDidChangeNotification, object: self) }
        if (changed && _isContinuous) || (final && !_isContinuous) { _sendAction() }
    }

    internal func _sendAction() {
        _ = NSApplication.shared.sendAction(_action ?? NSColorPanel.defaultAction, to: _target, from: self)
    }

    /// The lists the list picker offers: the standard ones plus those attached.
    internal var _colorLists: [NSColorList] {
        var lists = NSColorList.availableColorLists
        for l in _attachedLists where !lists.contains(where: { $0 === l }) { lists.append(l) }
        return lists
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorpanel/accessoryview
    @MainActor open var accessoryView: NSView? {
        get { _accessoryView }
        set {
            _accessoryView?.removeFromSuperview()
            _accessoryView = newValue
            _view.accessory = newValue
            if let v = newValue { _view.addSubview(v) }
            _fitToContent()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorpanel/alpha
    @MainActor open var alpha: CGFloat { _showsAlpha ? _color.alphaComponent : 1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorpanel/attachcolorlist(_:)
    @MainActor open func attachColorList(_ colorList: NSColorList) {
        guard !_attachedLists.contains(where: { $0 === colorList }) else { return }
        _attachedLists.append(colorList)
        _view.reloadLists()
    }
    /// Setting the colour shows it and posts `colorDidChangeNotification`; it sends no action.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorpanel/color
    @MainActor open var color: NSColor {
        get { _color }
        set {
            let c = _showsAlpha ? newValue : newValue.withAlphaComponent(1)
            let changed = !_color.isEqual(c)
            _color = c
            _view.sync(color: c)
            if changed { NotificationCenter.default.post(name: NSColorPanel.colorDidChangeNotification, object: self) }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorpanel/colordidchangenotification
    static public var colorDidChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSColorPanelColorDidChangeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorpanel/detachcolorlist(_:)
    @MainActor open func detachColorList(_ colorList: NSColorList) {
        _attachedLists.removeAll { $0 === colorList }
        _view.reloadLists()
    }
    /// Starts dragging `color` from `sourceView` (a swatch follows the pointer; the
    /// pasteboard carries the colour for wells, text views and the panel).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorpanel/dragcolor(_:with:from:)
    @MainActor public class func dragColor(_ color: NSColor, with event: NSEvent, from sourceView: NSView) -> Bool {
        let item = NSDraggingItem(pasteboardWriter: color)
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            if color.alphaComponent < 1 {
                NSGraphicsContext.saveGraphicsState()
                path.addClip()
                NSColorWell._drawCheckerboard(in: rect, cell: 4)
                NSGraphicsContext.restoreGraphicsState()
            }
            color.setFill()
            path.fill()
            NSColor(white: 0, alpha: 0.4).setStroke()
            path.stroke()
            return true
        }
        let p = sourceView.convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height), contents: image)
        let source: any NSDraggingSource = (sourceView as? NSDraggingSource) ?? _NSColorDragSource.shared
        _ = sourceView.beginDraggingSession(with: [item], event: event, source: source)
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorpanel/iscontinuous
    @MainActor open var isContinuous: Bool {
        get { _isContinuous }
        set { _isContinuous = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorpanel/maximumlinearexposure
    @available(macOS 26.0, *)
    @MainActor open var maximumLinearExposure: CGFloat {
        get { 1 }
        set { }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorpanel/mode
    @MainActor open var mode: NSColorPanel.Mode {
        get { _mode }
        set { _mode = newValue; _view.setMode(newValue); _fitToContent() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorpanel/setaction(_:)
    @MainActor open func setAction(_ selector: Selector?) { _action = selector }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorpanel/setpickermask(_:)
    @MainActor public class func setPickerMask(_ mask: NSColorPanel.Options) {
        _pickerMask = mask
        _shared?._view.setAvailableModes(mask)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorpanel/setpickermode(_:)
    @MainActor public class func setPickerMode(_ mode: NSColorPanel.Mode) {
        _defaultMode = mode
        _shared?.mode = mode
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorpanel/settarget(_:)
    @MainActor open func setTarget(_ target: Any?) { _target = target as AnyObject? }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorpanel/shared
    @MainActor class public var shared: NSColorPanel {
        if let p = _shared { return p }
        let panel = NSColorPanel(contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: 380), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.center()
        if let key = NSApplication.shared.keyWindow, !(key is NSPanel), let screen = key.screen ?? NSScreen.main {
            var origin = NSPoint(x: key.frame.maxX + 12, y: key.frame.maxY - panel.frame.height)
            if origin.x + panel.frame.width > screen.visibleFrame.maxX { origin.x = max(screen.visibleFrame.minX, key.frame.minX - panel.frame.width - 12) }
            origin.y = max(screen.visibleFrame.minY, origin.y)
            panel.setFrameOrigin(origin)
        }
        _shared = panel
        return panel
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorpanel/sharedcolorpanelexists
    @MainActor class public var sharedColorPanelExists: Bool { _shared != nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorpanel/showsalpha
    @MainActor open var showsAlpha: Bool {
        get { _showsAlpha }
        set {
            guard _showsAlpha != newValue else { return }
            _showsAlpha = newValue
            if !newValue, _color.alphaComponent < 1 { _color = _color.withAlphaComponent(1); _view.sync(color: _color) }
            _view.showsAlpha = newValue
            _fitToContent()
        }
    }

    /// Shows the panel; with `APPKITWIN_COLOR_PANEL=native` a backend that has a system
    /// colour dialog runs it modally instead and the chosen colour arrives as a final change.
    /// Test hook: stands in for `APPKITWIN_COLOR_PANEL=native` when set.
    nonisolated(unsafe) internal static var _nativeDialogOverride: Bool? = nil
    internal static var _usesNativeDialog: Bool { _nativeDialogOverride ?? (ProcessInfo.processInfo.environment["APPKITWIN_COLOR_PANEL"] == "native") }

    @MainActor open override func orderFront(_ sender: Any?) {
        if NSColorPanel._usesNativeDialog {
            let parent = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow
            if let result = Platform.backend.runColorDialog(initial: (_color.redComponent, _color.greenComponent, _color.blueComponent), parent: parent?._platformWindow) {
                _userSetColor(NSColor(red: result.0, green: result.1, blue: result.2, alpha: _showsAlpha ? _color.alphaComponent : 1), final: true)
            }
            // nil: cancelled, or no native dialog on this backend without the package panel to fall back on.
            if Platform.backend.hasNativeColorDialog { return }
        }
        _view.needsLayout = true
        super.orderFront(sender)
    }
    @MainActor open override var canBecomeMain: Bool { false }
}

/// The dragging source colours use when the view that starts the drag is not one itself.
@MainActor
internal final class _NSColorDragSource: NSObject, NSDraggingSource {
    static let shared = _NSColorDragSource()
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .generic }
}
