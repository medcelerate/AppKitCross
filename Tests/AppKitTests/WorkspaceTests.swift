// NSWorkspace, NSRunningApplication and NSDockTile on the host backend's in-memory
// workspace (ADR-0022): opening and revealing reach the platform, file types go through
// UniformTypeIdentifiers, icons are the platform's or drawn, the trash and duplicates
// land where they should, the running applications follow the platform's events with
// the workspace notifications, and the dock tile's badge reaches the taskbar seam.

import XCTest
import UniformTypeIdentifiers
@testable import AppKit

/// Notification names seen, collected from any thread.
final class _NotificationLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    func removeAll() { lock.lock(); items.removeAll(); lock.unlock() }
    var entries: [String] { lock.lock(); defer { lock.unlock() }; return items }
    var count: Int { entries.count }
}

final class WorkspaceTests: XCTestCase, @unchecked Sendable {
    @MainActor private var host: HostWorkspace { HostWorkspace.shared }
    private var observers: [NSObjectProtocol] = []
    private let temp = FileManager.default.temporaryDirectory.appendingPathComponent("WorkspaceTests-\(UUID().uuidString)", isDirectory: true)

    override func setUpWithError() throws {
        try requireHostBackend("needs the host workspace stub (APPKITWIN_HOST_BACKEND=1)")
    }

    /// True where the tests run against the host workspace stub: the host backend on Windows and Linux, and always on Darwin (Platform.swift).
    /// Keyed on the backend, not the environment, so the Darwin CI run, which sets no APPKITWIN_HOST_BACKEND, keeps its setup.
    private var hasHostBackend: Bool { MainActor.assumeIsolated { Platform.backend is HostBackend } }

