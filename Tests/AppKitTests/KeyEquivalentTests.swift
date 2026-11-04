// Key equivalents on buttons: plain keys, shifted characters and the modifier mask.

import XCTest
@testable import AppKit

final class KeyEquivalentTests: XCTestCase, @unchecked Sendable {
    @MainActor private final class Receiver: NSObject, NSSelectorHandling {
        var clicks = 0
        static let press = Selector(("press:"))
        func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
            guard action == Receiver.press else { return false }
            clicks += 1
            return true
        }
    }

    @MainActor private func key(_ c: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: c, charactersIgnoringModifiers: c, isARepeat: false, keyCode: 0)!
    }

    func testPlainAndShiftedCharacters() {
        MainActor.assumeIsolated {
            let log = Receiver()
            let times = NSButton(title: "×", target: log, action: Receiver.press)
            times.keyEquivalent = "*"
            times.keyEquivalentModifierMask = []
            XCTAssertTrue(times.performKeyEquivalent(with: key("*", [.shift])), "Shift-8 types *, so the shift is implied")
            XCTAssertTrue(times.performKeyEquivalent(with: key("*", [])), "the keypad * needs no shift")
            XCTAssertFalse(times.performKeyEquivalent(with: key("*", [.command])))
            XCTAssertEqual(log.clicks, 2)
            let seven = NSButton(title: "7", target: nil, action: nil)
            seven.keyEquivalent = "7"
            seven.keyEquivalentModifierMask = []
            XCTAssertTrue(seven.performKeyEquivalent(with: key("7", [])))
            XCTAssertFalse(seven.performKeyEquivalent(with: key("7", [.command])), "Cmd-7 is not the plain 7")
            let letter = NSButton(title: "Clear", target: nil, action: nil)
            letter.keyEquivalent = "c"
            letter.keyEquivalentModifierMask = []
            XCTAssertFalse(letter.performKeyEquivalent(with: key("c", [.shift])), "a letter never implies Shift")
        }
    }
}
