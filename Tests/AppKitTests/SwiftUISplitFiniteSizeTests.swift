// Sibyl's main window (a NavigationSplitView with a sidebar List(selection:) in a
// 140...420 column, a detail ScrollView of transcript rows (a VStack: the port has no LazyVStack) and an inspector) measures only
// finite sizes: on Windows the invalidation trace printed hundreds of
// "swiftui non-finite size" lines a minute, a primitive passing an infinite proposal
// through as its size.

import XCTest
@testable import AppKit
@testable import SwiftUI

private struct SibylLikeWindow: View {
    var rows: Int
    var selection: Binding<String?>
    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section("Channels") {
                    ForEach(["One", "Two", "Three"], id: \.self) { name in
                        HStack { Label(name, systemImage: "mic"); Spacer(); Text("\(name.count)").foregroundStyle(.secondary) }.tag(name)
                    }
                }
                Section("Library") {
                    Label("Vocabulary", systemImage: "text.book.closed").tag("Vocabulary")
                    Label("Recordings", systemImage: "waveform").tag("Recordings")
                }
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 250, max: 420)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<rows, id: \.self) { i in
                        HStack {
                            Text("Speaker \(i % 3)").bold()
                            Text("Transcript line number \(i) with some words in it")
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .inspector(isPresented: .constant(true)) {
                Form { Text("Inspector") }.formStyle(.grouped).inspectorColumnWidth(min: 210, ideal: 330, max: 520)
            }
        }
    }
}

/// Whether a "swiftui non-finite size (w, h) from … proposal WxH" line has an infinite
/// dimension whose proposal was finite or unspecified (an infinite answer to an infinite
/// proposal is a flexible view's maximum, as in SwiftUI).
private func _answersInfinityToAFiniteProposal(_ line: String) -> Bool {
    guard let open = line.firstIndex(of: "("), let close = line.firstIndex(of: ")"),
          let p = line.range(of: " proposal ", options: .backwards) else { return true }
    let size = line[line.index(after: open)..<close].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    let proposal = line[p.upperBound...].split(separator: "x").map(String.init)
    guard size.count == 2, proposal.count == 2 else { return true }
    for i in 0..<2 where size[i] == "inf" || size[i] == "-inf" || size[i] == "nan" {
        if proposal[i] != "inf" { return true }
    }
    return false
}

final class SwiftUISplitFiniteSizeTests: XCTestCase, @unchecked Sendable {
    func testSibylWindowMeasuresOnlyFiniteSizes() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            var lines: [String] = []
            NSView._traceInvalidation = true
            NSView._traceSink = { line in if line.hasPrefix("swiftui non-finite size") { lines.append(line) } }
            defer { NSView._traceInvalidation = false; NSView._traceSink = nil }

            var selected: String? = "One"
            let binding = Binding<String?>(get: { selected }, set: { selected = $0 })
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            let h = NSHostingView(rootView: SibylLikeWindow(rows: 20, selection: binding))
            h.frame = NSRect(x: 0, y: 0, width: 1100, height: 700)
            h.autoresizingMask = [.width, .height]
            w.contentView!.addSubview(h)
            w.makeKeyAndOrderFront(nil)
            h.layoutSubtreeIfNeeded()
            let initial = lines.count

            w.setContentSize(NSSize(width: 900, height: 600))
            h.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
            h.layoutSubtreeIfNeeded()
            let resized = lines.count

            selected = "Recordings"
            h.rootView = SibylLikeWindow(rows: 40, selection: binding)
            h.layoutSubtreeIfNeeded()

            for l in Set(lines).sorted() { print("[finite-size] \(l)") }
            let bad = lines.map(_answersInfinityToAFiniteProposal)
            XCTAssertEqual(bad[..<initial].filter { $0 }.count, 0, "initial layout")
            XCTAssertEqual(bad[initial..<resized].filter { $0 }.count, 0, "window resize")
            XCTAssertEqual(bad[resized...].filter { $0 }.count, 0, "state change")
            // The trace itself now skips infinity answered to an infinite proposal (a
            // Spacer, a flexible frame), so a Sibyl-like window traces nothing at all.
            XCTAssertTrue(lines.isEmpty, "no non-finite trace lines for a Sibyl-like window: \(Set(lines).sorted())")
            // The split view no longer probes its flexible detail column at infinity (that
            // measured the whole detail tree a third time per pass); what remains is a
            // stack's flexibility probe, where a Spacer offered infinity answers infinity
            // as in SwiftUI.
            XCTAssertFalse(lines.contains { $0.contains("_SplitPrimitive") || $0.contains("_ScrollPrimitive") || $0.contains("_SplitPanePrimitive") }, "detail column probed at infinity")
            XCTAssertFalse(lines.contains { $0.contains("from _List") }, "the sidebar list answered infinity")
            w.close()
        }
    }

    /// A List offered an infinite width (a stack's flexibility probe) takes its rows' ideal
    /// width, as SwiftUI's does, rather than passing infinity to a row with a Spacer.
    func testListUnderAnInfiniteWidthAnswersAFiniteWidth() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            var lines: [String] = []
            NSView._traceInvalidation = true
            NSView._traceSink = { line in if line.hasPrefix("swiftui non-finite size") { lines.append(line) } }
            defer { NSView._traceInvalidation = false; NSView._traceSink = nil }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
            let h = NSHostingView(rootView: HStack {
                List {
                    ForEach(["One", "Two"], id: \.self) { name in HStack { Label(name, systemImage: "mic"); Spacer(); Text("3") } }
                }
                Text("Detail")
            })
            h.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
            w.contentView!.addSubview(h)
            w.makeKeyAndOrderFront(nil)
            h.layoutSubtreeIfNeeded()
            for l in Set(lines).sorted() { print("[finite-size] \(l)") }
            XCTAssertFalse(lines.contains { $0.contains("from _List") }, "the list answered infinity")
            XCTAssertEqual(lines.filter(_answersInfinityToAFiniteProposal).count, 0)
            w.close()
        }
    }
}