    override func setUp() {
        super.setUp()
        // Skipped tests reach setUp too: touch NSApplication and the shared workspace only when the test runs.
        guard hasHostBackend else { return }
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            host.reset()
        }
    }

    override func tearDown() {
        for o in observers { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        observers.removeAll()
        try? FileManager.default.removeItem(at: temp)
        if hasHostBackend { MainActor.assumeIsolated { host.reset() } }
        super.tearDown()
    }

    private func file(_ name: String, _ contents: String = "hello") -> URL {
        let url = temp.appendingPathComponent(name)
        try? contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Collects the workspace notifications named, as "<short name>:<pid>" entries.
    private func record(_ names: [NSNotification.Name], into log: _NotificationLog) {
        for n in names {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: n, object: nil, queue: nil) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let short = n.rawValue.replacingOccurrences(of: "NSWorkspace", with: "").replacingOccurrences(of: "Notification", with: "")
                log.add(app.map { "\(short):\($0.processIdentifier)" } ?? short)
            })
        }
    }

    func testSharedWorkspaceAndNotificationNames() throws {
        try requireHostBackend("needs the host workspace stub (APPKITWIN_HOST_BACKEND=1)")
        XCTAssertTrue(NSWorkspace.shared === NSWorkspace.shared)
        XCTAssertEqual(NSWorkspace.didActivateApplicationNotification.rawValue, "NSWorkspaceDidActivateApplicationNotification")
        XCTAssertEqual(NSWorkspace.applicationUserInfoKey, "NSWorkspaceApplicationKey")
        XCTAssertEqual(NSWorkspace.volumeURLUserInfoKey, "NSWorkspaceVolumeURLKey")
        XCTAssertTrue(NSWorkspace.shared.notificationCenter !== NotificationCenter.default)
        XCTAssertTrue(NSWorkspace.shared.notificationCenter === NSWorkspace.shared.notificationCenter)
    }

    func testRunningApplicationsContainTheCurrentApplication() throws {
        try requireHostBackend("needs the host workspace stub (APPKITWIN_HOST_BACKEND=1)")
        MainActor.assumeIsolated {
            let current = NSRunningApplication.current
            XCTAssertTrue(current === NSRunningApplication.current)
            XCTAssertEqual(current.processIdentifier, ProcessInfo.processInfo.processIdentifier)
            XCTAssertNotNil(current.localizedName)
            XCTAssertNotNil(current.executableURL)
            XCTAssertFalse(current.isTerminated)
            XCTAssertEqual(current.activationPolicy, .regular)
            XCTAssertNotEqual(current.executableArchitecture, 0)
            XCTAssertTrue(NSWorkspace.shared.runningApplications.contains { $0 === current })
            XCTAssertTrue(NSWorkspace.shared.runningApplications.contains(current))
            XCTAssertNotNil(NSRunningApplication(processIdentifier: current.processIdentifier))
            XCTAssertNil(NSRunningApplication(processIdentifier: 1_999_999_999))
            // The current application's activation follows NSApp.
            NSApplication.shared.activate(ignoringOtherApps: true)
            XCTAssertTrue(current.isActive)
            XCTAssertTrue(current.ownsMenuBar)
            NSApplication.shared.deactivate()
            XCTAssertFalse(current.isActive)
            XCTAssertTrue(current.activate(options: []))
            XCTAssertTrue(NSApplication.shared.isActive)
            XCTAssertTrue(NSWorkspace.shared.frontmostApplication === current)
            XCTAssertTrue(NSWorkspace.shared.menuBarOwningApplication === current)
            XCTAssertEqual(NSWorkspace.shared.activeApplication()?["NSApplicationProcessIdentifier"] as? Int, Int(current.processIdentifier))
            XCTAssertNotNil(current.icon)
        }
    }

    func testOpeningURLsReachesThePlatform() throws {
        try requireHostBackend("needs the host workspace stub (APPKITWIN_HOST_BACKEND=1)")
        MainActor.assumeIsolated {
            let url = URL(string: "https://example.com/")!
            XCTAssertTrue(NSWorkspace.shared.open(url))
            XCTAssertEqual(host.openedURLs, [url])
            let txt = file("a.txt")
            XCTAssertTrue(NSWorkspace.shared.openFile(txt.path))
            XCTAssertEqual(host.openedURLs.last, txt)
            host.opensSucceed = false
            XCTAssertFalse(NSWorkspace.shared.open(url))
            // Revealing in the file manager.
            host.opensSucceed = true
            NSWorkspace.shared.activateFileViewerSelecting([txt])
            XCTAssertEqual(host.revealedURLs, [txt])
            XCTAssertTrue(NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: temp.path))
            XCTAssertEqual(host.revealedURLs.last?.path, temp.path)
            NSWorkspace.shared.noteFileSystemChanged(temp.path)
            XCTAssertEqual(host.fileSystemNotes, [temp.path])
        }
    }

    func testOpeningWithAnApplicationLaunchesAndReportsTheProcess() async throws {
        try await requireHostBackendAsync("needs the host workspace stub (APPKITWIN_HOST_BACKEND=1)")
        let app = file("editor", "#!/bin/sh\n")
        let txt = file("b.txt")
        let log = _NotificationLog()
        record([NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification], into: log)
        await MainActor.run { host.handlers[.fileExtension("txt")] = [app] }
        XCTAssertEqual(NSWorkspace.shared.urlForApplication(toOpen: txt), app)
        XCTAssertEqual(NSWorkspace.shared.urlsForApplications(toOpen: txt), [app])
        XCTAssertEqual(NSWorkspace.shared.urlForApplication(toOpen: UTType.plainText), app)
        XCTAssertNil(NSWorkspace.shared.urlForApplication(toOpen: URL(string: "mailto:x@y")!))
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--new-window"]
        configuration.activates = false
        let running = try await NSWorkspace.shared.open(txt, configuration: configuration)
        XCTAssertEqual(running.executableURL, app)
        XCTAssertEqual(running.localizedName, "editor")
        XCTAssertFalse(running.isTerminated)
        await MainActor.run {
            XCTAssertEqual(host.launches.count, 1)
            XCTAssertEqual(host.launches.last?.urls, [txt])
            XCTAssertEqual(host.launches.last?.options.arguments, ["--new-window"])
            XCTAssertFalse(host.launches.last?.options.activates ?? true)
            XCTAssertEqual(log.entries, ["DidLaunchApplication:\(running.processIdentifier)"])
            // The workspace hands out the same object for the process.
            XCTAssertTrue(NSWorkspace.shared.runningApplications.contains { $0 === running })
            XCTAssertEqual(NSRunningApplication.runningApplications(withBundleIdentifier: "editor").count, 1)
        }
        // Launching an application directly, and the completion-handler form.
        let second = try await NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        XCTAssertTrue(second === running, "allowsRunningApplicationSubstitution reuses the running instance")
        let fresh = NSWorkspace.OpenConfiguration()
        fresh.createsNewApplicationInstance = true
        let third = try await NSWorkspace.shared.openApplication(at: app, configuration: fresh)
        XCTAssertFalse(third === running)
        let done = expectation(description: "completion")
        NSWorkspace.shared.open([txt], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { app, error in
            XCTAssertNotNil(app); XCTAssertNil(error); done.fulfill()
        }
        await fulfillment(of: [done], timeout: 5)
        // No handler: the error.
        do {
            _ = try await NSWorkspace.shared.open(URL(string: "gopher://x")!, configuration: NSWorkspace.OpenConfiguration())
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue("\(error)".contains("no application"))
        }
        // The deprecated forms.
        XCTAssertNotNil(try NSWorkspace.shared.open(txt, options: [.withoutActivation], configuration: [:]))
        XCTAssertTrue(NSWorkspace.shared.openFile(txt.path, withApplication: app.path))
        await MainActor.run { host.applicationsByIdentifier["com.example.editor"] = app }
        XCTAssertEqual(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.example.editor"), app)
        XCTAssertEqual(NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: "com.example.editor"), app.path)
        XCTAssertEqual(NSWorkspace.shared.fullPath(forApplication: "com.example.editor"), app.path)
        XCTAssertTrue(NSWorkspace.shared.launchApplication("com.example.editor"))
        XCTAssertFalse(NSWorkspace.shared.launchApplication("com.example.nothing"))
        try await NSWorkspace.shared.setDefaultApplication(at: URL(fileURLWithPath: "/opt/other"), toOpen: .plainText)
        XCTAssertEqual(NSWorkspace.shared.urlForApplication(toOpen: txt)?.path, "/opt/other")
    }

    func testOpenConfigurationCopies() throws {
        try requireHostBackend("needs the host workspace stub (APPKITWIN_HOST_BACKEND=1)")
        let c = NSWorkspace.OpenConfiguration()
        XCTAssertTrue(c.activates); XCTAssertTrue(c.promptsUserIfNeeded); XCTAssertTrue(c.allowsRunningApplicationSubstitution)
        XCTAssertFalse(c.hides); XCTAssertFalse(c.createsNewApplicationInstance)
        c.arguments = ["a"]; c.environment = ["K": "V"]; c.hidesOthers = true
        let copy = c.copy() as! NSWorkspace.OpenConfiguration
        XCTAssertEqual(copy.arguments, ["a"]); XCTAssertEqual(copy.environment, ["K": "V"]); XCTAssertTrue(copy.hidesOthers)
        XCTAssertFalse(copy === c)
    }

    func testIconsComeFromThePlatformOrAreDrawn() throws {
        try requireHostBackend("needs the host workspace stub (APPKITWIN_HOST_BACKEND=1)")
        MainActor.assumeIsolated {
            let txt = NSWorkspace.shared.icon(forFileType: "txt")
            XCTAssertEqual(txt.size, NSSize(width: 32, height: 32))
            XCTAssertTrue(NSWorkspace.shared.icon(forFileType: "txt") === txt, "cached")
            XCTAssertEqual(host.iconRequests.first, .fileExtension("txt"))
            guard let pixels = txt._cgImage(scale: 2) else { return XCTFail("no pixels") }
            XCTAssertEqual(pixels.width, 64)
            let data = _pixels(pixels)
            var opaque = 0
            for i in stride(from: 3, to: data.count, by: 4) where data[i] > 0 { opaque += 1 }
            XCTAssertGreaterThan(opaque, 64 * 64 / 4, "the drawn document covers a good part of the icon")
            // A folder, a file, a UTType.
            let folder = NSWorkspace.shared.icon(forFile: temp.path)
            XCTAssertEqual(host.iconRequests.last, .folder)
            XCTAssertTrue(NSWorkspace.shared.icon(for: .folder) === folder)
            let f = file("c.pdf")
            _ = NSWorkspace.shared.icon(forFile: f.path)
            XCTAssertEqual(host.iconRequests.last, .file(path: f.path))
            _ = NSWorkspace.shared.icon(forFile: temp.appendingPathComponent("missing.png").path)
            XCTAssertEqual(host.iconRequests.last, .fileExtension("png"))
            _ = NSWorkspace.shared.icon(for: UTType.pdf)
            XCTAssertEqual(host.iconRequests.last, .fileExtension("pdf"))
            XCTAssertTrue(NSWorkspace.shared.icon(forFileType: "com.adobe.pdf") === NSWorkspace.shared.icon(for: UTType.pdf))
            // The platform's own pixels are used when it has some.
            let platformIcon = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { r in NSColor.red.setFill(); NSBezierPath(rect: r).fill(); return true }._cgImage(scale: 2)!
            host.icons[.fileExtension("zzz")] = platformIcon
            let zzz = NSWorkspace.shared.icon(forFileType: "zzz")
            XCTAssertEqual(zzz.size, NSSize(width: 32, height: 32))
            XCTAssertTrue(zzz._cgImage(scale: 2) === platformIcon)
            XCTAssertNotNil(NSWorkspace.shared.icon(forFiles: [f.path, temp.path]))
            XCTAssertNil(NSWorkspace.shared.icon(forFiles: []))
        }
    }

    func testFileTypesGoThroughUniformTypeIdentifiers() throws {
        try requireHostBackend("needs the host workspace stub (APPKITWIN_HOST_BACKEND=1)")
        let txt = file("d.txt")
        XCTAssertEqual(try NSWorkspace.shared.type(ofFile: txt.path), "public.plain-text")
        XCTAssertEqual(try NSWorkspace.shared.type(ofFile: temp.path), "public.folder")
        XCTAssertEqual(try NSWorkspace.shared.type(ofFile: file("noext").path), "public.data")
        XCTAssertThrowsError(try NSWorkspace.shared.type(ofFile: temp.appendingPathComponent("nope").path))
        XCTAssertEqual(NSWorkspace.shared.preferredFilenameExtension(forType: "public.plain-text"), "txt")
        XCTAssertTrue(NSWorkspace.shared.filenameExtension("txt", isValidForType: "public.plain-text"))
        XCTAssertTrue(NSWorkspace.shared.filenameExtension("txt", isValidForType: "public.text"))
        XCTAssertFalse(NSWorkspace.shared.filenameExtension("png", isValidForType: "public.plain-text"))
        XCTAssertTrue(NSWorkspace.shared.type("public.plain-text", conformsToType: "public.data"))
        XCTAssertFalse(NSWorkspace.shared.type("public.png", conformsToType: "public.text"))
        XCTAssertEqual(NSWorkspace.shared.localizedDescription(forType: "com.adobe.pdf")?.lowercased().contains("pdf"), true)
        // Packages: a directory whose extension names a package type.
        let app = temp.appendingPathComponent("Thing.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        XCTAssertTrue(NSWorkspace.shared.isFilePackage(atPath: app.path))
        XCTAssertFalse(NSWorkspace.shared.isFilePackage(atPath: temp.path))
        XCTAssertFalse(NSWorkspace.shared.isFilePackage(atPath: txt.path))
        var application: NSString? = nil, type: NSString? = nil
        XCTAssertTrue(NSWorkspace.shared.getInfoForFile(txt.path, application: &application, type: &type))
        XCTAssertEqual(type, "txt")
        XCTAssertNotNil(NSWorkspace.shared.mountedLocalVolumePaths())
    }

    func testRecycleAndDuplicate() async throws {
        try await requireHostBackendAsync("needs the host workspace stub (APPKITWIN_HOST_BACKEND=1)")
        let a = file("e.txt"), b = file("f.txt")
        let log = _NotificationLog()
        record([NSWorkspace.didPerformFileOperationNotification], into: log)
        let recycled = try await NSWorkspace.shared.recycle([a, b])
        XCTAssertEqual(recycled.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        let trash = await MainActor.run { host.trashURL }
        XCTAssertEqual(recycled[a]?.deletingLastPathComponent().path, trash.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recycled[a]!.path))
        XCTAssertEqual(log.count, 1)
        do {
            _ = try await NSWorkspace.shared.recycle([a])
            XCTFail("a missing file cannot be recycled")
        } catch let error as NSError {
            XCTAssertEqual(error.code, NSFileNoSuchFileError)
        }
        let c = file("g.txt", "copy me")
        let copies = try await NSWorkspace.shared.duplicate([c])
        XCTAssertEqual(copies[c]?.lastPathComponent, "g copy.txt")
        XCTAssertEqual(try String(contentsOf: copies[c]!, encoding: .utf8), "copy me")
        let again = try await NSWorkspace.shared.duplicate([c])
        XCTAssertEqual(again[c]?.lastPathComponent, "g copy 2.txt")
        let done = expectation(description: "recycled")
        NSWorkspace.shared.recycle([c]) { result, error in
            XCTAssertNil(error); XCTAssertEqual(result.count, 1); done.fulfill()
        }
        await fulfillment(of: [done], timeout: 5)
        XCTAssertTrue(NSWorkspace.shared.performFileOperation(.destroyOperation, source: temp.path, destination: "", files: ["g copy.txt"], tag: nil))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.appendingPathComponent("g copy.txt").path))
    }

    /// What the Workspace example does on the PC: an observer of didDeactivate asks for the
    /// frontmost application, which refreshes the list mid-notification. The change must
    /// already be recorded, or the refresh posts it again without end (a stack overflow on
    /// Windows, inside the foreground hook's callback).
    func testHandOffKeepsTheLaunchedApplicationObject() throws {
        try requireHostBackend("needs the host workspace stub (APPKITWIN_HOST_BACKEND=1)")
        MainActor.assumeIsolated {
            _ = NSWorkspace.shared.runningApplications
            let stub = PlatformRunningApplication(processIdentifier: 5151, localizedName: "notepad", bundleIdentifier: "notepad", executableURL: URL(fileURLWithPath: "/w/System32/notepad.exe"))
            host.otherApplications.append(stub)
            host.postEvent(.applicationDidLaunch(stub))
            guard let launched = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == 5151 }) else { return XCTFail("the stub is not listed") }
            let seen = _NotificationLog()
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { note in
                    seen.add("\(name.rawValue):\((note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier ?? -1)")
                })
            }
            // The stub exits; the package's Notepad.exe takes over.
            let real = PlatformRunningApplication(processIdentifier: 5152, localizedName: "Notepad", bundleIdentifier: "Microsoft.WindowsNotepad_8wekyb3d8bbwe!App",
                                                  executableURL: URL(fileURLWithPath: "/w/WindowsApps/Notepad/Notepad.exe"), launchDate: Date())
            host.otherApplications = host.otherApplications.filter { $0.processIdentifier != 5151 } + [real]
            host.postEvent(.applicationDidHandOff(fromProcessIdentifier: 5151, to: real))
            XCTAssertEqual(launched.processIdentifier, 5152)
            XCTAssertEqual(launched.localizedName, "Notepad")
            XCTAssertFalse(launched.isTerminated)
            XCTAssertTrue(NSWorkspace.shared.runningApplications.first { $0.processIdentifier == 5152 } === launched, "the same object stands for the real process")
            XCTAssertNil(NSWorkspace.shared.runningApplications.first { $0.processIdentifier == 5151 })
            XCTAssertEqual(seen.entries, [], "a hand-off is neither a launch nor a termination")
            // Terminating the real process ends the object the caller held.
            host.otherApplications = host.otherApplications.filter { $0.processIdentifier != 5152 }
            host.postEvent(.applicationDidTerminate(processIdentifier: 5152))
            XCTAssertTrue(launched.isTerminated)
            XCTAssertEqual(seen.entries, ["NSWorkspaceDidTerminateApplicationNotification:5152"])
        }
    }

    /// A single-instance application already running takes the launch: the stub's hand-off
    /// goes to that process, whose object (the user's instance) is left alone; the stub's
    /// object terminates.
    func testHandOffToARunningInstanceLeavesThatInstanceAlone() throws {
        try requireHostBackend("needs the host workspace stub (APPKITWIN_HOST_BACKEND=1)")
        MainActor.assumeIsolated {
            _ = NSWorkspace.shared.runningApplications
            let users = PlatformRunningApplication(processIdentifier: 2416, localizedName: "Notepad", bundleIdentifier: "Microsoft.WindowsNotepad_8wekyb3d8bbwe!App",
                                                   executableURL: URL(fileURLWithPath: "/w/WindowsApps/Notepad/Notepad.exe"), launchDate: Date(timeIntervalSinceNow: -600))
            host.otherApplications.append(users)
            host.postEvent(.applicationDidLaunch(users))
            guard let existing = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == 2416 }) else { return XCTFail("the running instance is not listed") }
            let stub = PlatformRunningApplication(processIdentifier: 5151, localizedName: "notepad", bundleIdentifier: "notepad", executableURL: URL(fileURLWithPath: "/w/System32/notepad.exe"))
            host.otherApplications.append(stub)
            host.postEvent(.applicationDidLaunch(stub))
            guard let launched = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == 5151 }) else { return XCTFail("the stub is not listed") }
            let seen = _NotificationLog()
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { note in
                    seen.add("\(name.rawValue):\((note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier ?? -1)")
                })
            }
            host.otherApplications = host.otherApplications.filter { $0.processIdentifier != 5151 }
            host.postEvent(.applicationDidHandOff(fromProcessIdentifier: 5151, to: users))
            XCTAssertTrue(NSWorkspace.shared.runningApplications.first { $0.processIdentifier == 2416 } === existing, "the user's instance keeps its object")
            XCTAssertFalse(existing.isTerminated)
            XCTAssertTrue(launched.isTerminated, "the stub exited")
            XCTAssertEqual(launched.processIdentifier, 5151, "the stub's object never comes to stand for the running instance")
            XCTAssertEqual(seen.entries, ["NSWorkspaceDidTerminateApplicationNotification:5151"])
        }
    }

    /// The platform answers a launch with a process that was already running (the
    /// activation manager names the single instance): the workspace returns that process's
    /// existing object, as AppKit does, and posts no launch.
    func testLaunchAnsweredByARunningInstanceReturnsItsObject() async throws {
        try await requireHostBackendAsync("needs the host workspace stub (APPKITWIN_HOST_BACKEND=1)")
        let app = file("notepad", "#!/bin/sh\n")
        let users = PlatformRunningApplication(processIdentifier: 2416, localizedName: "Notepad", bundleIdentifier: "Microsoft.WindowsNotepad_8wekyb3d8bbwe!App",
                                               executableURL: URL(fileURLWithPath: "/w/WindowsApps/Notepad/Notepad.exe"), launchDate: Date(timeIntervalSinceNow: -600))
        let existing: NSRunningApplication? = await MainActor.run {
            _ = NSWorkspace.shared.runningApplications
            host.otherApplications.append(users)
            host.postEvent(.applicationDidLaunch(users))
            host.launchResolvesTo = 2416
            return NSWorkspace.shared.runningApplications.first { $0.processIdentifier == 2416 }
        }
        let log = _NotificationLog()
        record([NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification], into: log)
        let fresh = NSWorkspace.OpenConfiguration()
        fresh.createsNewApplicationInstance = true
        let running = try await NSWorkspace.shared.openApplication(at: app, configuration: fresh)
        XCTAssertEqual(running.processIdentifier, 2416)
        XCTAssertTrue(running === existing, "the object for the running instance")
        XCTAssertFalse(running.isTerminated)
        await MainActor.run {
            XCTAssertEqual(host.launches.count, 1)
            XCTAssertEqual(log.entries, [], "an instance already running was not launched")
            XCTAssertEqual(NSWorkspace.shared.runningApplications.filter { $0.processIdentifier == 2416 }.count, 1)
        }
    }

    func testObserverAskingForTheFrontmostApplicationDoesNotRecurse() throws {
        try requireHostBackend("needs the host workspace stub (APPKITWIN_HOST_BACKEND=1)")
        MainActor.assumeIsolated {
            NSApplication.shared.activate(ignoringOtherApps: true)
            _ = NSWorkspace.shared.runningApplications
            var other = PlatformRunningApplication(processIdentifier: 4343, localizedName: "Notepad", bundleIdentifier: "notepad", executableURL: URL(fileURLWithPath: "/w/notepad.exe"))
            host.otherApplications.append(other)
            host.postEvent(.applicationDidLaunch(other))
            let seen = _NotificationLog()
            for name in [NSWorkspace.didDeactivateApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
                observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { note in
                    let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier ?? -1
                    seen.add("\(name.rawValue):\(pid)")
                    // Re-enters the workspace from inside the notification, as the example's
                    // "Frontmost:" label does.
                    _ = NSWorkspace.shared.frontmostApplication
                    _ = NSWorkspace.shared.runningApplications
                })
            }
            // Notepad comes to the front.
            other.isActive = true
            host.otherApplications = [other]
            host.postEvent(.applicationDidActivate(processIdentifier: 4343))
            let me = NSRunningApplication.current.processIdentifier
            XCTAssertEqual(seen.entries, ["NSWorkspaceDidDeactivateApplicationNotification:\(me)", "NSWorkspaceDidActivateApplicationNotification:4343"])
            XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, 4343)
            XCTAssertFalse(NSApplication.shared.isActive)
            // And back.
            other.isActive = false
            host.otherApplications = [other]
            seen.removeAll()
            host.postEvent(.applicationDidActivate(processIdentifier: me))
            XCTAssertEqual(seen.entries, ["NSWorkspaceDidDeactivateApplicationNotification:4343", "NSWorkspaceDidActivateApplicationNotification:\(me)"])
            XCTAssertTrue(NSWorkspace.shared.frontmostApplication === NSRunningApplication.current)
        }
    }

    func testApplicationNotificationsFollowThePlatform() throws {
        try requireHostBackend("needs the host workspace stub (APPKITWIN_HOST_BACKEND=1)")
        MainActor.assumeIsolated {
            let log = _NotificationLog()
            record([NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification, NSWorkspace.didDeactivateApplicationNotification,
                    NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification, NSWorkspace.didTerminateApplicationNotification], into: log)
            NSApplication.shared.activate(ignoringOtherApps: true)
            _ = NSWorkspace.shared.runningApplications
            log.removeAll()
            let me = NSRunningApplication.current.processIdentifier
            // Another application appears and comes to the front.
            let other = PlatformRunningApplication(processIdentifier: 4242, localizedName: "Notepad", bundleIdentifier: "notepad", executableURL: URL(fileURLWithPath: "/w/notepad.exe"))
            host.otherApplications.append(other)
            host.postEvent(.applicationDidLaunch(other))
            let apps = NSWorkspace.shared.runningApplications
            guard let notepad = apps.first(where: { $0.processIdentifier == 4242 }) else { return XCTFail("not listed") }
            XCTAssertEqual(notepad.localizedName, "Notepad")
            XCTAssertEqual(notepad.bundleIdentifier, "notepad")
            XCTAssertFalse(notepad.isActive)
            XCTAssertTrue(notepad.activate(options: []))
            XCTAssertEqual(host.activated, [4242])
            XCTAssertTrue(notepad.isActive)
            XCTAssertFalse(NSRunningApplication.current.isActive == true && NSWorkspace.shared.frontmostApplication === NSRunningApplication.current)
            XCTAssertTrue(NSWorkspace.shared.frontmostApplication === notepad)
            XCTAssertEqual(log.entries, ["DidLaunchApplication:4242", "DidDeactivateApplication:\(me)", "DidActivateApplication:4242"])
            log.removeAll()
            // Hide, unhide, through the application object and through the workspace.
            XCTAssertTrue(notepad.hide())
            XCTAssertTrue(notepad.isHidden)
            XCTAssertTrue(notepad.unhide())
            XCTAssertFalse(notepad.isHidden)
            NSWorkspace.shared.hideOtherApplications()
            XCTAssertTrue(notepad.isHidden)
            NSApplication.shared.unhideAllApplications(nil)
            XCTAssertFalse(notepad.isHidden)
            XCTAssertEqual(log.entries, ["DidHideApplication:4242", "DidUnhideApplication:4242", "DidHideApplication:4242", "DidUnhideApplication:4242"])
            log.removeAll()
            // This application comes back to the front, then the other one terminates.
            NSApplication.shared.activate(ignoringOtherApps: true)
            XCTAssertEqual(log.entries, ["DidDeactivateApplication:4242", "DidActivateApplication:\(me)"])
            log.removeAll()
            XCTAssertTrue(notepad.terminate())
            XCTAssertEqual(host.terminated.last?.0, 4242)
            XCTAssertEqual(host.terminated.last?.1, false)
            XCTAssertTrue(notepad.isTerminated)
            XCTAssertFalse(notepad.isActive)
            XCTAssertFalse(notepad.terminate())
            XCTAssertFalse(NSWorkspace.shared.runningApplications.contains { $0.processIdentifier == 4242 })
            XCTAssertEqual(log.entries, ["DidTerminateApplication:4242"])
            // A process that vanished without an event is noticed on the next refresh.
            let silent = PlatformRunningApplication(processIdentifier: 4343, localizedName: "Silent")
            host.otherApplications.append(silent)
            log.removeAll()
            guard let s = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == 4343 }) else { return XCTFail() }
            XCTAssertEqual(log.entries, ["DidLaunchApplication:4343"])
            host.otherApplications.removeAll()
            _ = NSWorkspace.shared.runningApplications
            XCTAssertTrue(s.isTerminated)
            XCTAssertEqual(log.entries, ["DidLaunchApplication:4343", "DidTerminateApplication:4343"])
            XCTAssertTrue(s.forceTerminate() == false)
        }
    }

    func testPowerSessionAndAccessibilityNotifications() throws {
        try requireHostBackend("needs the host workspace stub (APPKITWIN_HOST_BACKEND=1)")
        MainActor.assumeIsolated {
            let log = _NotificationLog()
            record([NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification,
                    NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification], into: log)
            XCTAssertTrue(host.isMonitoring)
            XCTAssertFalse(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            XCTAssertFalse(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
            XCTAssertFalse(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
            XCTAssertFalse(NSWorkspace.shared.isVoiceOverEnabled)
            host.accessibilityDisplayOptions.reduceMotion = true
            host.accessibilityDisplayOptions.increaseContrast = true
            host.accessibilityDisplayOptions.voiceOverEnabled = true
            host.postEvent(.accessibilityDisplayOptionsDidChange)
            XCTAssertTrue(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            XCTAssertTrue(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
            XCTAssertTrue(NSWorkspace.shared.isVoiceOverEnabled)
            for e in [PlatformWorkspaceEvent.willSleep, .didWake, .screensDidSleep, .screensDidWake, .sessionDidResignActive, .sessionDidBecomeActive] { host.postEvent(e) }
            XCTAssertEqual(log.entries, ["AccessibilityDisplayOptionsDidChange", "WillSleep", "DidWake", "ScreensDidSleep", "ScreensDidWake", "SessionDidResignActive", "SessionDidBecomeActive"])
            // The desktop picture.
            let wallpaper = URL(fileURLWithPath: "/pictures/w.png")
            XCTAssertNil(NSWorkspace.shared.desktopImageURL(for: NSScreen.main!))
            do { try NSWorkspace.shared.setDesktopImageURL(wallpaper, for: NSScreen.main!) } catch { XCTFail("\(error)") }
            XCTAssertEqual(NSWorkspace.shared.desktopImageURL(for: NSScreen.main!), wallpaper)
        }
    }

    func testDockTileBadgeReachesTheTaskbar() throws {
        try requireHostBackend("needs the host workspace stub (APPKITWIN_HOST_BACKEND=1)")
        MainActor.assumeIsolated {
            let tile = NSApplication.shared.dockTile
            XCTAssertTrue(tile === NSApplication.shared.dockTile)
            XCTAssertTrue(tile.owner === NSApplication.shared)
            XCTAssertEqual(tile.size, NSSize(width: 128, height: 128))
            XCTAssertNil(tile.badgeLabel)
            XCTAssertTrue(tile.showsApplicationBadge)
            tile.badgeLabel = "3"
            XCTAssertEqual(tile.badgeLabel, "3")
            guard let shown = host.dockTiles.last else { return XCTFail("nothing reached the platform") }
            XCTAssertEqual(shown.badgeLabel, "3")
            XCTAssertEqual(shown.scale, NSScreen.main?.backingScaleFactor)
            guard let overlay = shown.badgeOverlay else { return XCTFail("no overlay") }
            XCTAssertEqual(overlay.height, Int(16 * shown.scale))
            XCTAssertGreaterThanOrEqual(overlay.width, overlay.height)
            XCTAssertNil(shown.icon, "no icon of its own: the platform keeps the executable's")
            // A longer label widens the pill.
            tile.badgeLabel = "1,234"
            XCTAssertGreaterThan(host.dockTiles.last!.badgeOverlay!.width, overlay.width)
            // Hiding the badge clears it; an empty label too.
            tile.showsApplicationBadge = false
            XCTAssertNil(host.dockTiles.last?.badgeLabel)
            XCTAssertNil(host.dockTiles.last?.badgeOverlay)
            tile.showsApplicationBadge = true
            tile.badgeLabel = ""
            XCTAssertNil(host.dockTiles.last?.badgeLabel)
            // A content view becomes the icon, with the badge in its corner.
            let view = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.green.cgColor
            tile.contentView = view
            tile.badgeLabel = "7"
            tile.display()
            guard let icon = host.dockTiles.last?.icon else { return XCTFail("no icon") }
            XCTAssertEqual(icon.width, Int(128 * shown.scale))
            XCTAssertEqual(view.frame.size, tile.size, "the view is laid out at the tile's size")
            tile.contentView = nil
            // The application icon image is the tile's icon when set.
            NSApplication.shared.applicationIconImage = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { r in NSColor.blue.setFill(); NSBezierPath(rect: r).fill(); return true }
            XCTAssertNotNil(host.dockTiles.last?.icon)
            XCTAssertTrue(NSRunningApplication.current.icon === NSApplication.shared.applicationIconImage)
            NSApplication.shared.applicationIconImage = nil
            tile.badgeLabel = nil
            // A window's tile exists but shows nothing on these platforms.
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let count = host.dockTiles.count
            window.dockTile.badgeLabel = "x"
            XCTAssertTrue(window.dockTile.owner === window)
            XCTAssertEqual(host.dockTiles.count, count)
            window.close()
        }
    }
}

