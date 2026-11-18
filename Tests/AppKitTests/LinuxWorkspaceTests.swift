// The Linux workspace (ADR-0022) against a temporary XDG tree: a stub desktop entry
// registered for text/plain in mimeapps.list is found as the handler and launched with
// the file, a PNG in a theme directory is the icon for .txt, the XDG trash receives a
// recycled file with its .trashinfo, and the process list contains this process.
// Linux only; no bus or window system needed.

import XCTest
@testable import AppKit
#if os(Linux)
import Glibc
#endif

final class LinuxWorkspaceTests: XCTestCase, @unchecked Sendable {
    #if os(Linux)
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("LinuxWorkspaceTests-\(UUID().uuidString)", isDirectory: true)

    private func write(_ relative: String, _ contents: String, executable: Bool = false) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        if executable { chmod(url.path, 0o755) }
        return url
    }

    @MainActor
    private func makeWorkspace() throws -> LinuxWorkspace {
        var env = LinuxWorkspaceEnvironment.current()
        env.home = root.path
        env.dataHome = root.appendingPathComponent("data").path
        env.dataDirs = [root.appendingPathComponent("usr-share").path]
        env.configHome = root.appendingPathComponent("config").path
        env.configDirs = []
        env.currentDesktop = ["test"]
        env.iconTheme = nil
        return LinuxWorkspace(environment: env, connectsToBus: false, windowSystem: nil)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    func testDesktopEntriesAndMimeappsResolveTheHandler() throws {
        let out = root.appendingPathComponent("opened.txt")
        let stub = try write("bin/stub.sh", "#!/bin/sh\nprintf '%s' \"$*\" > '\(out.path)'\n", executable: true)
        _ = try write("data/applications/org.example.Stub.desktop", "[Desktop Entry]\nType=Application\nName=Stub Editor\nName[de]=Stub-Editor\nExec=\(stub.path) --flag %u\nIcon=stub\nMimeType=text/plain;x-scheme-handler/stub;\n")
        _ = try write("usr-share/applications/other.desktop", "[Desktop Entry]\nType=Application\nName=Other\nExec=/bin/true %F\nMimeType=text/plain;\n")
        _ = try write("config/mimeapps.list", "[Default Applications]\ntext/plain=org.example.Stub.desktop\n")
        let txt = try write("docs/note.txt", "hi")
        try MainActor.assumeIsolated {
            let ws = try makeWorkspace()
            XCTAssertEqual(ws.database.mimeType(for: txt), "text/plain")
            XCTAssertEqual(ws.database.mimeType(forExtension: "pdf"), "application/pdf")
            XCTAssertEqual(ws.database.mimeType(for: root), "inode/directory")
            let handlers = ws.database.handlers(forMIMEType: "text/plain")
            XCTAssertEqual(handlers.map(\.id), ["org.example.Stub", "other"])
            XCTAssertEqual(handlers.first?.name, "Stub Editor")
            XCTAssertEqual(ws.applicationURLs(toOpen: .file(txt)).first?.lastPathComponent, "org.example.Stub.desktop")
            XCTAssertEqual(ws.applicationURLs(toOpen: .fileExtension("txt")).count, 2)
            XCTAssertEqual(ws.applicationURLs(toOpen: .scheme("stub")).count, 1)
            XCTAssertEqual(ws.applicationURL(withBundleIdentifier: "org.example.Stub")?.lastPathComponent, "org.example.Stub.desktop")
            XCTAssertEqual(ws.applicationURL(withBundleIdentifier: "org.example.Stub.desktop")?.lastPathComponent, "org.example.Stub.desktop")
            XCTAssertEqual(LinuxDesktopEntry.splitExec("\"/opt/my app/run\" --x \"a b\" %u"), ["/opt/my app/run", "--x", "a b", "%u"])
            XCTAssertEqual(handlers.first?.commandLine(urls: [txt]), [stub.path, "--flag", txt.absoluteString])
            // Opening the file runs the stub with the URL.
            XCTAssertTrue(ws.open(txt))
            let deadline = Date(timeIntervalSinceNow: 10)
            while !FileManager.default.fileExists(atPath: out.path), Date() < deadline { usleep(50_000) }
            XCTAssertEqual(try String(contentsOf: out, encoding: .utf8), "--flag \(txt.absoluteString)")
            // Launching with the application answers the process, listed until it exits.
            let process = try ws.open([txt], withApplicationAt: handlers.first!.url, options: PlatformLaunchOptions())
            XCTAssertEqual(process.localizedName, "Stub Editor")
            XCTAssertEqual(process.bundleIdentifier, "org.example.Stub")
            XCTAssertGreaterThan(process.processIdentifier, 0)
            XCTAssertNotNil(ws.runningApplication(withProcessIdentifier: getpid()))
            XCTAssertEqual(ws.runningApplication(withProcessIdentifier: getpid())?.processIdentifier, getpid())
            XCTAssertNotNil(ws.executableArchitecture(processIdentifier: getpid()))
            // Setting the default rewrites mimeapps.list.
            try ws.setDefaultApplication(at: handlers[1].url, toOpen: .fileExtension("txt"))
            ws.database.invalidate()
            XCTAssertEqual(ws.database.handlers(forMIMEType: "text/plain").first?.id, "other")
            let list = try String(contentsOfFile: root.appendingPathComponent("config/mimeapps.list").path, encoding: .utf8)
            XCTAssertTrue(list.contains("text/plain=other.desktop"), list)
            // No handler, no xdg-open on PATH: false, not a crash.
            var noPath = ws.environment
            noPath.path = []
            let bare = LinuxWorkspace(environment: noPath, connectsToBus: false, windowSystem: nil)
            XCTAssertFalse(bare.open(URL(string: "gopher://nowhere")!))
            XCTAssertThrowsError(try bare.open([URL(string: "gopher://nowhere")!], withApplicationAt: nil, options: PlatformLaunchOptions()))
        }
    }

    func testIconsComeFromTheThemeAndFallBackToDrawn() throws {
        // A small red PNG (the port's own encoder) as the text/plain icon of a theme that inherits from hicolor.
        let red = MainActor.assumeIsolated { NSImage(size: NSSize(width: 4, height: 4), flipped: false) { r in NSColor.red.setFill(); NSBezierPath(rect: r).fill(); return true }._cgImage(scale: 1)! }
        guard let png = Platform.imageCodec.encode(red, format: "public.png", quality: 1) else { return XCTFail("no PNG encoder") }
        _ = try write("usr-share/icons/Test/index.theme", "[Icon Theme]\nName=Test\nInherits=hicolor\nDirectories=32x32/mimetypes\n")
        try png.write(to: write("usr-share/icons/Test/32x32/mimetypes/text-plain.png", ""))
        try png.write(to: write("usr-share/icons/hicolor/48x48/places/folder.png", ""))
        _ = try write("config/gtk-3.0/settings.ini", "[Settings]\ngtk-icon-theme-name=Test\n")
        let txt = try write("docs/a.txt", "x")
        try MainActor.assumeIsolated {
            let ws = try makeWorkspace()
            XCTAssertEqual(ws.iconTheme.theme, "Test")
            guard let icon = ws.icon(for: .fileExtension("txt"), size: 32, scale: 1) else { return XCTFail("no theme icon") }
            XCTAssertEqual(icon.width, 4)
            XCTAssertNotNil(ws.icon(for: .file(path: txt.path), size: 32, scale: 1))
            XCTAssertNotNil(ws.icon(for: .folder, size: 32, scale: 1), "folder comes from the inherited hicolor")
            XCTAssertNil(ws.icon(for: .fileExtension("pdf"), size: 32, scale: 1), "nothing in the theme: the core draws one")
            // Through NSWorkspace the drawn fallback has the right size.
            XCTAssertEqual(_NSWorkspaceIcons.drawn(for: .fileExtension("pdf"), size: 32).size, NSSize(width: 32, height: 32))
        }
    }

    func testRecycleFollowsTheTrashSpecification() throws {
        let doomed = try write("docs/old.txt", "bye")
        try MainActor.assumeIsolated {
            let ws = try makeWorkspace()
            guard let moved = try ws.recycle(doomed) else { return XCTFail("no destination") }
            XCTAssertFalse(FileManager.default.fileExists(atPath: doomed.path))
            XCTAssertEqual(moved.path, root.appendingPathComponent("data/Trash/files/old.txt").path)
            let info = try String(contentsOfFile: root.appendingPathComponent("data/Trash/info/old.txt.trashinfo").path, encoding: .utf8)
            XCTAssertTrue(info.hasPrefix("[Trash Info]\nPath="))
            XCTAssertTrue(info.contains(doomed.path))
            XCTAssertTrue(info.contains("DeletionDate="))
            // A second file of the same name keeps both.
            let again = try write("docs/old.txt", "bye again")
            XCTAssertEqual(try ws.recycle(again)?.lastPathComponent, "old.2.txt")
        }
    }
    #else
    func testSkippedOffLinux() throws { throw XCTSkip("Linux only") }
    #endif
}
