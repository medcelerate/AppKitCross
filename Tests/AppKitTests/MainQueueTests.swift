// The Linux event pump services the main dispatch queue and RunLoop timers (an X display
// is needed: the test skips without DISPLAY, and on macOS the host backend runs CFRunLoop).

import XCTest
@testable import AppKit

final class MainQueueTests: XCTestCase, @unchecked Sendable {
    func testPumpRunsMainQueueBlocksAndTimers() throws {
        #if os(Linux)
        guard ProcessInfo.processInfo.environment["DISPLAY"] != nil else { throw XCTSkip("no X display") }
        try MainActor.assumeIsolated {
            let backend = LinuxBackend()
            nonisolated(unsafe) var mainQueueRan = false
            nonisolated(unsafe) var timerFired = false
            // A block from another thread, and a timer on the main run loop.
            DispatchQueue.global().async {
                Thread.sleep(forTimeInterval: 0.05)
                DispatchQueue.main.async { mainQueueRan = true }
            }
            let timer = Timer(timeInterval: 0.1, repeats: false) { _ in timerFired = true }
            RunLoop.main.add(timer, forMode: .default)
            let deadline = Date(timeIntervalSinceNow: 3)
            while (!mainQueueRan || !timerFired) && Date() < deadline { backend.pump(blocking: true) }
            XCTAssertTrue(mainQueueRan, "DispatchQueue.main blocks run from the pump")
            XCTAssertTrue(timerFired, "RunLoop.main timers fire from the pump")
        }
        #else
        throw XCTSkip("Linux pump only")
        #endif
    }
}
