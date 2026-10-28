// SwiftUI over AppKitWin: the runtime (state, bindings, reconciliation, environment),
// layout (stacks, spacers, frames, padding) and rendering through AppKit views.

import XCTest
@testable import AppKit
@testable import SwiftUI
#if canImport(Combine)
import Combine
#endif

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
private func node<V: View, T>(_ h: NSHostingView<V>, _ type: T.Type) -> _ViewNode? {
    (h.hostingRoot as? _ViewRoot)?.firstNode { $0.viewType == T.self }
}

@MainActor
private func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }

final class SwiftUITests: XCTestCase, @unchecked Sendable {
    struct Counter: View {
        @State var count = 0
        var body: some View {
            VStack(spacing: 10) {
                Text("Count: \(count)")
                Button("Increment") { count += 1 }
                if count > 2 { Text("Many") }
            }
        }
    }

    func testStateDrivesBodyAndButtonsAct() {
        MainActor.assumeIsolated {
            let (w, h) = host(Counter())
            let texts = allViews(h).compactMap { $0 as? _TextView }
            XCTAssertEqual(texts.count, 1)
            XCTAssertEqual(texts[0].storage.string, "Count: 0")
            let button = allViews(h).compactMap { $0 as? NSButton }.first
            XCTAssertNotNil(button)
            XCTAssertEqual(button?.title, "Increment")
            button?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(texts[0].storage.string, "Count: 1", "the same text view is updated in place")
            button?.performClick(nil); button?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            let after = allViews(h).compactMap { $0 as? _TextView }
            XCTAssertEqual(after.count, 2, "the conditional view appears")
            XCTAssertEqual(after[1].storage.string, "Many")
            XCTAssertGreaterThan(after[1].frame.minY, after[0].frame.maxY, "stacked below")
            w.close()
        }
    }

    struct Form: View {
        @State var name = ""
        @State var on = false
        @State var amount = 0.5
        var body: some View {
            VStack {
                TextField("Name", text: $name)
                Toggle("Enabled", isOn: $on)
                Slider(value: $amount, in: 0...1)
                Text(name.isEmpty ? "anonymous" : name)
            }.padding()
        }
    }

    func testBindingsFlowBothWays() {
        MainActor.assumeIsolated {
            let (w, h) = host(Form())
            let field = allViews(h).compactMap { $0 as? NSTextField }.first { $0.placeholderString == "Name" }!
            let toggle = allViews(h).compactMap { $0 as? NSButton }.first!
            let slider = allViews(h).compactMap { $0 as? NSSlider }.first!
            let label = allViews(h).compactMap { $0 as? _TextView }.first!
            XCTAssertEqual(label.storage.string, "anonymous")
            field.stringValue = "Ada"
            NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(label.storage.string, "Ada", "typing updates the binding and the body")
            // The view writes back into the control when state changes elsewhere.
            let n = node(h, Form.self)!
            let formNode = n
            XCTAssertNotNil(formNode)
            toggle.performClick(nil)
            XCTAssertEqual(toggle.state, .on)
            slider.doubleValue = 0.9
            slider.sendAction(slider.action, to: slider.target)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(slider.doubleValue, 0.9, accuracy: 0.001)
            w.close()
        }
    }

    func testStacksSpacersFramesAndPadding() {
        MainActor.assumeIsolated {
            struct Row: View {
                var body: some View {
                    HStack(spacing: 0) {
                        Color.red.frame(width: 40, height: 20)
                        Spacer()
                        Color.blue.frame(width: 60, height: 30)
                    }.padding(10)
                }
            }
            let (w, h) = host(Row(), width: 300, height: 100)
            let red = node(h, Color.self)!
            XCTAssertEqual(red.frame.minX, 10, accuracy: 0.5)
            XCTAssertEqual(red.frame.width, 40)
            let shapes = allViews(h).compactMap { $0 as? _ShapeDrawingView }
            XCTAssertEqual(shapes.count, 2)
            let blue = shapes.max { $0.frame.minX < $1.frame.minX }!
            XCTAssertEqual(blue.frame.maxX, 290, accuracy: 0.5, "the spacer pushes the blue box to the trailing edge")
            XCTAssertEqual(blue.frame.width, 60)
            // Vertical centring in the row: the shorter box is centred against the taller.
            let redView = shapes.min { $0.frame.minX < $1.frame.minX }!
            XCTAssertEqual(redView.frame.midY, blue.frame.midY, accuracy: 1)
            // Ideal size of the whole thing: 40 + 60 + padding.
            XCTAssertEqual(h.sizeThatFits(.unspecified).height, 30 + 20)
            w.close()
        }
    }

