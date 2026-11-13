import XCTest
@testable import AppKit

/// Skips a test that needs the host backend's rendered window; run with APPKITWIN_HOST_BACKEND=1 to execute it.
func requireHostBackend(_ reason: String = "needs the host backend's rendered window (APPKITWIN_HOST_BACKEND=1)") throws {
    let isHost = MainActor.assumeIsolated { Platform.backend is HostBackend }
    try XCTSkipUnless(isHost, reason)
}

/// Async-context variant: MainActor.assumeIsolated traps off the main actor.
func requireHostBackendAsync(_ reason: String = "needs the host backend's rendered window (APPKITWIN_HOST_BACKEND=1)") async throws {
    // The host backend is selected by the environment alone (Platform.swift), so read it here without hopping to MainActor: a hop deadlocks the async test.
    let isHost = ProcessInfo.processInfo.environment["APPKITWIN_HOST_BACKEND"] == "1"
    try XCTSkipUnless(isHost, reason)
}
