// XIM on the X11 backend (ADR-0047): the window's input context against Xlib's own input
// method (no server under Xvfb, so root-window style). Runs only with an X display and the
// X11 backend selected: tools/linux/run.sh runs it under Xvfb.

#if os(Linux)
import XCTest
import Glibc
import CX11
@testable import AppKit

final class X11InputMethodTests: XCTestCase, @unchecked Sendable {
    func testInputContextLooksUpAndCommitsIntoTheTextView() throws {
        guard ProcessInfo.processInfo.environment["DISPLAY"] != nil, let backend = MainActor.assumeIsolated({ Platform.backend as? LinuxBackend }) else {
            throw XCTSkip("needs the X11 backend")
        }
        try MainActor.assumeIsolated {
            guard backend.xim != nil else { throw XCTSkip("no input method in this locale") }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            tv.string = "ab"
            w.contentView!.addSubview(tv)
            w.makeKeyAndOrderFront(nil)
            XCTAssertTrue(w.makeFirstResponder(tv))
            let platform = Mirror(reflecting: w).descendant("_platform") as! LinuxWindow
            let context = try XCTUnwrap(platform.inputContext, "every window gets an input context")
            XCTAssertFalse(context.onTheSpot, "Xlib's own input method draws no preedit")
            context.setFocus(true)
            XCTAssertTrue(context.focused)
            // A key press for "c" looks up as text and a keysym.
            var key = XKeyEvent()
            key.type = KeyPress
            key.display = backend.display
            key.window = platform.xid
            key.keycode = UInt32(XKeysymToKeycode(backend.display, KeySym(XK_c)))
            let (status, text, keysym) = context.lookup(&key)
            XCTAssertEqual(status, XLookupBoth)
            XCTAssertEqual(text, "c")
            XCTAssertEqual(keysym, KeySym(XK_c))
            // Committed text goes to the client at the caret.
            tv.setSelectedRange(NSRange(location: 2, length: 0))
            XCTAssertTrue(context.commit("日本"))
            XCTAssertEqual(tv.string, "ab日本")
            context.changed(.deactivated, windowIsKey: true)
            XCTAssertFalse(context.focused)
            w.close()
        }
    }
}
#endif