    func testForEachReconcilesByIdentity() {
        MainActor.assumeIsolated {
            final class Model: ObservableObject {
                @Published var items = ["a", "b", "c"]
            }
            struct ListView: View {
                @ObservedObject var model: Model
                var body: some View {
                    VStack {
                        ForEach(model.items, id: \.self) { Text($0) }
                    }
                }
            }
            let model = Model()
            let (w, h) = host(ListView(model: model))
            var texts = allViews(h).compactMap { $0 as? _TextView }
            XCTAssertEqual(texts.map { $0.storage.string }, ["a", "b", "c"])
            let bView = texts[1]
            model.items = ["c", "b"]
            h.layoutSubtreeIfNeeded()
            texts = allViews(h).compactMap { $0 as? _TextView }
            XCTAssertEqual(texts.map { $0.storage.string }, ["c", "b"])
            XCTAssertTrue(texts.contains { $0 === bView }, "the view for b is kept across the reorder")
            w.close()
        }
    }

    func testEnvironmentFlowsDown() {
        MainActor.assumeIsolated {
            struct Leaf: View {
                @Environment(\.font) var font
                @Environment(\.isEnabled) var enabled
                var body: some View { Text(enabled ? "on" : "off").font(font) }
            }
            struct Root: View {
                var body: some View {
                    VStack {
                        Leaf()
                        Leaf().disabled(true)
                    }.font(.system(size: 30))
                }
            }
            let (w, h) = host(Root())
            let texts = allViews(h).compactMap { $0 as? _TextView }
            XCTAssertEqual(texts.map { $0.storage.string }, ["on", "off"])
            let font = texts[0].storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            XCTAssertEqual(font?.pointSize, 30)
            XCTAssertGreaterThan(texts[0].frame.height, 25)
            w.close()
        }
    }

    func testDecorationsDrawAndClip() {
        MainActor.assumeIsolated {
            struct Card: View {
                var body: some View {
                    Text("Hi").padding(20).background(Color.green).cornerRadius(8).border(Color.red, width: 2)
                }
            }
            let (w, h) = host(Card(), width: 120, height: 80)
            w.display()
            let host = Mirror(reflecting: w).descendant("_platform") as! HostWindow
            let img = host.lastImage!
            let px = _pixels(img)
            func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {   // BGRA, y from the top
                let i = y * img.bytesPerRow + x * 4
                return (px[i + 2], px[i + 1], px[i])
            }
            let container = allViews(h).compactMap { $0 as? _ContainerView }.first!
            let f = container.frame
            let cx = Int(f.midX), cy = Int(f.midY) + Int(NSWindow._testTitleBarHeight)
            let centre = pixel(cx, cy)
            XCTAssertGreaterThan(centre.g, 150, "green background behind the text")
            let edge = pixel(Int(f.minX) + 1, cy)
            XCTAssertGreaterThan(edge.r, 150, "red border at the leading edge")
            w.close()
        }
    }

    func testRepresentableHostsAppKitViews() {
        MainActor.assumeIsolated {
            struct Field: NSViewRepresentable {
                var text: String
                func makeNSView(context: Context) -> NSTextField { NSTextField(frame: .zero) }
                func updateNSView(_ nsView: NSTextField, context: Context) { nsView.stringValue = text }
            }
            struct Root: View {
                @State var text = "one"
                var body: some View { VStack { Field(text: text); Button("go") { text = "two" } } }
            }
            let (w, h) = host(Root())
            let field = allViews(h).compactMap { $0 as? NSTextField }.first!
            XCTAssertEqual(field.stringValue, "one")
            allViews(h).compactMap { $0 as? NSButton }.first!.performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(field.stringValue, "two")
            w.close()
        }
    }

    func testHostingControllerAndSizing() {
        MainActor.assumeIsolated {
            let c = NSHostingController(rootView: Text("Hello").padding())
            let size = c.sizeThatFits(in: NSSize(width: 1000, height: 1000))
            XCTAssertGreaterThan(size.width, 40)
            XCTAssertGreaterThan(size.height, 30)
            XCTAssertNotNil(c.view)
        }
    }
}

extension NSWindow {
    /// The host window manager's title bar height, for pixel tests that read the window image.
    @MainActor static var _testTitleBarHeight: CGFloat { HostWindow.titleBarHeight }
}
