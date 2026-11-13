import XCTest
import Foundation
#if canImport(CoreText)
import CoreText
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import AppKit

/// swift-corelibs-foundation reads a Swift object's CF type ID from bits 8-17 of its first
/// stored word (see Support/CFBridgeLayout.swift). A value whose first word is a pointer
/// gets a type ID from its heap address, and CFEqual halts when that decodes to 0: an
/// intermittent "Illegal instruction" in Foundation when two such values sit in adjacent
/// attributed-string runs (the layout manager's CoreText string). Every class that is an
/// attribute value must start with a fixed, non-zero CF info word.
final class CFBridgeLayoutTests: XCTestCase, @unchecked Sendable {
    #if !canImport(Darwin)
    /// The CF type ID corelibs reads from an object, or nil when the value is not an
    /// NSObject (it is boxed, and the box's first word is the value's address).
    private func cfTypeID(_ object: AnyObject) -> UInt64? {
        guard object is NSObject else { return nil }
        let word = Unmanaged.passUnretained(object).toOpaque().load(fromByteOffset: 16, as: UInt64.self)
        return (word >> 8) & 0x3FF
    }

    func testAttributeValuesHaveAFixedCFTypeID() {
        MainActor.assumeIsolated {
            let values: [(String, AnyObject)] = [
                // What NSLayoutManager puts in its CoreText string.
                ("CTFont", CTFontCreateWithName("Helvetica" as CFString, 12, nil)),
                ("CGColor", CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)),
                ("CTParagraphStyle", CTParagraphStyleCreate(nil, 0)),
                ("CTTextTab", CTTextTabCreate(.left, 28, nil)),
                // AppKit's attribute values (PR 56).
                ("NSColor", NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)),
                ("NSFont", NSFont.systemFont(ofSize: 12)),
                ("NSParagraphStyle", NSMutableParagraphStyle()),
                ("NSTextAttachment", NSTextAttachment()),
                ("NSTextTab", NSTextTab(textAlignment: .left, location: 0)),
                ("NSTextList", NSTextList(markerFormat: .disc, options: 0)),
                ("NSTextBlock", NSTextBlock()),
                ("NSCursor", NSCursor.arrow),
            ]
            for (name, value) in values {
                let id = cfTypeID(value)
                XCTAssertNotNil(id, "\(name) is an NSObject, so corelibs does not box it")
                XCTAssertEqual(id, 0x3FF, "\(name)'s first stored word is the fixed CF info word")
            }
        }
    }

    /// Distinct values side by side, as the layout manager's CoreText string holds them.
    func testDistinctCoreTextValuesInAdjacentRuns() {
        let pairs: [(String, Any, Any)] = [
            ("fonts", CTFontCreateWithName("Helvetica" as CFString, 12, nil), CTFontCreateWithName("Helvetica" as CFString, 14, nil)),
            ("colours", CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1), CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)),
            ("paragraph styles", CTParagraphStyleCreate(nil, 0), CTParagraphStyleCreate(nil, 0)),
        ]
        for (name, a, b) in pairs {
            let s = NSMutableAttributedString(string: "ab")
            let k = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
            s.addAttributes([k: a], range: NSRange(location: 0, length: 1))
            s.addAttributes([k: b], range: NSRange(location: 1, length: 1))
            var runs = 0
            s.enumerateAttribute(k, in: NSRange(location: 0, length: 2), options: []) { _, _, _ in runs += 1 }
            XCTAssertTrue(runs == 1 || runs == 2, name)
        }
    }
    #endif
}
