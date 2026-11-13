import XCTest
@testable import AppKit

/// Skips a test that needs the host backend's rendered window; run with APPKITWIN_HOST_BACKEND=1 to execute it.
func requireHostBackend(_ reason: String = "needs the host backend's rendered window (APPKITWIN_HOST_BACKEND=1)") throws {
    let isHost = MainActor.assumeIsolated { Platform.backend is HostBackend }
    try XCTSkipUnless(isHost, reason)
}

/// Async-context variant: MainActor.assumeIsolated traps off the main actor.
func requireHostBackendAsync(_ reason: String = "needs the host backend's rendered window (APPKITWIN_HOST_BACKEND=1)") async throws {
    // Platform.swift picks the host backend from the environment on Windows and Linux; on Darwin the backend is always HostBackend, so the gate passes there (as the sync variant does). Read the environment here without hopping to MainActor: a hop deadlocks the async test.
    #if os(Windows) || os(Linux)
    let isHost = ProcessInfo.processInfo.environment["APPKITWIN_HOST_BACKEND"] == "1"
    #else
    let isHost = true
    #endif
    try XCTSkipUnless(isHost, reason)
}
