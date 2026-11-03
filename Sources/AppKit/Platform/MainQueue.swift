// The main dispatch queue and the main run loop on platforms where AppKit owns the event
// loop. Apple's AppKit runs inside CFRunLoop, which services both; the Win32 and Linux
// backends run their own loops, so they wait on the main queue's wake handle alongside
// window events, drain the queue with libdispatch's run-loop hook (the one CoreFoundation
// uses), and step the main RunLoop for its timers. Without this, DispatchQueue.main,
// @MainActor hops from other threads and Timer never fire in a running app.

#if os(Linux) || os(Windows)
import Foundation
import Dispatch

#if os(Windows)
import WinSDK
@_silgen_name("_dispatch_get_main_queue_handle_4CF") private func _dispatchMainQueueHandle() -> HANDLE?
#else
@_silgen_name("_dispatch_get_main_queue_handle_4CF") private func _dispatchMainQueueHandle() -> Int32
#endif
@_silgen_name("_dispatch_main_queue_callback_4CF") private func _dispatchMainQueueCallback(_ msg: UnsafeMutableRawPointer?)

@MainActor
enum PlatformMainQueue {
    #if os(Windows)
    /// Signalled when the main queue has work; wait on it with the message queue.
    static let handle: HANDLE? = _dispatchMainQueueHandle()
    #else
    /// Readable when the main queue has work; poll it with the display connection.
    static let fileDescriptor: Int32 = _dispatchMainQueueHandle()
    #endif

    /// Runs every block queued on the main queue, then the main run loop's ready timers
    /// and sources. Returns how long the caller may wait before the next timer is due
    /// (nil: no timer pending).
    @discardableResult
    static func service() -> TimeInterval? {
        _dispatchMainQueueCallback(nil)
        let loop = RunLoop.main
        _ = loop.run(mode: .default, before: Date())
        guard let next = loop.limitDate(forMode: .default) else { return nil }
        let interval = next.timeIntervalSinceNow
        return interval == .infinity || interval > 86_400 ? nil : max(0, interval)
    }
}
#endif
