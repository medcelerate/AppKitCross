// Toolbar: a window with an NSToolbar (image items, a segmented group, a menu item, a
// search field, the standard items, user customization with autosave, the chevron
// overflow when the window is narrow) and an NSStatusItem in the platform's status
// area whose click opens a menu (ADR-0018).

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSToolbarDelegate, NSToolbarItemValidation, NSSelectorHandling {
    var window: NSWindow!
    var toolbar: NSToolbar!
    var status: NSTextField!
    var statusItem: NSStatusItem?
    var statusVisible: NSButton!
    var coversTitleBar: NSButton!
    var styles: NSPopUpButton!
    var modes: NSPopUpButton!
    var canGoForward = false

    static let back = NSToolbarItem.Identifier("back")
    static let forward = NSToolbarItem.Identifier("forward")
    static let style = NSToolbarItem.Identifier("style")
    static let tint = NSToolbarItem.Identifier("tint")
    static let edit = NSToolbarItem.Identifier("edit")
    static let preview = NSToolbarItem.Identifier("preview")
    static let search = NSToolbarItem.Identifier("search")
    static let act = Selector(("toolbarItemClicked:"))

    /// A simple vector glyph for an item (no system symbols on these platforms).
    static func glyph(_ draw: @escaping (NSRect) -> Void) -> NSImage {
        NSImage(size: NSSize(width: 24, height: 24), flipped: false) { r in draw(r.insetBy(dx: 3, dy: 3)); return true }
    }
    static func arrow(forward: Bool) -> NSImage {
        glyph { r in
            let p = NSBezierPath()
            let x0 = forward ? r.minX : r.maxX, x1 = forward ? r.maxX : r.minX
            p.move(to: NSPoint(x: x0, y: r.midY)); p.line(to: NSPoint(x: x1, y: r.midY))
            let tip = x1, dir: CGFloat = forward ? -1 : 1
            p.move(to: NSPoint(x: tip + dir * 6, y: r.midY + 6)); p.line(to: NSPoint(x: tip, y: r.midY)); p.line(to: NSPoint(x: tip + dir * 6, y: r.midY - 6))
            p.lineWidth = 2; p.lineCapStyle = .round; p.lineJoinStyle = .round
            NSColor.labelColor.setStroke(); p.stroke()
        }
    }
    static func disc(_ color: NSColor) -> NSImage { glyph { r in color.setFill(); NSBezierPath(ovalIn: r).fill() } }
    static func pencil() -> NSImage {
        glyph { r in
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.minX, y: r.minY)); p.line(to: NSPoint(x: r.maxX - 4, y: r.maxY - 4))
            p.lineWidth = 3; p.lineCapStyle = .round; NSColor.labelColor.setStroke(); p.stroke()
            NSColor.labelColor.setFill(); NSBezierPath(ovalIn: NSRect(x: r.maxX - 6, y: r.maxY - 6, width: 6, height: 6)).fill()
        }
    }
    static func eye() -> NSImage {
        glyph { r in
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.minX, y: r.midY))
            p.curve(to: NSPoint(x: r.maxX, y: r.midY), controlPoint1: NSPoint(x: r.minX + 4, y: r.maxY + 2), controlPoint2: NSPoint(x: r.maxX - 4, y: r.maxY + 2))
            p.curve(to: NSPoint(x: r.minX, y: r.midY), controlPoint1: NSPoint(x: r.maxX - 4, y: r.minY - 2), controlPoint2: NSPoint(x: r.minX + 4, y: r.minY - 2))
            p.lineWidth = 1.5; NSColor.labelColor.setStroke(); p.stroke()
            NSColor.labelColor.setFill(); NSBezierPath(ovalIn: NSRect(x: r.midX - 3, y: r.midY - 3, width: 6, height: 6)).fill()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Toolbar"
        window.isReleasedWhenClosed = false
        window.contentView = makeContent()

        toolbar = NSToolbar(identifier: "Examples.Toolbar.main")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.displayMode = .iconAndLabel
        toolbar.selectedItemIdentifier = AppDelegate.edit
        window.toolbar = toolbar
        syncModePopUp()        // the autosaved display mode
        window.center()
        window.makeKeyAndOrderFront(nil)
        // The Customize sheet can change the display mode: resync the pop-up when it closes.
        NotificationCenter.default.addObserver(forName: NSWindow.didEndSheetNotification, object: window, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncModePopUp() }
        }

        makeStatusItem()
        report("ready; the toolbar's items send their actions here")
    }

    // MARK: Window content

    private func makeContent() -> NSView {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        let stack = NSStackView(frame: NSRect(x: 20, y: 20, width: 600, height: 320))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.autoresizingMask = [.width, .height]
        let intro = NSTextField(labelWithString: "An NSToolbar drawn by the package under the title bar: image items, a group, a menu item,\na search field and Customize. Narrow the window: items move into the » menu.\nThe status area icon shows a menu when clicked.")
        intro.lineBreakMode = .byWordWrapping
        intro.maximumNumberOfLines = 3
        stack.addArrangedSubview(intro)
        status = NSTextField(labelWithString: "")
        status.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(status)

        func row(_ label: String, _ control: NSView) -> NSStackView {
            let r = NSStackView()
            r.orientation = .horizontal
            r.spacing = 8
            let l = NSTextField(labelWithString: label)
            r.addArrangedSubview(l)
            r.addArrangedSubview(control)
            return r
        }
        styles = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 160, height: 26), pullsDown: false)
        styles.addItems(withTitles: ["Automatic", "Expanded", "Preference", "Unified", "Unified compact"])
        styles.target = self
        styles.action = Selector(("styleChanged:"))
        stack.addArrangedSubview(row("Toolbar style:", styles))
        modes = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 160, height: 26), pullsDown: false)
        modes.addItems(withTitles: ["Icon and label", "Icon only", "Label only"])
        modes.target = self
        modes.action = Selector(("modeChanged:"))
        stack.addArrangedSubview(row("Display mode:", modes))
        coversTitleBar = NSButton(checkboxWithTitle: "Content covers the title bar (fullSizeContentView: the unified styles sit next to the window buttons)", target: self, action: Selector(("coverChanged:")))
        stack.addArrangedSubview(coversTitleBar)
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.addArrangedSubview(NSButton(title: "Show/Hide Toolbar", target: nil, action: Selector(("toggleToolbarShown:"))))
        buttons.addArrangedSubview(NSButton(title: "Customize Toolbar…", target: nil, action: Selector(("runToolbarCustomizationPalette:"))))
        buttons.addArrangedSubview(NSButton(title: "Validate", target: self, action: Selector(("validate:"))))
        stack.addArrangedSubview(buttons)
        statusVisible = NSButton(checkboxWithTitle: "Status item in the status area (click: menu; Windows tray, Linux StatusNotifierItem)", target: self, action: Selector(("statusVisibleChanged:")))
        statusVisible.state = .on
        stack.addArrangedSubview(statusVisible)
        content.addSubview(stack)
        return content
    }

    private func installMenu() {
        let main = NSMenu(title: "Main")
        let app = NSMenuItem(title: "Toolbar", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "Toolbar")
        appMenu.addItem(withTitle: "Quit", action: Selector(("quit:")), keyEquivalent: "q")
        app.submenu = appMenu
        main.addItem(app)
        let view = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Show/Hide Toolbar", action: Selector(("toggleToolbarShown:")), keyEquivalent: "t").keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(withTitle: "Customize Toolbar…", action: Selector(("runToolbarCustomizationPalette:")), keyEquivalent: "")
        view.submenu = viewMenu
        main.addItem(view)
        NSApp.mainMenu = main
    }

    // MARK: Status item

    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = AppDelegate.glyph { r in
            NSColor(calibratedRed: 0.2, green: 0.5, blue: 0.95, alpha: 1).setFill()
            NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
            NSColor.white.setFill()
            for i in 0..<3 { NSBezierPath(rect: NSRect(x: r.minX + 3, y: r.minY + 3 + CGFloat(i) * 4.5, width: r.width - 6, height: 2)).fill() }
        }
        item.button?.toolTip = "Toolbar example"
        item.button?.title = "Toolbar"
        item.autosaveName = "Examples.Toolbar.status"
        let menu = NSMenu(title: "Status")
        menu.addItem(withTitle: "Show Window", action: Selector(("showWindow:")), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Show/Hide Toolbar", action: Selector(("toggleToolbarShown:")), keyEquivalent: "").target = window
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: Selector(("quit:")), keyEquivalent: "").target = self
        item.menu = menu
        statusItem = item
        statusVisible.state = item.isVisible ? .on : .off
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [AppDelegate.back, AppDelegate.forward, AppDelegate.style, AppDelegate.tint, .flexibleSpace, AppDelegate.edit, AppDelegate.preview, AppDelegate.search, .customizeToolbar]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [AppDelegate.back, AppDelegate.forward, AppDelegate.style, AppDelegate.tint, AppDelegate.edit, AppDelegate.preview, AppDelegate.search,
         .print, .showColors, .showFonts, .customizeToolbar, .space, .flexibleSpace, .separator]
    }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [AppDelegate.edit, AppDelegate.preview] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case AppDelegate.style:
            let g = NSToolbarItemGroup(itemIdentifier: id, titles: ["B", "I", "U"], selectionMode: .selectAny, labels: ["Bold", "Italic", "Underline"], target: self, action: AppDelegate.act)
            g.label = "Style"
            g.paletteLabel = "Text style"
            return g
        case AppDelegate.tint:
            let m = NSMenuToolbarItem(itemIdentifier: id)
            m.label = "Tint"
            m.image = AppDelegate.disc(.systemOrange)
            m.toolTip = "Pick a tint"
            let menu = NSMenu(title: "Tint")
            for name in ["Orange", "Teal", "Purple"] { menu.addItem(withTitle: name, action: Selector(("tintChosen:")), keyEquivalent: "").target = self }
            m.menu = menu
            return m
        case AppDelegate.search:
            let s = NSSearchToolbarItem(itemIdentifier: id)
            s.preferredWidthForSearchField = 160
            s.searchField.target = self
            s.searchField.action = Selector(("searched:"))
            return s
        default:
            let item = NSToolbarItem(itemIdentifier: id)
            item.target = self
            item.action = AppDelegate.act
            switch id {
            case AppDelegate.back: item.label = "Back"; item.image = AppDelegate.arrow(forward: false); item.isNavigational = true; item.toolTip = "Go back"
            case AppDelegate.forward: item.label = "Forward"; item.image = AppDelegate.arrow(forward: true); item.isNavigational = true; item.toolTip = "Go forward"
            case AppDelegate.edit: item.label = "Edit"; item.image = AppDelegate.pencil(); item.visibilityPriority = .high
            case AppDelegate.preview: item.label = "Preview"; item.image = AppDelegate.eye(); item.visibilityPriority = .low
            default: return nil
            }
            return item
        }
    }
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        item.itemIdentifier == AppDelegate.forward ? canGoForward : true
    }

    // MARK: Actions

    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch action {
        case AppDelegate.act:
            if let g = sender as? NSToolbarItemGroup {
                report("style: \(g.subitems.enumerated().filter { g.isSelected(at: $0.offset) }.map { $0.element.label }.joined(separator: ", "))")
            } else if let i = sender as? NSToolbarItem {
                if i.itemIdentifier == AppDelegate.back { canGoForward = true }
                if i.itemIdentifier == AppDelegate.forward { canGoForward = false }
                if i.itemIdentifier == AppDelegate.edit || i.itemIdentifier == AppDelegate.preview { toolbar.selectedItemIdentifier = i.itemIdentifier }
                toolbar.validateVisibleItems()
                report("\(i.label) clicked")
            }
        case Selector(("tintChosen:")): report("tint: \((sender as? NSMenuItem)?.title ?? "?")")
        case Selector(("searched:")): report("search: \((sender as? NSTextField)?.stringValue ?? "")")
        case Selector(("styleChanged:")):
            window.toolbarStyle = [.automatic, .expanded, .preference, .unified, .unifiedCompact][max(0, styles.indexOfSelectedItem)]
            report("toolbar style \(window.toolbarStyle)")
        case Selector(("modeChanged:")):
            toolbar.displayMode = [.iconAndLabel, .iconOnly, .labelOnly][max(0, modes.indexOfSelectedItem)]
        case Selector(("coverChanged:")):
            if coversTitleBar.state == .on { window.styleMask.insert(.fullSizeContentView); window.titlebarAppearsTransparent = true }
            else { window.styleMask.remove(.fullSizeContentView); window.titlebarAppearsTransparent = false }
        case Selector(("validate:")): toolbar.validateVisibleItems(); report("validated: Forward \(canGoForward ? "enabled" : "disabled")")
        case Selector(("statusVisibleChanged:")): statusItem?.isVisible = statusVisible.state == .on
        case Selector(("showWindow:")): window.makeKeyAndOrderFront(nil)
        case Selector(("quit:")): NSApp.terminate(sender)
        default: return false
        }
        return true
    }

    func syncModePopUp() {
        let index = [NSToolbar.DisplayMode.iconAndLabel, .iconOnly, .labelOnly].firstIndex(of: toolbar.displayMode) ?? 0
        if modes.indexOfSelectedItem != index { modes.selectItem(at: index) }
    }

    func report(_ text: String) {
        status.stringValue = text
        print(text)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
