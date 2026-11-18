// The SwiftUI and AppKit names the AGENTS.md validation (PR 88) had to shim: SecureField and
// a masking NSSecureTextField, onReceive, ForEach.onDelete with the offset helpers, #Preview,
// ranged lineLimit, TextField(axis:), header-only Section, and NSPasteboard's discardable
// results (ADR-0049).

import XCTest
@testable import AppKit
@testable import SwiftUI

// `#Preview` compiles (the port's plugin expands it into a function that is never called).
#Preview {
    Text("A preview")
}

#Preview("Named", traits: .sizeThatFitsLayout) {
    Text("Two views")
    Text("in one preview")
}

#Preview("Previewable") {
    @Previewable @State var on = false
    Toggle("Switch", isOn: $on)
}

#Preview("AppKit") {
    NSTextField(labelWithString: "An AppKit preview")
}

@MainActor
private func host<V: View>(_ view: V, width: CGFloat = 320, height: CGFloat = 260) -> (NSWindow, NSHostingView<V>) {
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
    let h = NSHostingView(rootView: view)
    h.frame = NSRect(x: 0, y: 0, width: width, height: height)
    w.contentView!.addSubview(h)
    w.makeKeyAndOrderFront(nil)
    h.layoutSubtreeIfNeeded()
    return (w, h)
}

@MainActor
private func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }
@MainActor
private func texts(_ v: NSView) -> [String] { allViews(v).compactMap { ($0 as? _TextView)?.storage.string } }

@MainActor
private func click(_ list: _ListView, row: Int, flags: NSEvent.ModifierFlags = [], in w: NSWindow) {
    let f = list.rowFrames[row]
    let p = list.convert(NSPoint(x: f.midX, y: f.midY), to: nil)
    for (type, n) in [(NSEvent.EventType.leftMouseDown, 1), (.leftMouseUp, 2)] {
        let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: n, clickCount: 1, pressure: 1)!
        NSApplication.shared.sendEvent(e)
    }
}

@MainActor
private func key(_ code: UInt16, _ chars: String = "", flags: NSEvent.ModifierFlags = [], in w: NSWindow) {
    let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil,
                             characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    NSApplication.shared.sendEvent(e)
}

final class SwiftUIPortGapsTests: XCTestCase, @unchecked Sendable {

    // MARK: NSSecureTextField

    func testSecureTextFieldMasksItsTextAndEditor() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
            let field = NSSecureTextField(frame: NSRect(x: 10, y: 20, width: 200, height: 24))
            let plain = NSTextField(frame: NSRect(x: 10, y: 50, width: 200, height: 24))
            w.contentView!.addSubview(field); w.contentView!.addSubview(plain)
            w.makeKeyAndOrderFront(nil)
            let cell = field.cell as? NSSecureTextFieldCell
            XCTAssertNotNil(cell, "an NSSecureTextField makes an NSSecureTextFieldCell")
            XCTAssertEqual(cell?.echosBullets, true)
            field.stringValue = "hunter2"
            XCTAssertEqual(cell?._displayedString, String(repeating: "\u{2022}", count: 7), "the cell draws bullets")
            XCTAssertEqual(field.stringValue, "hunter2", "the value is the real text")
            XCTAssertEqual(field.accessibilityValue() as String?, String(repeating: "\u{2022}", count: 7))
            cell?.echosBullets = false
            XCTAssertEqual(cell?._displayedString, "", "no echo draws nothing")
            cell?.echosBullets = true

            // Editing: the secure field editor lays out bullets for the real text.
            XCTAssertTrue(w.makeFirstResponder(field))
            guard let editor = field.currentEditor as? NSTextView else { return XCTFail("no field editor") }
            XCTAssertNotNil(editor._layoutManager._secureEcho)
            editor.insertText("é🙂x")
            XCTAssertEqual(field.stringValue, "é🙂x")
            let shown = editor._layoutManager._coreTextString().string
            XCTAssertEqual((shown as NSString).length, ("é🙂x" as NSString).length, "offsets stay one to one")
            XCTAssertEqual(shown.filter { $0 == "\u{2022}" }.count, 3, "one bullet per character")
            XCTAssertFalse(shown.contains("x"))
            XCTAssertEqual(editor.accessibilityValue() as String?, String(repeating: "\u{2022}", count: 3))

            // Nothing leaves a secure field through the pasteboard.
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString("before", forType: .string)
            editor.selectAll(nil)
            editor.copy(nil)
            editor.cut(nil)
            XCTAssertEqual(pb.string(forType: .string), "before")
            XCTAssertEqual(field.stringValue, "é🙂x", "cut does not remove the text either")

