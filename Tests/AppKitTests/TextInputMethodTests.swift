// Input method text input (ADR-0047): scripted compositions through the platform-neutral
// session every backend drives (TSF text store edits, text-input-v3 batches, XIM preedit),
// NSTextInputContext activation, and the marked-text clauses NSTextView draws.

import XCTest
@testable import AppKit

final class TextInputMethodTests: XCTestCase, @unchecked Sendable {
    @MainActor private func window(with view: NSView) -> (NSWindow, HostWindow) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        w.contentView!.addSubview(view)
        w.makeKeyAndOrderFront(nil)
        let platform = Mirror(reflecting: w).descendant("_platform") as! HostWindow
        return (w, platform)
    }

    @MainActor private func textView(_ text: String, caret: Int) -> (NSTextView, NSWindow, HostWindow) {
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        tv.string = text
        let (w, p) = window(with: tv)
        XCTAssertTrue(w.makeFirstResponder(tv))
        tv.setSelectedRange(NSRange(location: caret, length: 0))
        return (tv, w, p)
    }

    private let none = NSRange(location: NSNotFound, length: 0)

    // MARK: Composition on NSTextView

    /// Japanese: type "nihon", convert to 日本, commit — the steps an input method takes.
    func testScriptedCompositionCommitInTextView() {
        MainActor.assumeIsolated {
            let (tv, w, p) = textView("ab", caret: 1)
            let session = p.textInput()!.session!
            session.setComposition("に", selection: NSRange(location: 1, length: 0))
            XCTAssertEqual(tv.string, "aにb")
            XCTAssertEqual(tv.markedRange(), NSRange(location: 1, length: 1))
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 2, length: 0))
            session.setComposition("にほ", selection: NSRange(location: 2, length: 0))
            session.setComposition("にほん", selection: NSRange(location: 3, length: 0))
            XCTAssertEqual(tv.string, "aにほんb")
            XCTAssertEqual(tv.markedRange(), NSRange(location: 1, length: 3))
            XCTAssertEqual(tv._markedClauses, [_TextInputClause(range: NSRange(location: 0, length: 3), thick: false)])
            // Space converts: one clause, being converted (thick).
            session.setComposition("日本", selection: NSRange(location: 2, length: 0), clauses: [_TextInputClause(range: NSRange(location: 0, length: 2), thick: true)])
            XCTAssertEqual(tv.string, "a日本b")
            XCTAssertEqual(tv.markedRange(), NSRange(location: 1, length: 2))
            XCTAssertEqual(tv._markedClauses, [_TextInputClause(range: NSRange(location: 0, length: 2), thick: true)])
            // Enter commits.
            session.commit("日本")
            XCTAssertFalse(tv.hasMarkedText())
            XCTAssertEqual(tv.markedRange().location, NSNotFound)
            XCTAssertEqual(tv.string, "a日本b")
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 3, length: 0))
            w.close()
        }
    }

    /// Escape cancels: the text is as it was before the composition.
    func testScriptedCompositionCancelInTextView() {
        MainActor.assumeIsolated {
            let (tv, w, p) = textView("ab", caret: 2)
            let session = p.textInput()!.session!
            session.setComposition("か", selection: NSRange(location: 1, length: 0))
            session.setComposition("かん", selection: NSRange(location: 2, length: 0))
            XCTAssertEqual(tv.string, "abかん")
            session.cancelComposition()
            XCTAssertFalse(tv.hasMarkedText())
            XCTAssertEqual(tv.string, "ab")
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 2, length: 0))
            w.close()
        }
    }

    /// Two clauses with the second being converted, as Microsoft IME and Mozc send them.
    func testClausesFromTheMarkedString() {
        MainActor.assumeIsolated {
            let (tv, w, p) = textView("", caret: 0)
            let session = p.textInput()!.session!
            let clauses = [_TextInputClause(range: NSRange(location: 0, length: 2), thick: false),
                           _TextInputClause(range: NSRange(location: 2, length: 2), thick: true)]
            session.setComposition("今日は雨", selection: NSRange(location: 4, length: 0), clauses: clauses)
            XCTAssertEqual(tv._markedClauses, clauses + [])
            // A marked string that names its clauses only by underline style.
            let s = NSMutableAttributedString(string: "東京都")
            s.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: 2))
            s.addAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue, range: NSRange(location: 2, length: 1))
            tv.setMarkedText(s, selectedRange: NSRange(location: 3, length: 0), replacementRange: none)
            XCTAssertEqual(tv.string, "東京都")
            XCTAssertEqual(tv._markedClauses, [_TextInputClause(range: NSRange(location: 0, length: 2), thick: false),
                                               _TextInputClause(range: NSRange(location: 2, length: 1), thick: true)])
            // A plain string with a selected range: the selection is the thick clause.
            tv.setMarkedText("abcd", selectedRange: NSRange(location: 1, length: 2), replacementRange: none)
            XCTAssertEqual(tv._markedClauses.map(\.thick), [false, true, false])
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 1, length: 2))
            w.close()
        }
    }

    /// Korean 2-set: each syllable is composed, then committed when the next one starts.
    func testHangulSyllablesCommitAsTheNextStarts() {
        MainActor.assumeIsolated {
            let (tv, w, p) = textView("", caret: 0)
            let session = p.textInput()!.session!
            session.setComposition("ㅎ", selection: NSRange(location: 1, length: 0))
            session.setComposition("하", selection: NSRange(location: 1, length: 0))
            session.setComposition("한", selection: NSRange(location: 1, length: 0))
            session.commit("한")
            session.setComposition("ㄱ", selection: NSRange(location: 1, length: 0))
            session.setComposition("그", selection: NSRange(location: 1, length: 0))
            session.setComposition("글", selection: NSRange(location: 1, length: 0))
            XCTAssertEqual(tv.string, "한글")
            XCTAssertEqual(tv.markedRange(), NSRange(location: 1, length: 1))
            session.finishComposition()
            XCTAssertEqual(tv.string, "한글")
            XCTAssertFalse(tv.hasMarkedText())
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 2, length: 0))
            w.close()
        }
    }

    // MARK: NSTextField (field editor)

    func testCompositionInTextFieldAndFocusChange() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
            let a = NSTextField(), b = NSTextField()
            a.frame = NSRect(x: 10, y: 70, width: 200, height: 24)
            b.frame = NSRect(x: 10, y: 20, width: 200, height: 24)
            a.stringValue = "x"
            w.contentView!.addSubview(a); w.contentView!.addSubview(b)
            w.makeKeyAndOrderFront(nil)
            let p = Mirror(reflecting: w).descendant("_platform") as! HostWindow
            @MainActor func click(_ point: NSPoint) {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    w.sendEvent(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!)
                }
            }
            click(NSPoint(x: 100, y: 82))
            let editor = a.currentEditor() as! NSTextView
            XCTAssertTrue(NSTextInputContext.current === editor.inputContext, "the field editor's context is current")
            editor.setSelectedRange(NSRange(location: 1, length: 0))
            let session = p.textInput()!.session!
            XCTAssertTrue(session.client as AnyObject === editor)
            session.setComposition("ね", selection: NSRange(location: 1, length: 0))
            session.setComposition("ねこ", selection: NSRange(location: 2, length: 0))
            XCTAssertEqual(editor.string, "xねこ")
            XCTAssertEqual(editor.markedRange(), NSRange(location: 1, length: 2))
            session.setComposition("猫", selection: NSRange(location: 1, length: 0), clauses: [_TextInputClause(range: NSRange(location: 0, length: 1), thick: true)])
            session.commit("猫")
            XCTAssertEqual(a.stringValue, "x猫")
            // Moving to the next field while composing keeps the composition as typed.
            session.setComposition("い", selection: NSRange(location: 1, length: 0))
            click(NSPoint(x: 100, y: 32))
            XCTAssertEqual(a.stringValue, "x猫い")
            XCTAssertFalse(editor.hasMarkedText())
            XCTAssertTrue(NSTextInputContext.current === (b.currentEditor() as! NSTextView).inputContext)
            XCTAssertTrue(p.textInputChanges.contains(.activated))
            w.close()
        }
    }

    // MARK: NSTextInputContext

    func testInputContextActivationFollowsTheKeyWindowsFirstResponder() {
        MainActor.assumeIsolated {
            let (tv, w, p) = textView("hello", caret: 5)
            let context = tv.inputContext!
            XCTAssertTrue(context.client as AnyObject === tv)
            XCTAssertTrue(tv.inputContext === context, "the view keeps its context")
            XCTAssertTrue(NSTextInputContext.current === context)
            XCTAssertNil(NSView().inputContext, "a view that is not a text input client has none")
            p.textInputChanges = []
            // Typing outside the input method tells it the text changed.
            tv.insertText(" there", replacementRange: none)
            XCTAssertTrue(p.textInputChanges.contains(.textChanged))
            // The input method's own edits are not echoed back.
            p.textInputChanges = []
            p.textInput()?.session?.setComposition("ア", selection: NSRange(location: 1, length: 0))
            XCTAssertFalse(p.textInputChanges.contains(.textChanged))
            // discardMarkedText: the input method drops it, the text stays as typed.
            context.discardMarkedText()
            XCTAssertEqual(p.textInputChanges.last, .discardComposition)
            XCTAssertFalse(tv.hasMarkedText())
            XCTAssertEqual(tv.string, "hello thereア")
            // handleEvent runs the key bindings into the client.
            let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil,
                                     characters: "!", charactersIgnoringModifiers: "!", isARepeat: false, keyCode: 0)!
            XCTAssertTrue(context.handleEvent(e))
            XCTAssertEqual(tv.string, "hello thereア!")
            context.invalidateCharacterCoordinates()
            XCTAssertEqual(p.textInputChanges.last, .layoutChanged)
            // A plain responder takes the focus: the context is deactivated.
            _ = w.makeFirstResponder(nil)
            XCTAssertNil(NSTextInputContext.current)
            XCTAssertEqual(p.textInputChanges.last, .deactivated)
            XCTAssertTrue(w.makeFirstResponder(tv))
            XCTAssertTrue(NSTextInputContext.current === context)
            w.resignKey()
            XCTAssertNil(NSTextInputContext.current, "resigning key deactivates the window's context")
            w.close()
        }
    }

    func testClickCommitsTheComposition() {
        MainActor.assumeIsolated {
            let (tv, w, p) = textView("abc", caret: 3)
            p.textInput()!.session!.setComposition("ふ", selection: NSRange(location: 1, length: 0))
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 2, y: 190), modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            w.sendEvent(down)
            XCTAssertFalse(tv.hasMarkedText())
            XCTAssertEqual(tv.string, "abcふ")
            w.close()
        }
    }

    // MARK: Text store edits (Text Services Framework)

    func testStoreEditsBecomeMarkedTextAndCommits() {
        MainActor.assumeIsolated {
            let (tv, w, p) = textView("ab", caret: 2)
            let session = p.textInput()!.session!
            @MainActor func edit(_ new: String, selection: Int, composition: NSRange?, clauses: [_TextInputClause] = []) {
                let old = session.snapshot()
                session.applyStoreEdit(from: old, newText: Array(new.utf16), selection: NSRange(location: selection, length: 0), composition: composition, clauses: clauses)
            }
            XCTAssertEqual(session.snapshot(), _TextInputSession.Snapshot(base: 0, text: Array("ab".utf16), selection: NSRange(location: 2, length: 0), marked: nil))
            edit("abに", selection: 3, composition: NSRange(location: 2, length: 1))
            XCTAssertEqual(tv.string, "abに")
            XCTAssertEqual(tv.markedRange(), NSRange(location: 2, length: 1))
            edit("abにほ", selection: 4, composition: NSRange(location: 2, length: 2))
            XCTAssertEqual(session.snapshot().marked, NSRange(location: 2, length: 2))
            edit("ab日本", selection: 4, composition: NSRange(location: 2, length: 2), clauses: [_TextInputClause(range: NSRange(location: 2, length: 2), thick: true)])
            XCTAssertEqual(tv.string, "ab日本")
            XCTAssertEqual(tv._markedClauses, [_TextInputClause(range: NSRange(location: 0, length: 2), thick: true)])
            // Committing 日本 while 語 starts a new composition in the same edit.
            edit("ab日本ご", selection: 5, composition: NSRange(location: 4, length: 1))
            XCTAssertEqual(tv.string, "ab日本ご")
            XCTAssertEqual(tv.markedRange(), NSRange(location: 4, length: 1))
            // The composition ends with its text.
            edit("ab日本語", selection: 5, composition: nil)
            XCTAssertEqual(tv.string, "ab日本語")
            XCTAssertFalse(tv.hasMarkedText())
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 5, length: 0))
            // Cancelled: the composition's text is removed again.
            edit("ab日本語か", selection: 6, composition: NSRange(location: 5, length: 1))
            edit("ab日本語", selection: 5, composition: nil)
            XCTAssertEqual(tv.string, "ab日本語")
            XCTAssertFalse(tv.hasMarkedText())
            // Reconversion: an input method replaces committed text with a new composition.
            edit("ab日本語", selection: 5, composition: NSRange(location: 2, length: 3))
            XCTAssertEqual(tv.markedRange(), NSRange(location: 2, length: 3))
            XCTAssertEqual(tv.string, "ab日本語")
            w.close()
        }
    }

    func testSnapshotOfALongDocumentIsAWindowAroundTheCaret() {
        MainActor.assumeIsolated {
            let text = String(repeating: "0123456789", count: 1000)
            let (_, w, p) = textView(text, caret: 5000)
            let s = p.textInput()!.session!.snapshot(limit: 1000)
            XCTAssertEqual(s.base, 4500)
            XCTAssertEqual(s.text.count, 1000)
            XCTAssertEqual(s.selection, NSRange(location: 500, length: 0))
            w.close()
        }
    }

    // MARK: text-input-v3 (Wayland)

    func testTextInputV3DoneBatches() {
        MainActor.assumeIsolated {
            let (tv, w, p) = textView("x", caret: 1)
            let session = p.textInput()!.session!
            var state = _TextInputSession.TextInputV3State()
            state.preedit = "にほ"; state.cursorBegin = 6; state.cursorEnd = 6
            session.apply(state)
            XCTAssertEqual(tv.string, "xにほ")
            XCTAssertEqual(tv.markedRange(), NSRange(location: 1, length: 2))
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 3, length: 0))
            // Converted with the whole preedit highlighted.
            state = .init(); state.preedit = "日本"; state.cursorBegin = 0; state.cursorEnd = 6
            session.apply(state)
            XCTAssertEqual(tv._markedClauses, [_TextInputClause(range: NSRange(location: 0, length: 2), thick: true)])
            // Commit with no new preedit.
            state = .init(); state.commit = "日本"
            session.apply(state)
            XCTAssertEqual(tv.string, "x日本")
            XCTAssertFalse(tv.hasMarkedText())
            // Delete one character (3 bytes) before the cursor and commit a replacement.
            state = .init(); state.deleteBefore = 3; state.commit = "語"
            session.apply(state)
            XCTAssertEqual(tv.string, "x日語")
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 3, length: 0))
            // A preedit then an empty done: the preedit goes away.
            state = .init(); state.preedit = "a"
            session.apply(state)
            session.apply(.init())
            XCTAssertEqual(tv.string, "x日語")
            XCTAssertFalse(tv.hasMarkedText())
            w.close()
        }
    }

    func testSurroundingTextIsUTF8AroundTheCaretWithoutThePreedit() {
        MainActor.assumeIsolated {
            let (_, w, p) = textView("ab日本cd", caret: 4)
            let session = p.textInput()!.session!
            var s = session.surroundingText()
            XCTAssertEqual(s.text, "ab日本cd")
            XCTAssertEqual(s.cursor, 8)
            XCTAssertEqual(s.anchor, 8)
            session.setComposition("ご", selection: NSRange(location: 1, length: 0))
            s = session.surroundingText()
            XCTAssertEqual(s.text, "ab日本cd", "the preedit is not part of the surrounding text")
            XCTAssertEqual(s.cursor, 8)
            // A small budget keeps whole characters on both sides.
            s = session.surroundingText(maxBytes: 7)
            XCTAssertEqual(s.text, "本cd")
            XCTAssertEqual(s.cursor, 3)
            XCTAssertEqual(_TextInputSession.utf16Offset(ofByte: 4, in: "a日b"), 2)
            XCTAssertEqual(_TextInputSession.utf16Offset(ofByte: 2, in: "a日b"), 1, "a byte inside a character stops before it")
            w.close()
        }
    }

    // MARK: XIM preedit (X11)

    func testXIMPreeditDrawCallbacks() {
        var p = _XIMPreedit()
        p.draw(caret: 1, first: 0, length: 0, text: Array("n".unicodeScalars), thick: [false])
        XCTAssertEqual(p.string, "n")
        p.draw(caret: 1, first: 0, length: 1, text: Array("に".unicodeScalars), thick: [false])
        p.draw(caret: 2, first: 1, length: 0, text: Array("ほ".unicodeScalars), thick: [false])
        p.draw(caret: 3, first: 2, length: 0, text: Array("ん".unicodeScalars), thick: [false])
        XCTAssertEqual(p.string, "にほん")
        XCTAssertEqual(p.caretUTF16, 3)
        XCTAssertEqual(p.clauses, [], "one plain clause needs no clause list")
        // Converted: 日本 highlighted, followed by an unconverted clause.
        p.draw(caret: 2, first: 0, length: 3, text: Array("日本".unicodeScalars), thick: [true, true])
        p.draw(caret: 2, first: 2, length: 0, text: Array("ご".unicodeScalars), thick: [false])
        XCTAssertEqual(p.string, "日本ご")
        XCTAssertEqual(p.clauses, [_TextInputClause(range: NSRange(location: 0, length: 2), thick: true),
                                   _TextInputClause(range: NSRange(location: 2, length: 1), thick: false)])
        // Deleted text (no string) and characters outside the BMP count two UTF-16 units.
        p.draw(caret: 0, first: 2, length: 1, text: nil, thick: [])
        XCTAssertEqual(p.string, "日本")
        p.draw(caret: 3, first: 2, length: 0, text: Array("😀".unicodeScalars), thick: [false])
        XCTAssertEqual(p.caretUTF16, 4)
        // Feedback alone changes (XIMText without a string): the clause moves.
        p.restyle(first: 0, thick: [false, true])
        XCTAssertEqual(p.thick, [false, true, false])
        p.reset()
        XCTAssertEqual(p.string, "")
    }

    func testXIMPreeditShownOnTheClient() {
        MainActor.assumeIsolated {
            let (tv, w, host) = textView("", caret: 0)
            let session = host.textInput()!.session!
            var p = _XIMPreedit()
            p.draw(caret: 2, first: 0, length: 0, text: Array("한국".unicodeScalars), thick: [false, false])
            p.show(in: session)
            XCTAssertEqual(tv.string, "한국")
            XCTAssertTrue(tv.hasMarkedText())
            p.reset()
            p.show(in: session)
            XCTAssertEqual(tv.string, "")
            XCTAssertFalse(tv.hasMarkedText())
            w.close()
        }
    }
}
