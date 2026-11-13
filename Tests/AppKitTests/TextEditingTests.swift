// The field editor (NSText / NSTextView): editing, navigation, selection, the text
// field's editing session, and input-method composition through the platform seam.

import XCTest
@testable import AppKit

final class TextEditingTests: XCTestCase, @unchecked Sendable {
    @MainActor private func key(_ w: NSWindow, _ chars: String, flags: NSEvent.ModifierFlags = [], plain: String? = nil) {
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil,
                                 characters: chars, charactersIgnoringModifiers: plain ?? chars, isARepeat: false, keyCode: 0)!
        w.sendEvent(e)
    }

    @MainActor private func click(_ w: NSWindow, _ p: NSPoint, count: Int = 1) {
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: count, pressure: 1)!
        w.sendEvent(down)
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: count, pressure: 0)!
        w.sendEvent(up)
    }

    func testTextViewEditingAndNavigation() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            w.contentView!.addSubview(tv)
            w.makeKeyAndOrderFront(nil)
            XCTAssertTrue(w.makeFirstResponder(tv))
            key(w, "H"); key(w, "i"); key(w, " "); key(w, "t"); key(w, "h"); key(w, "e"); key(w, "r"); key(w, "e")
            XCTAssertEqual(tv.string, "Hi there")
            XCTAssertEqual(tv.selectedRange, NSRange(location: 8, length: 0))
            key(w, "\r")
            key(w, "x")
            XCTAssertEqual(tv.string, "Hi there\nx")
            XCTAssertEqual(tv._layoutLines().count, 2)
            // Navigation: word left, shift-select, home/end, up/down.
            key(w, "\u{F702}", flags: .option)                     // word left -> before "x"
            key(w, "\u{F700}")                                      // up -> line 1
            XCTAssertEqual(tv.selectedRange.location, 0)
            key(w, "\u{F703}", flags: .option)                     // word right -> after "Hi"
            XCTAssertEqual(tv.selectedRange.location, 2)
            key(w, "\u{F703}", flags: [.shift, .option])           // select " there"
            XCTAssertEqual(tv.selectedRange, NSRange(location: 2, length: 6))
            key(w, "\u{7F}")                                        // delete selection
            XCTAssertEqual(tv.string, "Hi\nx")
            key(w, "\u{F72B}")                                      // end of document
            XCTAssertEqual(tv.selectedRange.location, 4)
            key(w, "\u{7F}"); key(w, "\u{7F}")
            XCTAssertEqual(tv.string, "Hi")
            // Select all, copy, paste.
            key(w, "a", flags: .command)
            XCTAssertEqual(tv.selectedRange, NSRange(location: 0, length: 2))
            key(w, "c", flags: .command)
            key(w, "\u{F703}")
            key(w, "v", flags: .command)
            XCTAssertEqual(tv.string, "HiHi")
            // Double-click selects a word; Escape collapses the selection.
            tv.string = "alpha beta"
            click(w, NSPoint(x: 10, y: 190), count: 2)
            XCTAssertEqual(tv.selectedRange, NSRange(location: 0, length: 5))
            key(w, "\u{1B}")
            XCTAssertEqual(tv.selectedRange.length, 0)
            w.close()
        }
    }

    func testFieldEditorCommitsAndMovesFocus() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
            let a = NSTextField(), b = NSTextField()
            a.frame = NSRect(x: 10, y: 70, width: 200, height: 24)
            b.frame = NSRect(x: 10, y: 20, width: 200, height: 24)
            a.stringValue = "first"
            var actions = 0
            let target = NSObject()
            target.setActionHandler(for: Selector(("go:"))) { _ in actions += 1 }
            a.target = target
            a.action = Selector(("go:"))
            w.contentView!.addSubview(a); w.contentView!.addSubview(b)
            w.makeKeyAndOrderFront(nil)
            // Clicking the field starts editing in the window's field editor.
            click(w, NSPoint(x: 100, y: 82))
            XCTAssertNotNil(a.currentEditor)
            XCTAssertTrue(w.firstResponder === a.currentEditor)
            XCTAssertTrue(w.fieldEditor(false, for: a) === a.currentEditor)
            key(w, "a", flags: .command)
            key(w, "n"); key(w, "e"); key(w, "w")
            XCTAssertEqual(a.stringValue, "new", "the model follows the editor")
            // Return commits and sends the action; the field stays in editing with everything selected.
            key(w, "\r")
            XCTAssertNotNil(a.currentEditor)
            XCTAssertEqual(actions, 1)
            XCTAssertEqual(a.stringValue, "new")
            XCTAssertEqual(a.currentEditor?.selectedRange, NSRange(location: 0, length: 3))
            // Tab from a moves editing to b.
            key(w, "\t")
            XCTAssertNil(a.currentEditor)
            XCTAssertNotNil(b.currentEditor)
            XCTAssertTrue(w.firstResponder === b.currentEditor)
            key(w, "z")
            XCTAssertEqual(b.stringValue, "z")
            // Clicking the other field ends b's session.
            click(w, NSPoint(x: 100, y: 82))
            XCTAssertNil(b.currentEditor)
            XCTAssertNotNil(a.currentEditor)
            XCTAssertEqual(b.stringValue, "z")
            w.close()
        }
    }

    func testMenuActionsReachTheTextView() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            tv.string = "hello world"
            w.contentView!.addSubview(tv)
            w.makeKeyAndOrderFront(nil)
            _ = w.makeFirstResponder(tv)
            let copy = NSMenuItem(title: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
            let open = NSMenuItem(title: "Open", action: Selector(("openFile:")), keyEquivalent: "o")
            // The text view is the target for editing actions only; others walk past it.
            XCTAssertTrue(NSApp._target(forAction: copy.action!) === tv)
            XCTAssertFalse(NSApp._target(forAction: open.action!) === tv)
            XCTAssertFalse(tv.validateMenuItem(copy), "nothing selected")
            tv.setSelectedRange(NSRange(location: 0, length: 5))
            XCTAssertTrue(tv.validateMenuItem(copy))
            _ = NSPasteboard.general.clearContents()
            XCTAssertTrue(NSApp.sendAction(copy.action!, to: nil, from: copy))
            XCTAssertEqual(NSPasteboard.general.string(forType: .string), "hello")
            tv.setSelectedRange(NSRange(location: 11, length: 0))
            XCTAssertTrue(NSApp.sendAction(Selector(("paste:")), to: nil, from: nil))
            XCTAssertEqual(tv.string, "hello worldhello")
            w.close()
        }
    }

    func testInputMethodCompositionThroughTheSeam() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            tv.string = "ab"
            w.contentView!.addSubview(tv)
            w.makeKeyAndOrderFront(nil)
            _ = w.makeFirstResponder(tv)
            tv.setSelectedRange(NSRange(location: 1, length: 0))
            let platform = Mirror(reflecting: w).descendant("_platform") as! HostWindow
            let input = platform.textInput()!
            XCTAssertFalse(input.hasMarkedText())
            input.setMarkedText("か", NSRange(location: 1, length: 0))
            XCTAssertTrue(input.hasMarkedText())
            XCTAssertEqual(tv.string, "aかb")
            XCTAssertEqual(tv.markedRange(), NSRange(location: 1, length: 1))
            input.setMarkedText("かん", NSRange(location: 2, length: 0))
            XCTAssertEqual(tv.string, "aかんb")
            XCTAssertNotNil(input.markedRect())
            input.insertText("漢")
            XCTAssertFalse(input.hasMarkedText())
            XCTAssertEqual(tv.string, "a漢b")
            XCTAssertEqual(tv.selectedRange, NSRange(location: 2, length: 0))
            // No text input target when a plain view is first responder.
            _ = w.makeFirstResponder(nil)
            XCTAssertNil(platform.textInput())
            w.close()
        }
    }

    func testWrappingAndSizing() {
        MainActor.assumeIsolated {
            let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 120, height: 100))
            tv.string = "one two three four five six seven"
            let lines = tv._layoutLines()
            XCTAssertGreaterThan(lines.count, 1, "wraps at the view width")
            for l in lines { XCTAssertLessThanOrEqual(l.width, 120) }
            tv.isHorizontallyResizable = true
            tv.isVerticallyResizable = true
            // AppKit's defaults keep the initial frame as the minimum and its width as the
            // maximum; a view that fits its text both ways says so.
            tv.minSize = .zero
            tv.maxSize = NSSize(width: 10_000_000, height: 10_000_000)
            tv.sizeToFit()
            XCTAssertEqual(tv._layoutLines().count, 1)
            XCTAssertGreaterThan(tv.frame.width, 120)
            XCTAssertEqual(tv.frame.height, tv._lineHeight)
        }
    }
}