            // A plain field next to it edits in the ordinary, unmasked editor.
            XCTAssertTrue(w.makeFirstResponder(plain))
            guard let plainEditor = plain.currentEditor as? NSTextView else { return XCTFail("no plain editor") }
            XCTAssertFalse(plainEditor === editor)
            XCTAssertNil(plainEditor._layoutManager._secureEcho)
            w.close()
        }
    }

    /// The rendered field shows no glyph of the text: a secure field and an empty one
    /// differ only where the bullets are, and a plain field with the same text differs more.
    func testSecureTextFieldRendersBullets() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            @MainActor func render(_ field: NSTextField) -> Data {
                let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 220, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)
                field.frame = NSRect(x: 10, y: 8, width: 200, height: 24)
                w.contentView!.addSubview(field)
                w.makeKeyAndOrderFront(nil)
                w.display()
                let data = _pixels((w._platformWindow as! HostWindow).lastImage!)
                w.close()
                return data
            }
            let secure = NSSecureTextField(); secure.stringValue = "WWWWWW"
            let secureAgain = NSSecureTextField(); secureAgain.stringValue = "iiiiii"
            let plain = NSTextField(); plain.stringValue = "WWWWWW"
            let a = render(secure), b = render(secureAgain), c = render(plain)
            XCTAssertEqual(a, b, "six bullets look the same whatever the six characters are")
            XCTAssertNotEqual(a, c, "a plain field draws the characters")
        }
    }

    // MARK: SecureField

    func testSecureFieldHostsASecureTextFieldBoundToItsText() {
        MainActor.assumeIsolated {
            struct Login: View {
                @State var password = "seed"
                var body: some View {
                    VStack {
                        SecureField("Password", text: $password)
                        SecureField(text: $password, prompt: Text("Prompt")) { Text("Label") }
                        Text("pw \(password)")
                    }
                }
            }
            let (w, h) = host(Login())
            let fields = allViews(h).compactMap { $0 as? NSSecureTextField }
            XCTAssertEqual(fields.count, 2)
            XCTAssertEqual(fields.first?.placeholderString, "Password")
            XCTAssertEqual(fields.last?.placeholderString, "Prompt")
            XCTAssertEqual(fields.first?.stringValue, "seed")
            XCTAssertTrue(w.makeFirstResponder(fields[0]))
            (fields[0].currentEditor as? NSTextView)?.selectAll(nil)
            (fields[0].currentEditor as? NSTextView)?.insertText("s3cret")
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("pw s3cret"), texts(h).joined(separator: "|"))
            XCTAssertEqual(fields[1].stringValue, "s3cret", "the binding reaches the other field")
            XCTAssertFalse(texts(h).contains { $0.contains("s3cret") && $0 != "pw s3cret" })
            w.close()
        }
    }

    // MARK: onReceive

    func testOnReceiveSubscribesWhileInTheHierarchy() {
        MainActor.assumeIsolated {
            let subject = PassthroughSubject<Int, Never>()
            final class Log { var values: [Int] = [] }
            let log = Log()
            struct Probe: View {
                let subject: PassthroughSubject<Int, Never>
                let log: Log
                @State var shown = true
                @State var last = 0
                var body: some View {
                    VStack {
                        if shown {
                            Text("last \(last)").onReceive(subject) { v in last = v; log.values.append(v) }
                        }
                        Button("Hide") { shown = false }
                    }
                }
            }
            let (w, h) = host(Probe(subject: subject, log: log))
            subject.send(1)
            subject.send(2)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(log.values, [1, 2])
            XCTAssertTrue(texts(h).contains("last 2"), texts(h).joined(separator: "|"))
            // Updates keep one subscription (no duplicate deliveries).
            subject.send(3)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(log.values, [1, 2, 3])
            allViews(h).compactMap { $0 as? NSButton }.first { $0.title == "Hide" }?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            subject.send(4)
            XCTAssertEqual(log.values, [1, 2, 3], "removing the view cancels the subscription")
            w.close()
        }
    }

    // MARK: onDelete and offsets

    func testRemoveAndMoveOffsetsMatchSwiftUI() {
        var a = ["a", "b", "c", "d", "e"]
        a.remove(atOffsets: [1, 3])
        XCTAssertEqual(a, ["a", "c", "e"])
        a.remove(atOffsets: [])
        XCTAssertEqual(a, ["a", "c", "e"])
        a.remove(atOffsets: [0, 1, 2])
        XCTAssertEqual(a, [])

        func moved(_ source: IndexSet, _ destination: Int) -> [String] {
            var m = ["a", "b", "c", "d", "e"]
            m.move(fromOffsets: source, toOffset: destination)
            return m
        }
        XCTAssertEqual(moved([1, 3], 0), ["b", "d", "a", "c", "e"])
        XCTAssertEqual(moved([1, 3], 2), ["a", "b", "d", "c", "e"])
        XCTAssertEqual(moved([1, 3], 5), ["a", "c", "e", "b", "d"])
        XCTAssertEqual(moved([0], 2), ["b", "a", "c", "d", "e"])
        XCTAssertEqual(moved([4], 0), ["e", "a", "b", "c", "d"])
        XCTAssertEqual(moved([2], 2), ["a", "b", "c", "d", "e"])
        XCTAssertEqual(moved([2], 3), ["a", "b", "c", "d", "e"])
    }

    func testOnDeleteDeletesTheSelectedRowsWithTheDeleteKey() {
        MainActor.assumeIsolated {
            final class Log { var deleted: [IndexSet] = [] }
            let log = Log()
            struct Probe: View {
                let log: Log
                @State var fruit = ["Apple", "Banana", "Cherry"]
                @State var veg = ["Leek", "Onion"]
                @State var selection: Set<String> = []
                var body: some View {
                    VStack {
                        List(selection: $selection) {
                            Section {
                                ForEach(fruit, id: \.self) { Text($0) }
                                    .onDelete { log.deleted.append($0); fruit.remove(atOffsets: $0) }
                            } header: {
                                Text("Fruit")
                            }
                            Section("Vegetables") {
                                ForEach(veg, id: \.self) { Text($0) }
                                    .onDelete { log.deleted.append($0); veg.remove(atOffsets: $0) }
                            }
                        }
                        .frame(height: 360)     // all seven rows visible with any platform's font
                        Text("left \(fruit.joined(separator: ",")) / \(veg.joined(separator: ","))")
                    }
                }
            }
            let (w, h) = host(Probe(log: log), height: 480)
            guard let list = allViews(h).compactMap({ $0 as? _ListView }).first else { return XCTFail("no list") }
            XCTAssertLessThanOrEqual(list.rowFrames.last?.maxY ?? .infinity, list.visibleRect.maxY + 1, "every row is on screen")
            // Rows: Fruit header, 3 fruit, Vegetables header, 2 vegetables.
            XCTAssertEqual(list.rowFrames.count, 7)
            XCTAssertEqual(list.supplementaryRows, [0, 4])
            // A header cannot be selected.
            click(list, row: 0, in: w)
            XCTAssertTrue(list.selectedRows.isEmpty)
            // Banana, then Onion with Command: one delete per ForEach with its own offsets.
            click(list, row: 2, in: w); h.layoutSubtreeIfNeeded()
            click(list, row: 6, flags: [.command], in: w)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(list.selectedRows, [2, 6])
            key(51, "\u{7F}", in: w)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(log.deleted, [IndexSet(integer: 1), IndexSet(integer: 1)])
            XCTAssertTrue(texts(h).contains("left Apple,Cherry / Leek"), texts(h).joined(separator: "|"))
            // Arrow keys step over the Vegetables header.
            click(list, row: 2, in: w)          // Cherry
            key(125, in: w)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(list.selectedRows, [4], "Leek, past the header at 3")
            w.close()
        }
    }

    // MARK: Section

    func testHeaderOnlySectionUnderListAndForm() {
        MainActor.assumeIsolated {
            struct Probe: View {
                var body: some View {
                    HStack {
                        List {
                            Section { Text("Row A"); Text("Row B") } header: { Text("List Header") }
                            Section(header: Text("Old Header")) { Text("Row C") }
                        }
                        Form {
                            Section { Text("Field") } header: { Text("Form Header") }
                            Section { Text("Other") } footer: { Text("Form Footer") }
                        }
                    }
                }
            }
            let (w, h) = host(Probe(), width: 600, height: 300)
            let shown = texts(h)
            for s in ["List Header", "Row A", "Row B", "Old Header", "Row C", "Form Header", "Field", "Other", "Form Footer"] {
                XCTAssertTrue(shown.contains(s), "\(s) missing from \(shown)")
            }
            let list = allViews(h).compactMap { $0 as? _ListView }.first
            XCTAssertEqual(list?.rowFrames.count, 5, "two headers and three rows")
            XCTAssertEqual(list?.supplementaryRows, [0, 3])
            // The header sits above its rows.
            @MainActor func y(_ s: String) -> CGFloat { allViews(h).compactMap { $0 as? _TextView }.first { $0.storage.string == s }.map { $0.convert($0.bounds, to: h).minY } ?? -1 }
            XCTAssertLessThan(y("Form Header"), y("Field"))
            XCTAssertLessThan(y("Other"), y("Form Footer"))
            w.close()
        }
    }

    // MARK: lineLimit and TextField(axis:)

    func testVerticalTextFieldGrowsWithinItsLineLimitRange() {
        MainActor.assumeIsolated {
            struct Probe: View {
                @Binding var text: String
                var body: some View {
                    VStack(alignment: .leading) {
                        TextField("Notes", text: $text, axis: .vertical).lineLimit(2...4).frame(width: 200)
                        TextField("Single", text: $text).frame(width: 200)
                        Spacer()
                    }
                }
            }
            final class Box { var text = "" }
            let box = Box()
            let binding = Binding(get: { box.text }, set: { box.text = $0 })
            let (w, h) = host(Probe(text: binding), width: 300, height: 400)
            let fields = allViews(h).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
            guard fields.count == 2 else { return XCTFail("fields: \(fields.count)") }
            let vertical = fields.first { $0.placeholderString == "Notes" }!
            let single = fields.first { $0.placeholderString == "Single" }!
            XCTAssertFalse(vertical.usesSingleLineMode)
            XCTAssertTrue(single.usesSingleLineMode)
            #if os(macOS)
            XCTAssertEqual(single.frame.height, 21, accuracy: 1, "macOS's bezeled field height")   // other platforms' fonts differ
            #endif
            let lineHeight = single.frame.height - 5
            XCTAssertEqual(vertical.frame.height, 2 * lineHeight + 5, accuracy: 1, "empty: the range's two lines")
            box.text = "one\ntwo\nthree"
            h.rootView = Probe(text: binding)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(vertical.frame.height, 3 * lineHeight + 5, accuracy: 1, "grows to its three lines")
            box.text = (1...9).map { "line \($0)" }.joined(separator: "\n")
            h.rootView = Probe(text: binding)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(vertical.frame.height, 4 * lineHeight + 5, accuracy: 1, "no taller than the upper bound")
            XCTAssertEqual(single.frame.height, lineHeight + 5, accuracy: 1, "a horizontal field stays one line")
            // The field editor wraps for a vertical field and Option-Return types a newline.
            XCTAssertTrue(w.makeFirstResponder(vertical))
            let editor = vertical.currentEditor as? NSTextView
            XCTAssertEqual(editor?._fieldEditorWraps, true)
            editor?.moveToEndOfDocument(nil)
            editor?.insertNewlineIgnoringFieldEditor(nil)
            XCTAssertTrue(vertical.stringValue.hasSuffix("line 9\n"))
            XCTAssertTrue(w.makeFirstResponder(single))
            XCTAssertEqual((single.currentEditor as? NSTextView)?._fieldEditorWraps, false)
            w.close()
        }
    }

    func testLineLimitOverloads() {
        MainActor.assumeIsolated {
            let long = String(repeating: "word ", count: 80)
            struct Probe: View {
                let long: String
                var body: some View {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("short").lineLimit(3, reservesSpace: true).frame(width: 200).background(Color.red).id("reserved")
                        Text("short").lineLimit(3).frame(width: 200).id("plain")
                        Text(long).lineLimit(...2).frame(width: 200).id("through")
                        Text(long).lineLimit(1...).frame(width: 200).id("from")
                        Spacer()
                    }
                }
            }
            let (w, h) = host(Probe(long: long), width: 300, height: 900)
            let views = allViews(h).compactMap { $0 as? _TextView }
            let shortViews = views.filter { $0.storage.string == "short" }
            let longViews = views.filter { $0.storage.string == long }
            XCTAssertEqual(shortViews.count, 2)
            XCTAssertEqual(longViews.count, 2)
            let one = shortViews[1].frame.height
            XCTAssertEqual(shortViews[0].frame.height, 3 * one, accuracy: 3, "reservesSpace keeps three lines")
            XCTAssertEqual(longViews[0].frame.height, 2 * one, accuracy: 3, "...2 caps at two lines")
            XCTAssertGreaterThan(longViews[1].frame.height, 4 * one, "1... has no upper bound")
            w.close()
        }
    }

    // MARK: Preview and NSPasteboard

    func testPreviewValuesAndDiscardablePasteboardResults() {
        MainActor.assumeIsolated {
            let p = Preview("Built") { Text("x") }
            XCTAssertEqual(p._name, "Built")
            _ = PreviewTrait<Preview.ViewTraits>(.sizeThatFitsLayout, .fixedLayout(width: 10, height: 10))
            // AppKit's Bool/Int results are discardable, as for every Objective-C method.
            let pb = NSPasteboard.withUniqueName()
            pb.clearContents()
            pb.setString("value", forType: .string)
            let item = NSPasteboardItem()
            item.setString("object", forType: .init("test.object"))
            pb.writeObjects([item])
            pb.setData(Data([1]), forType: .init("test.data"))
            XCTAssertEqual(pb.string(forType: .string), "value")
            pb.releaseGlobally()
        }
    }
}
