// ServiceManagement (ADR-0043): SMAppService over the XDG autostart backend in a temporary
// config directory (every platform; macOS builds the module as ServiceManagementPortable),
// and over a fake backend for the error paths.

import XCTest
#if canImport(ServiceManagementPortable)
@testable import ServiceManagementPortable
#else
@testable import ServiceManagement
#endif

final class FakeLoginItemBackend: LoginItemBackend, @unchecked Sendable {
    var current: SMAppService.Status = .notRegistered
    var failure: Error?
    var opened = 0
    func status() -> SMAppService.Status { current }
    func register() throws {
        if let failure { throw failure }
        current = .enabled
    }
    func unregister() throws {
        if let failure { throw failure }
        current = .notRegistered
    }
    func openSettings() { opened += 1 }
}

final class ServiceManagementTests: XCTestCase {
    var directory: URL!
    let identity = LoginItemIdentity(identifier: "com.example.Daily To-Do", displayName: "Daily To Do", executablePath: "/opt/Daily To Do/bin/daily%todo")

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("autostart-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRegisterWritesAnAutostartEntryAndStatusReadsItBack() throws {
        let backend = XDGAutostartBackend(directory: directory, identity: identity)
        let service = SMAppService(backend: backend)
        XCTAssertEqual(service.status, .notRegistered)
        try service.register()
        XCTAssertEqual(service.status, .enabled)

        XCTAssertEqual(backend.entryURL.lastPathComponent, "com.example.Daily_To-Do.desktop")
        let text = try String(contentsOf: backend.entryURL, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("[Desktop Entry]\nType=Application\n"))
        XCTAssertTrue(text.contains("Name=Daily To Do\n"))
        // Quoted for the space, `%` doubled, and the quoting's backslash-free result string-escaped.
        XCTAssertTrue(text.contains("Exec=\"/opt/Daily To Do/bin/daily%%todo\"\n"), text)
        XCTAssertEqual(XDGAutostartBackend.parse(text)["X-AppKitCross-LoginItem"], "com.example.Daily To-Do")

        try service.unregister()
        XCTAssertEqual(service.status, .notRegistered)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backend.entryURL.path))
    }

    func testEntryTheUserSwitchedOffRequiresApproval() throws {
        let backend = XDGAutostartBackend(directory: directory, identity: identity)
        try backend.register()
        var text = try String(contentsOf: backend.entryURL, encoding: .utf8)
        text = text.replacingOccurrences(of: "X-GNOME-Autostart-enabled=true", with: "X-GNOME-Autostart-enabled=false")
        try text.write(to: backend.entryURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(backend.status(), .requiresApproval)
        try (text + "Hidden=true\n").replacingOccurrences(of: "=false", with: "=true").write(to: backend.entryURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(backend.status(), .requiresApproval)
    }

    func testEntryForAnotherExecutableIsNotOurs() throws {
        let other = XDGAutostartBackend(directory: directory, identity: LoginItemIdentity(identifier: identity.identifier, displayName: "Old", executablePath: "/old/place/app"))
        try other.register()
        let backend = XDGAutostartBackend(directory: directory, identity: identity)
        XCTAssertEqual(backend.status(), .notRegistered)
        try backend.register()
        XCTAssertEqual(backend.status(), .enabled)
    }

    func testExecQuotingRoundTrips() {
        for path in ["/usr/bin/app", "/opt/My App/app", "/weird/$dollar \"quote\"/back\\slash", "/p/100%"] {
            let quoted = XDGAutostartBackend.quoteExecArgument(path)
            let unescaped = XDGAutostartBackend.unescapeString(quoted)
            XCTAssertEqual(XDGAutostartBackend.program(ofExec: unescaped), path, quoted)
        }
        XCTAssertEqual(XDGAutostartBackend.quoteExecArgument("/usr/bin/app"), "/usr/bin/app")
    }

    func testDefaultDirectoryFollowsXDGConfigHome() {
        XCTAssertEqual(XDGAutostartBackend.defaultDirectory(environment: ["XDG_CONFIG_HOME": "/cfg", "HOME": "/home/u"]).path, "/cfg/autostart")
        XCTAssertEqual(XDGAutostartBackend.defaultDirectory(environment: ["XDG_CONFIG_HOME": "relative", "HOME": "/home/u"]).path, "/home/u/.config/autostart")
        XCTAssertEqual(XDGAutostartBackend.defaultDirectory(environment: ["HOME": "/home/u"]).path, "/home/u/.config/autostart")
    }

    func testOpenSettingsFallsBackToTheAutostartFolder() {
        let backend = XDGAutostartBackend(directory: directory, identity: identity)
        var launched: [(String, [String])] = []
        backend.launcher = { program, args in launched.append((program, args)); return program == "xdg-open" }
        backend.openSettings()
        XCTAssertEqual(launched.last?.0, "xdg-open")
        XCTAssertEqual(launched.last?.1, [directory.path])
    }

    func testErrorsCarryServiceManagementCodes() {
        let fake = FakeLoginItemBackend()
        let service = SMAppService(backend: fake)
        XCTAssertThrowsError(try service.unregister()) {
            XCTAssertEqual(($0 as NSError).code, kSMErrorJobNotFound)
        }
        fake.failure = CocoaError(.fileWriteNoPermission)
        XCTAssertThrowsError(try service.register()) {
            let error = $0 as NSError
            XCTAssertEqual(error.code, kSMErrorInternalFailure)
            XCTAssertNotNil(error.userInfo[NSUnderlyingErrorKey])
        }
        fake.failure = nil
        XCTAssertNoThrow(try service.register())
        XCTAssertEqual(service.status, .enabled)
        let done = expectation(description: "unregistered")
        service.unregister { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(service.status, .notRegistered)
        XCTAssertEqual(SMAppService.Status.requiresApproval.rawValue, 2)
    }
}
