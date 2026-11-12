// Workspace: NSWorkspace, NSRunningApplication and NSDockTile on the shell (ADR-0022).
// Open a URL in the default browser, reveal a file in the file manager, the icons the
// shell gives .txt, .pdf, a folder and this application, recycle a temporary file, a
// badge on the taskbar button, the frontmost application as it changes, and launching,
// activating, hiding and terminating another application by its identifier.
//
// `--report` prints what the workspace answers without a window (CI and the PC checklist).
// `--open <url> --stay <seconds>` opens the URL right after launch and keeps the window
// (and the workspace's hooks and poll timer) running that long before quitting: the
// Windows CI opens a stub-handled URL this way and checks the process survives.

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
    /// The application Launch started, the only one Activate, Hide and Terminate act on:
    /// matched by its process identifier, never by name, so an instance the user already
    /// had running (with unsaved work, say) is never touched.
    var launched: NSRunningApplication?
    /// The processes running before Launch: one of them answering for the launch (a
    /// single-instance application, like Windows 11's Notepad, takes the request itself)
    /// is the user's instance, and the demo leaves it alone.
    var runningBeforeLaunch: Set<pid_t> = []

    static let act = Selector(("workspaceAction:"))
    /// `--open` / `--stay` (see the header).
    static var openOnLaunch: URL?
    static var stay: TimeInterval?

    #if os(Windows)
    // charmap allows several instances; notepad (packaged, single-instance) would hand
    // Launch to an instance already running, which the demo then refuses to touch.
    static let defaultApplication = "charmap"
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
        if let url = AppDelegate.openOnLaunch { report("open \(url): \(NSWorkspace.shared.open(url))") }
        if let stay = AppDelegate.stay {
            Timer.scheduledTimer(withTimeInterval: stay, repeats: false) { _ in
                MainActor.assumeIsolated {
                    self.report("alive after \(stay) s: \(NSWorkspace.shared.runningApplications.count) running applications, frontmost \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "none")")
                    NSApp.terminate(nil)
                }
            }
        }
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
            let exe = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).standardizedFileURL
            ws.activateFileViewerSelecting([exe])
            // The same reveal through the API that answers, so the log says whether the
            // shell took it (activateFileViewerSelecting returns nothing, as AppKit's).
            report("revealed \(exe.path): \(ws.selectFile(exe.path, inFileViewerRootedAtPath: exe.deletingLastPathComponent().path))")
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
            let before = Set(ws.runningApplications.map(\.processIdentifier))
            ws.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, error in
                MainActor.assumeIsolated {
                    guard let app else { self.report("launch failed: \(error.map { "\($0)" } ?? "?")"); return }
                    self.launched = app
                    self.runningBeforeLaunch = before
                    if before.contains(app.processIdentifier) {
                        self.report("launch of \(id) went to the instance already running, \(app.localizedName ?? "?") (pid \(app.processIdentifier)): a single-instance application; Activate, Hide and Terminate will not touch it. Quit it first, or launch one that allows several instances (charmap, msinfo32).")
                    } else {
                        self.report("launched \(app.localizedName ?? "?") (pid \(app.processIdentifier)) from \(url.path)")
                    }
                }
            }
        case 8, 9, 10:
            // Only the instance Launch started, found again by its process identifier.
            guard let pid = launched?.processIdentifier else { report("nothing launched yet: press Launch first"); return true }
            guard let app = ws.runningApplications.first(where: { $0.processIdentifier == pid }) ?? (launched?.isTerminated == false ? launched : nil) else {
                report("the launched application (pid \(pid)) is no longer running")
                launched = nil
                return true
            }
            let name = app.localizedName ?? appField.stringValue
            // A launch a running instance took (or a stub that handed off to one) is the
            // user's instance, perhaps with unsaved work: never acted on.
            guard !runningBeforeLaunch.contains(app.processIdentifier) else {
                report("\(name) (pid \(app.processIdentifier)) was already running before Launch: not touching it")
                return true
            }
            switch button.tag {
            case 8: report("activate \(name) (pid \(pid)): \(app.activate(options: []))")
            case 9: report("\(app.isHidden ? "unhide" : "hide") \(name) (pid \(pid)): \(app.isHidden ? app.unhide() : app.hide())")
            default: report("terminate \(name) (pid \(pid)): \(app.terminate())")
            }
        default:
            return false
        }
        return true
    }

    func report(_ text: String) {
        status.stringValue = text
        log.string = (log.string.isEmpty ? "" : log.string + "\n") + text
        // Unbuffered, so the line is on the console even if the process dies right after.
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
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
    print("icon application: \(current.icon.map { "\(Int($0.size.width))x\(Int($0.size.height)) pt" } ?? "none")")
    print("type of \(temp.path): \((try? ws.type(ofFile: temp.path)) ?? "?")")
    print("handler for .txt: \(ws.urlForApplication(toOpen: temp.appendingPathComponent("x.txt"))?.path ?? "none")")
    print("handler for https: \(ws.urlForApplication(toOpen: URL(string: "https://example.com")!)?.path ?? "none")")
    print("default application '\(AppDelegate.defaultApplication)': \(ws.urlForApplication(withBundleIdentifier: AppDelegate.defaultApplication)?.path ?? "none")")
    print(AppDelegate.accessibilityLine())
    print("desktop picture: \(NSScreen.main.flatMap { ws.desktopImageURL(for: $0) }?.path ?? "none")")
}

let app = NSApplication.shared
let arguments = CommandLine.arguments
if let i = arguments.firstIndex(of: "--open"), i + 1 < arguments.count { AppDelegate.openOnLaunch = URL(string: arguments[i + 1]) }
if let i = arguments.firstIndex(of: "--stay"), i + 1 < arguments.count { AppDelegate.stay = TimeInterval(arguments[i + 1]) }
if arguments.contains("--report") {
    MainActor.assumeIsolated { printReport() }
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
