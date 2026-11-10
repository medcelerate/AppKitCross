// Workspace: NSWorkspace, NSRunningApplication and NSDockTile on the shell (ADR-0022).
// Open a URL in the default browser, reveal a file in the file manager, the icons the
// shell gives .txt, .pdf, a folder and this application, recycle a temporary file, a
// badge on the taskbar button, the frontmost application as it changes, and launching,
// activating, hiding and terminating another application by its identifier.
//
// `--report` prints what the workspace answers without a window (CI and the PC checklist).

import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSSelectorHandling {
    var window: NSWindow!
    var urlField: NSTextField!
    var appField: NSTextField!
    var frontmost: NSTextField!
    var status: NSTextField!
    var log: NSTextView!
    var badgeCount = 0
    var observers: [NSObjectProtocol] = []

    static let act = Selector(("workspaceAction:"))

    #if os(Windows)
    static let defaultApplication = "notepad"
    #elseif os(Linux)
    static let defaultApplication = "org.gnome.TextEditor"
    #else
    static let defaultApplication = "com.apple.TextEdit"
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Workspace"
        window.isReleasedWhenClosed = false
        window.contentView = makeContent()
        window.center()
        window.makeKeyAndOrderFront(nil)
        observe()
        updateFrontmost()
        report("ready: \(NSWorkspace.shared.runningApplications.count) running applications")
    }

    func installMenu() {
        let menu = NSMenu(title: "Main")
        let app = NSMenuItem(title: "Workspace", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "Workspace")
        appMenu.addItem(withTitle: "Quit", action: Selector(("quit:")), keyEquivalent: "q")
        app.submenu = appMenu
        menu.addItem(app)
        NSApp.mainMenu = menu
    }

    func makeContent() -> NSView {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 520))
        let stack = NSStackView(frame: NSRect(x: 20, y: 20, width: 640, height: 480))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.autoresizingMask = [.width, .height]
        content.addSubview(stack)

        func button(_ title: String, _ tag: Int) -> NSButton {
            let b = NSButton(title: title, target: self, action: AppDelegate.act)
            b.tag = tag
            return b
        }
        func row(_ views: [NSView]) -> NSStackView {
            let r = NSStackView()
            r.orientation = .horizontal
            r.spacing = 8
            for v in views { r.addArrangedSubview(v) }
            return r
        }

        urlField = NSTextField(string: "https://www.swift.org/")
        urlField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        stack.addArrangedSubview(row([NSTextField(labelWithString: "URL:"), urlField, button("Open", 1)]))
        stack.addArrangedSubview(row([button("Reveal this executable in the file manager", 2), button("Open the temporary folder", 3)]))

        // Icons: .txt, .pdf, a folder, this application.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let icons: [(String, NSImage?)] = [
            (".txt", NSWorkspace.shared.icon(forFileType: "txt")),
            (".pdf", NSWorkspace.shared.icon(for: UTType.pdf)),
            ("folder", NSWorkspace.shared.icon(forFile: home)),
            ("this app", NSRunningApplication.current.icon),
        ]
        var iconViews: [NSView] = [NSTextField(labelWithString: "Icons:")]
        for (label, image) in icons {
            let v = NSImageView(frame: NSRect(x: 0, y: 0, width: 48, height: 48))
            v.image = image
            v.imageScaling = .scaleProportionallyUpOrDown
            let column = NSStackView()
            column.orientation = .vertical
            column.alignment = .centerX
            column.addArrangedSubview(v)
            column.addArrangedSubview(NSTextField(labelWithString: label))
            iconViews.append(column)
        }
        stack.addArrangedSubview(row(iconViews))

        stack.addArrangedSubview(row([button("Recycle a temporary file", 4), button("Badge +1", 5), button("Clear badge", 6)]))

        appField = NSTextField(string: AppDelegate.defaultApplication)
        appField.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        stack.addArrangedSubview(row([NSTextField(labelWithString: "Application:"), appField, button("Launch", 7), button("Activate", 8), button("Hide", 9), button("Terminate", 10)]))

        frontmost = NSTextField(labelWithString: "Frontmost: …")
        stack.addArrangedSubview(frontmost)
        status = NSTextField(labelWithString: "")
        stack.addArrangedSubview(status)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 200))
        log = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 200))
        log.isEditable = false
        log.autoresizingMask = [.width]
        scroll.documentView = log
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        stack.addArrangedSubview(scroll)
        return content
    }

    func observe() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didDeactivateApplicationNotification,
                                            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                                            NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                                            NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                                            NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification,
                                            NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification,
                                            NSWorkspace.accessibilityDisplayOptionsDidChangeNotification]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let short = name.rawValue.replacingOccurrences(of: "NSWorkspace", with: "").replacingOccurrences(of: "Notification", with: "")
                MainActor.assumeIsolated {
                    self?.report("\(short)" + (app.map { " \($0.localizedName ?? "?") (pid \($0.processIdentifier))" } ?? ""))
                    if name == NSWorkspace.didActivateApplicationNotification || name == NSWorkspace.didDeactivateApplicationNotification { self?.updateFrontmost() }
                    if name == NSWorkspace.accessibilityDisplayOptionsDidChangeNotification { self?.report(AppDelegate.accessibilityLine()) }
                }
            })
        }
    }

    static func accessibilityLine() -> String {
        let ws = NSWorkspace.shared
        return "accessibility: reduce motion \(ws.accessibilityDisplayShouldReduceMotion), increase contrast \(ws.accessibilityDisplayShouldIncreaseContrast), reduce transparency \(ws.accessibilityDisplayShouldReduceTransparency), screen reader \(ws.isVoiceOverEnabled)"
    }

    func updateFrontmost() {
        if let app = NSWorkspace.shared.frontmostApplication {
            frontmost.stringValue = "Frontmost: \(app.localizedName ?? "?") (pid \(app.processIdentifier), \(app.bundleIdentifier ?? "no identifier"))"
        } else {
            frontmost.stringValue = "Frontmost: none"
        }
    }

    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        if action == Selector(("quit:")) { NSApp.terminate(sender); return true }
        guard action == AppDelegate.act, let button = sender as? NSButton else { return false }
        let ws = NSWorkspace.shared
        switch button.tag {
        case 1:
            guard let url = URL(string: urlField.stringValue) else { report("not a URL"); return true }
            report("open \(url): \(ws.open(url))")
        case 2:
            let exe = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            ws.activateFileViewerSelecting([exe])
            report("revealed \(exe.path)")
        case 3:
            report("open folder: \(ws.selectFile(nil, inFileViewerRootedAtPath: FileManager.default.temporaryDirectory.path))")
        case 4:
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("AppKitCross-recycle-me-\(Int(Date().timeIntervalSince1970)).txt")
            try? "Recycle me".write(to: file, atomically: true, encoding: .utf8)
            ws.recycle([file]) { moved, error in
                MainActor.assumeIsolated {
                    if let error { self.report("recycle failed: \(error)") }
                    else { self.report("recycled \(file.lastPathComponent)" + (moved[file].map { " -> \($0.path)" } ?? " (into the Recycle Bin)")) }
                }
            }
        case 5:
            badgeCount += 1
            NSApp.dockTile.badgeLabel = "\(badgeCount)"
            report("badge \(badgeCount)")
        case 6:
            badgeCount = 0
            NSApp.dockTile.badgeLabel = nil
            report("badge cleared")
        case 7:
            let id = appField.stringValue
            guard let url = ws.urlForApplication(withBundleIdentifier: id) else { report("no application for '\(id)'"); return true }
            ws.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, error in
                MainActor.assumeIsolated {
                    if let app { self.report("launched \(app.localizedName ?? "?") (pid \(app.processIdentifier)) from \(url.path)") }
                    else { self.report("launch failed: \(error.map { "\($0)" } ?? "?")") }
                }
            }
        case 8, 9, 10:
            let id = appField.stringValue
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            guard let app = apps.first else { report("'\(id)' is not running (\(ws.runningApplications.compactMap(\.bundleIdentifier).joined(separator: ", ")))"); return true }
            switch button.tag {
            case 8: report("activate \(app.localizedName ?? id): \(app.activate(options: []))")
            case 9: report("\(app.isHidden ? "unhide" : "hide") \(app.localizedName ?? id): \(app.isHidden ? app.unhide() : app.hide())")
            default: report("terminate \(app.localizedName ?? id): \(app.terminate())")
            }
        default:
            return false
        }
        return true
    }

    func report(_ text: String) {
        status.stringValue = text
        log.string = (log.string.isEmpty ? "" : log.string + "\n") + text
        print(text)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// `--report`: the workspace's answers, headless.
@MainActor
func printReport() {
    let ws = NSWorkspace.shared
    let current = NSRunningApplication.current
    print("current: \(current.localizedName ?? "?") pid \(current.processIdentifier) id \(current.bundleIdentifier ?? "none") exe \(current.executableURL?.path ?? "?")")
    let apps = ws.runningApplications
    print("running applications: \(apps.count), contains current: \(apps.contains(current))")
    for app in apps.prefix(12) { print("  \(app.processIdentifier) \(app.localizedName ?? "?") [\(app.bundleIdentifier ?? "-")] active=\(app.isActive) hidden=\(app.isHidden)") }
    print("frontmost: \(ws.frontmostApplication?.localizedName ?? "none")")
    let temp = FileManager.default.temporaryDirectory
    for ext in ["txt", "pdf"] {
        let icon = ws.icon(forFileType: ext)
        print("icon .\(ext): \(Int(icon.size.width))x\(Int(icon.size.height)) pt")
    }
    print("icon folder: \(ws.icon(forFile: temp.path).size)")
    print("type of \(temp.path): \((try? ws.type(ofFile: temp.path)) ?? "?")")
    print("handler for .txt: \(ws.urlForApplication(toOpen: temp.appendingPathComponent("x.txt"))?.path ?? "none")")
    print("handler for https: \(ws.urlForApplication(toOpen: URL(string: "https://example.com")!)?.path ?? "none")")
    print("default application '\(AppDelegate.defaultApplication)': \(ws.urlForApplication(withBundleIdentifier: AppDelegate.defaultApplication)?.path ?? "none")")
    print(AppDelegate.accessibilityLine())
    print("desktop picture: \(NSScreen.main.flatMap { ws.desktopImageURL(for: $0) }?.path ?? "none")")
}

let app = NSApplication.shared
if CommandLine.arguments.contains("--report") {
    MainActor.assumeIsolated { printReport() }
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
