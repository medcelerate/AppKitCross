// The SwiftUI members added for the third-party library compatibility example
// (docs/compatibility/swiftui-libraries.md): gradients, masks, preferences and anchors,
// 3D rotation, tasks, redaction, image and colour bridging.

import XCTest
@testable import AppKit
@testable import SwiftUI

@MainActor
private func host<V: View>(_ view: V, width: CGFloat = 200, height: CGFloat = 100) -> (NSWindow, NSHostingView<V>) {
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

/// The hosting view rendered as the window draws it; `pixel` reads RGBA at a point.
@MainActor
private func render(_ h: NSView) -> NSBitmapImageRep? {
    guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { return nil }
    h.cacheDisplay(in: h.bounds, to: rep)
    return rep
}

/// RGBA at a point (in points; the rep is at the window's backing scale).
private func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
    let scale = max(1, rep.pixelsWide / max(1, Int(rep.size.width)))
    guard let c = rep.colorAt(x: x * scale, y: y * scale) else { return (0, 0, 0, 0) }
    return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
}

final class SwiftUIEffectsTests: XCTestCase, @unchecked Sendable {
    func testLinearGradientDrawsFromStartToEnd() {
        MainActor.assumeIsolated {
            let (w, h) = host(LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing), width: 200, height: 40)
            guard let rep = render(h) else { return XCTFail("no render") }
            let left = pixel(rep, 4, 20), right = pixel(rep, 195, 20), middle = pixel(rep, 100, 20)
            XCTAssertGreaterThan(left.r, 0.8, "red at the start: \(left)")
            XCTAssertLessThan(left.b, 0.3)
            XCTAssertGreaterThan(right.b, 0.8, "blue at the end: \(right)")
            XCTAssertLessThan(right.r, 0.3)
            XCTAssertGreaterThan(middle.r, 0.3, "a blend in the middle: \(middle)")
            XCTAssertGreaterThan(middle.b, 0.3)
            w.close()
        }
    }

    func testShapeFillsWithGradient() {
        MainActor.assumeIsolated {
            let (w, h) = host(Rectangle().fill(LinearGradient(colors: [.black, .white], startPoint: .top, endPoint: .bottom)), width: 40, height: 200)
            guard let rep = render(h) else { return XCTFail("no render") }
            XCTAssertLessThan(pixel(rep, 20, 4).r, 0.2, "dark at the top")
            XCTAssertGreaterThan(pixel(rep, 20, 195).r, 0.8, "light at the bottom")
            w.close()
        }
    }

    func testMaskClipsToTheMaskViewsAlpha() {
        MainActor.assumeIsolated {
            // A red fill masked by a 50-point black square on the leading side: the trailing
            // half shows nothing.
            let view = Color.red.mask(alignment: .leading) { Color.black.frame(width: 50, height: 40) }
            let (w, h) = host(view, width: 100, height: 40)
            guard let rep = render(h) else { return XCTFail("no render") }
            let shown = pixel(rep, 20, 20), hidden = pixel(rep, 80, 20)
            XCTAssertGreaterThan(shown.r, 0.8, "inside the mask the red shows: \(shown)")
            XCTAssertGreaterThan(shown.a, 0.9)
            XCTAssertLessThan(hidden.a, 0.1, "outside the mask nothing shows: \(hidden)")
            w.close()
        }
    }

    func testGradientMaskFadesContent() {
        MainActor.assumeIsolated {
            // The shimmer idiom: content masked by a gradient from opaque to transparent.
            let view = Color.blue.mask(LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing))
            let (w, h) = host(view, width: 200, height: 40)
            guard let rep = render(h) else { return XCTFail("no render") }
            let start = pixel(rep, 5, 20), end = pixel(rep, 195, 20)
            XCTAssertGreaterThan(start.a, 0.85, "opaque at the start: \(start)")
            XCTAssertLessThan(end.a, 0.15, "transparent at the end: \(end)")
            w.close()
        }
    }

    struct HeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }

    struct SelfSizing: View {
        @State var height: CGFloat = 0
        var body: some View {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Color.red.frame(height: 30)
                    Color.blue.frame(height: 25)
                }
                .anchorPreference(key: HeightKey.self, value: .bounds) { geo[$0].size.height }
            }
            .frame(height: height)
            .onPreferenceChange(HeightKey.self) { height = $0 }
        }
    }

    func testAnchorPreferenceSizesAReaderToItsContent() {
        MainActor.assumeIsolated {
            // WrappingHStack's idiom: a GeometryReader whose height follows its content
            // through an anchor preference. Settles within the same layout pass.
            let (w, h) = host(SelfSizing(), width: 200, height: 300)
            let reader = (h.hostingRoot as? _ViewRoot)?.firstNode { $0.primitive is _GeometryReaderPrimitive }
            XCTAssertEqual(reader?.frame.height, 55, "the reader took its content's height")
            w.close()
        }
    }

    struct CountKey: PreferenceKey {
        static let defaultValue = 0
        static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
    }

    func testPreferencesReduceAcrossSiblingsAndDeliverOnce() {
        MainActor.assumeIsolated {
            var seen: [Int] = []
            let view = HStack {
                Text("a").preference(key: CountKey.self, value: 2)
                Text("b").preference(key: CountKey.self, value: 3)
                Text("c")
            }.onPreferenceChange(CountKey.self) { seen.append($0) }
            let (w, h) = host(view)
            XCTAssertEqual(seen, [5], "siblings reduce in order; delivered once")
            h.layoutSubtreeIfNeeded()
            h.setNeedsLayout(); h.layoutSubtreeIfNeeded()
            XCTAssertEqual(seen, [5], "unchanged values are not delivered again")
            w.close()
        }
    }

    func testRotation3DEffectSetsTheLayerTransform() {
        MainActor.assumeIsolated {
            let (w, h) = host(Color.red.frame(width: 40, height: 40).rotation3DEffect(.degrees(60), axis: (x: 1, y: 0, z: 0), perspective: 0))
            let container = allViews(h).compactMap { $0 as? _ContainerView }.first { $0.layer != nil && !CATransform3DIsIdentity($0.layer!.transform) }
            XCTAssertNotNil(container, "the decorated view's layer carries a 3D transform")
            if let t = container?.layer?.transform {
                XCTAssertEqual(t.m22, cos(CGFloat.pi / 3), accuracy: 0.01, "rotation about x scales y by cos")
                XCTAssertEqual(t.m34, 0, "no perspective asked for")
            }
            let (w2, h2) = host(Color.red.frame(width: 40, height: 40).rotation3DEffect(.degrees(60), axis: (x: 0, y: 1, z: 0)))
            let perspective = allViews(h2).compactMap { $0 as? _ContainerView }.first { $0.layer != nil && !CATransform3DIsIdentity($0.layer!.transform) }?.layer?.transform
            XCTAssertNotEqual(perspective?.m34 ?? 0, 0, "the default perspective sets a vanishing point")
            w.close(); w2.close()
        }
    }

    final class Flag: @unchecked Sendable { var started = 0; var cancelled = 0 }

    func testTaskStartsOnAppearAndIsCancelledOnDisappear() {
        MainActor.assumeIsolated {
            let flag = Flag()
            let started = expectation(description: "started")
            let view = Text("x").task {
                flag.started += 1
                started.fulfill()
                while !Task.isCancelled { try? await Task.sleep(nanoseconds: 1_000_000) }
                flag.cancelled += 1
            }
            let (w, h) = host(view)
            wait(for: [started], timeout: 2)
            XCTAssertEqual(flag.started, 1)
            h.removeFromSuperview()
            (h.hostingRoot as? _ViewRoot)?.detach()
            let deadline = Date().addingTimeInterval(2)
            while flag.cancelled == 0, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            XCTAssertEqual(flag.cancelled, 1, "the task saw cancellation when the view left")
            w.close()
        }
    }

    func testRedactedTextDrawsAPlaceholderBar() {
        MainActor.assumeIsolated {
            let (w, h) = host(Text("Loading content").redacted(reason: .placeholder))
            let text = allViews(h).compactMap { $0 as? _TextView }.first
            XCTAssertEqual(text?.isRedacted, true)
            // Modifiers apply outside in: the inner `unredacted` clears what the outer set.
            let (w2, h2) = host(Text("Loading content").unredacted().redacted(reason: .placeholder))
            XCTAssertEqual(allViews(h2).compactMap { $0 as? _TextView }.first?.isRedacted, false)
            w.close(); w2.close()
        }
    }

    func testImageFromCGImageAndColorBridging() {
        MainActor.assumeIsolated {
            let ns = NSImage(size: NSSize(width: 40, height: 20))
            ns.lockFocus(); NSColor.red.setFill(); NSBezierPath.fill(NSRect(x: 0, y: 0, width: 40, height: 20)); ns.unlockFocus()
            guard let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return XCTFail("no cgImage") }
            let image = Image(decorative: cg, scale: 2)
            XCTAssertEqual(image.image?.size, CGSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2), "points = pixels / scale")
            XCTAssertEqual(Image(cg, scale: 1, label: Text("Badge")).accessibilityLabel, "Badge")
            XCTAssertEqual(NSImage().size, .zero, "the empty image")

            let color = Color(red: 0.2, green: 0.4, blue: 0.6)
            guard let cgColor = color.cgColor else { return XCTFail("rgb colours bridge to CGColor") }
            let back = Color(cgColor: cgColor)
            XCTAssertEqual(back.nsColor.greenComponent, 0.4, accuracy: 0.01)
            XCTAssertNil(Color.primary.cgColor, "dynamic colours have no CGColor, as on macOS")
            let resolved = color.resolve(in: EnvironmentValues())
            XCTAssertEqual(resolved.blue, 0.6, accuracy: 0.01)
            XCTAssertEqual(Color(resolved).nsColor.redComponent, 0.2, accuracy: 0.01)
            XCTAssertEqual(Color(NSColor.red).nsColor, NSColor.red)
        }
    }

    func testPreviewProviderAndLabelTitlesCompile() {
        struct P: PreviewProvider {
            static var previews: some View { Label(Substring("Title"), systemImage: "star").previewLayout(.sizeThatFits) }
        }
        MainActor.assumeIsolated { XCTAssertNil(P.platform) }
    }
}

