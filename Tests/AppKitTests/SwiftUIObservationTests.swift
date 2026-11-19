// Observation-driven SwiftUI (ADR-0050): `@Observable` models, `@Environment(Model.self)`,
// `.environment(model)` and `@Bindable`, on the host backend.

import XCTest
import Observation
@testable import AppKit
@testable import SwiftUI

@Observable
private final class Counter {
    var count = 0
    var title = "zero"
    var nested = Nested()
}

@Observable
private final class Nested {
    var flag = false
}

private struct CounterView: View {
    @Environment(Counter.self) private var counter
    var body: some View {
        VStack {
            Text("count \(counter.count)")
            Text(counter.title)
        }
    }
}

private struct OptionalCounterView: View {
    @Environment(Counter.self) private var counter: Counter?
    var body: some View {
        Text(counter == nil ? "none" : "some")
    }
}

private struct BindableView: View {
    @Environment(Counter.self) private var counter
    var body: some View {
        @Bindable var counter = counter
        Toggle("flag", isOn: $counter.nested.flag)
    }
}

private struct StateModelView: View {
    @State private var counter = Counter()
    var body: some View {
        VStack {
            Text("state \(counter.count)")
            Button("bump") { counter.count += 1 }
        }
    }
}

@MainActor
private func host<V: View>(_ view: V) -> NSHostingView<V> {
        let h = NSHostingView(rootView: view)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        w.contentView = h
        h.layoutSubtreeIfNeeded()
        return h
}

@MainActor
private func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }
@MainActor
private func texts(_ v: NSView) -> [String] { allViews(v).compactMap { ($0 as? _TextView)?.storage.string } }
@MainActor
private func firstButton(_ v: NSView) -> NSButton? { allViews(v).compactMap { $0 as? NSButton }.first }

final class SwiftUIObservationTests: XCTestCase, @unchecked Sendable {

    func testEnvironmentObservableUpdatesTheViewsThatReadIt() {
        MainActor.assumeIsolated {
            let model = Counter()
            let h = host(CounterView().environment(model))
            XCTAssertEqual(texts(h), ["count 0", "zero"])
            model.count = 3
            model.title = "three"
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(texts(h), ["count 3", "three"])
            // Tracking is re-armed after every pass: a second change updates too.
            model.count = 4
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(texts(h), ["count 4", "three"])
        }
    }

    func testOptionalEnvironmentObservableReadsNilWhenAbsent() {
        MainActor.assumeIsolated {
            let h = host(OptionalCounterView())
            XCTAssertEqual(texts(h), ["none"])
            let h2 = host(OptionalCounterView().environment(Counter()))
            XCTAssertEqual(texts(h2), ["some"])
        }
    }

    func testBindableWritesThroughToTheModelAndNestedObjectsAreTracked() {
        MainActor.assumeIsolated {
            let model = Counter()
            let h = host(BindableView().environment(model))
            let b = try! XCTUnwrap(firstButton(h))
            XCTAssertEqual(b.state, .off)
            b.performClick(nil)
            XCTAssertTrue(model.nested.flag)
            model.nested.flag = false
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(b.state, .off)
        }
    }

    func testStateHeldObservableModelUpdatesTheView() {
        MainActor.assumeIsolated {
            let h = host(StateModelView())
            XCTAssertEqual(texts(h), ["state 0"])
            try! XCTUnwrap(firstButton(h)).performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(texts(h), ["state 1"])
        }
    }

    func testChangeFromABackgroundThreadSchedulesAMainThreadUpdate() {
        MainActor.assumeIsolated {
            let model = Counter()
            let h = host(CounterView().environment(model))
            let done = expectation(description: "mutated")
            DispatchQueue.global().async { model.count = 9; done.fulfill() }
            wait(for: [done], timeout: 2)
        }
        // The scheduled update lands on the main queue.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        MainActor.assumeIsolated {
            // A fresh pass on any hosting view attached to the same model shows the new value.
            let model = Counter()
            model.count = 9
            let h = host(CounterView().environment(model))
            XCTAssertEqual(texts(h), ["count 9", "zero"])
        }
    }
}
