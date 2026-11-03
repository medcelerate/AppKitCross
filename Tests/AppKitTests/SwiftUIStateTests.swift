// GeometryReader, AppStorage and FocusState.

import XCTest
@testable import AppKit
@testable import SwiftUI

@MainActor
private func host<V: View>(_ view: V, width: CGFloat = 300, height: CGFloat = 200) -> (NSWindow, NSHostingView<V>) {
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
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

final class SwiftUIStateTests: XCTestCase, @unchecked Sendable {
    func testGeometryReaderReportsItsSize() {
        MainActor.assumeIsolated {
            struct Probe: View {
                var body: some View {
                    VStack(spacing: 0) {
                        Text("header")
                        GeometryReader { proxy in
                            Text("\(Int(proxy.size.width))x\(Int(proxy.size.height)) at \(Int(proxy.frame(in: .global).minY))")
                        }
                    }.padding(10)
                }
            }
            let (w, h) = host(Probe(), width: 300, height: 200)
            let line = texts(h).first { $0.contains("x") }
            XCTAssertNotNil(line)
            XCTAssertTrue(line!.hasPrefix("280x"), "the reader fills the width inside the padding: \(line!)")
            XCTAssertTrue(line!.hasSuffix("at \(10 + 16)") || line!.hasSuffix("at 26") || line!.hasSuffix("at 27"), "below the header: \(line!)")
            h.setFrameSize(NSSize(width: 200, height: 200))
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains { $0.hasPrefix("180x") }, "resizing rebuilds the content")
            w.close()
        }
    }

    func testAppStoragePersistsThroughUserDefaults() {
        MainActor.assumeIsolated {
            let suite = "AppKitWinSwiftUIStateTests"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            enum Theme: String { case light, dark }
            struct Settings: View {
                let store: UserDefaults
                @AppStorage("count") var count = 3
                @AppStorage("name") var name = "guest"
                @AppStorage("theme") var theme = Theme.light
                init(store: UserDefaults) {
                    self.store = store
                    _count = AppStorage(wrappedValue: 3, "count", store: store)
                    _name = AppStorage(wrappedValue: "guest", "name", store: store)
                    _theme = AppStorage(wrappedValue: .light, "theme", store: store)
                }
                var body: some View {
                    VStack {
                        Text("\(name) \(count) \(theme.rawValue)")
                        Button("Bump") { count += 1; name = "ada"; theme = .dark }
                    }
                }
            }
            let (w, h) = host(Settings(store: defaults))
            XCTAssertTrue(texts(h).contains("guest 3 light"), "defaults apply when nothing is stored")
            allViews(h).compactMap { $0 as? NSButton }.first?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("ada 4 dark"))
            XCTAssertEqual(defaults.integer(forKey: "count"), 4)
            XCTAssertEqual(defaults.string(forKey: "theme"), "dark")
            // A second view over the same store sees the persisted values.
            let (w2, h2) = host(Settings(store: defaults))
            XCTAssertTrue(texts(h2).contains("ada 4 dark"))
            w.close(); w2.close()
            defaults.removePersistentDomain(forName: suite)
        }
    }

    func testFocusStateMovesFocusAndFollowsEditing() {
        MainActor.assumeIsolated {
            enum Field: Hashable { case name, email }
            struct Form: View {
                @State var name = ""
                @State var email = ""
                @State var submitted = 0
                @FocusState var focus: Field?
                var body: some View {
                    VStack {
                        TextField("Name", text: $name).focused($focus, equals: .name)
                        TextField("Email", text: $email).focused($focus, equals: .email)
                            .onSubmit { submitted += 1 }
                        Button("Focus email") { focus = .email }
                        Text("focus: \(focus.map { "\($0)" } ?? "none") submitted: \(submitted)")
                    }
                }
            }
            let (w, h) = host(Form())
            let fields = allViews(h).compactMap { $0 as? NSTextField }
            let name = fields.first { $0.placeholderString == "Name" }!
            let email = fields.first { $0.placeholderString == "Email" }!
            XCTAssertTrue(texts(h).contains("focus: none submitted: 0"))
            allViews(h).compactMap { $0 as? NSButton }.first { $0.title == "Focus email" }?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertNotNil(email.currentEditor, "setting the focus state focuses the field")
            XCTAssertTrue(texts(h).contains("focus: email submitted: 0"))
            // Clicking into the other field moves the state along.
            _ = w.makeFirstResponder(name)
            h.layoutSubtreeIfNeeded()
            XCTAssertNotNil(name.currentEditor)
            XCTAssertTrue(texts(h).contains("focus: name submitted: 0"), texts(h).joined(separator: "|"))
            // Return in the email field submits.
            _ = w.makeFirstResponder(email)
            h.layoutSubtreeIfNeeded()
            let ret = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
            w.sendEvent(ret)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains { $0.hasSuffix("submitted: 1") }, texts(h).joined(separator: "|"))
            w.close()
        }
    }
}
