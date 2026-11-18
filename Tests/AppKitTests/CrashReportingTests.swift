import XCTest
import Foundation
@testable import AppKit

/// ADR-0046: the crash report seam. A real crash is checked end to end in CI (the
/// Dependent example under APPKITWIN_CRASH_TEST); here the report writer runs without
/// crashing, and the directory and switch logic are checked on every platform.
final class CrashReportingTests: XCTestCase {
    func testReportsDirectoryFollowsThePlatform() {
        let id = "com.example.CrashTest"
        let override = PlatformCrashReporting.reportsDirectory(bundleIdentifier: id, environment: ["APPKITWIN_CRASH_DIR": "/tmp/x"])
        XCTAssertTrue(override.path.hasSuffix("tmp/x"), override.path)
        #if os(Windows)
        let dir = PlatformCrashReporting.reportsDirectory(bundleIdentifier: id, environment: ["LOCALAPPDATA": "C:\\Users\\u\\AppData\\Local"])
        XCTAssertTrue(dir.path.hasSuffix("AppData/Local/com.example.CrashTest/Crashes") || dir.path.hasSuffix("AppData\\Local\\com.example.CrashTest\\Crashes"), dir.path)
        #else
        let xdg = PlatformCrashReporting.reportsDirectory(bundleIdentifier: id, environment: ["XDG_DATA_HOME": "/data", "HOME": "/home/u"])
        XCTAssertEqual(xdg.path, "/data/com.example.CrashTest/Crashes")
        let home = PlatformCrashReporting.reportsDirectory(bundleIdentifier: id, environment: ["HOME": "/home/u"])
        XCTAssertEqual(home.path, "/home/u/.local/share/com.example.CrashTest/Crashes")
        // A relative XDG_DATA_HOME is invalid by the spec and ignored.
        let relative = PlatformCrashReporting.reportsDirectory(bundleIdentifier: id, environment: ["XDG_DATA_HOME": "rel", "HOME": "/home/u"])
        XCTAssertEqual(relative.path, "/home/u/.local/share/com.example.CrashTest/Crashes")
        #endif
    }

    func testCrashTestSwitch() {
        XCTAssertNil(PlatformCrashReporting.requestedCrashTest([:]))
        XCTAssertNil(PlatformCrashReporting.requestedCrashTest(["APPKITWIN_CRASH_TEST": "0"]))
        XCTAssertEqual(PlatformCrashReporting.requestedCrashTest(["APPKITWIN_CRASH_TEST": "1"]), 0)
        XCTAssertEqual(PlatformCrashReporting.requestedCrashTest(["APPKITWIN_CRASH_TEST": "segv"]), 0)
        XCTAssertEqual(PlatformCrashReporting.requestedCrashTest(["APPKITWIN_CRASH_TEST": "trap"]), 1)
        XCTAssertEqual(PlatformCrashReporting.requestedCrashTest(["APPKITWIN_CRASH_TEST": "abort"]), 2)
    }

    @MainActor func testNoHandlerUnderXCTest() {
        // NSApplication.init asks for the handler; the test runner keeps its own.
        _ = NSApplication.shared
        XCTAssertFalse(PlatformCrashReporting.isInstalled)
    }

    func testWriteReportWithoutCrashing() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("appkitcross-crash-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(PlatformCrashReporting.configure(directory: dir))
        XCTAssertTrue(PlatformCrashReporting.writeReport(reason: "unit test"))
        let report = try XCTUnwrap(PlatformCrashReporting.lastReport)
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.path), report.path)
        XCTAssertEqual(report.pathExtension, "txt")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".txt") }, [report.lastPathComponent])
        let text = try String(contentsOf: report, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("AppKitCross crash report"), text)
        XCTAssertTrue(text.contains("Reason: unit test"), text)
        XCTAssertTrue(text.contains("Backtrace"), text)
        #if os(Windows)
        // The minidump sits next to the text report.
        let dump = report.deletingPathExtension().appendingPathExtension("dmp")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dump.path), dump.path)
        #else
        // backtrace_symbols_fd names this test binary among the frames.
        XCTAssertTrue(text.contains("0x"), text)
        #endif
    }
}