// MARK: Behaviour the libraries depend on

final class SwiftUILibraryIdiomTests: XCTestCase, @unchecked Sendable {
    func testTextNeverBreaksInsideAWord() {
        MainActor.assumeIsolated {
            // A stack with several spacers offers each text a small share; the text answers
            // with its word width (SwiftUI wraps between words only), so the tag is one line.
            let view = HStack(spacing: 0) {
                Text("AppKit"); Spacer(minLength: 0)
                Text("DirectComposition"); Spacer(minLength: 0)
                Text("Cairo"); Spacer(minLength: 0)
            }.frame(maxWidth: .infinity)
            let (w, h) = host(view, width: 420, height: 60)
            let texts = allViews(h).compactMap { $0 as? _TextView }
            XCTAssertEqual(texts.count, 3)
            let ideal = NSHostingView(rootView: Text("DirectComposition")).sizeThatFits(.unspecified)
            for t in texts {
                XCTAssertEqual(t.frame.height, ideal.height, accuracy: 1, "\(t.storage.string) stays on one line")
            }
            XCTAssertEqual(texts[1].frame.width, ideal.width, accuracy: 1, "and keeps its ideal width")
            // Proposed less than a word: the word width comes back, not a column of letters.
            XCTAssertEqual(texts[1].size(for: 10).width, ideal.width, accuracy: 1)
            w.close()
        }
    }

    final class Counter: ObservableObject { @Published var value = 0 }

    /// A library's property wrapper that wraps an observed object (Defaults' `@Default`).
    @MainActor @propertyWrapper
    struct Tracked: DynamicProperty {
        @ObservedObject var counter: Counter
        var wrappedValue: Int { counter.value }
    }

    struct TrackedView: View {
        @Tracked var count: Int
        var body: some View { Text("count \(count)") }
    }

    func testNestedDynamicPropertiesAreInstalled() {
        MainActor.assumeIsolated {
            let counter = Counter()
            let (w, h) = host(TrackedView(count: Tracked(counter: counter)))
            let text = allViews(h).compactMap { $0 as? _TextView }.first
            XCTAssertEqual(text?.storage.string, "count 0")
            counter.value = 3
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(text?.storage.string, "count 3", "the observed object inside the custom wrapper drives updates")
            w.close()
        }
    }
}
