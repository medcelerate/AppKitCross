// Right-to-left layout: the application's direction comes from the environment, the
// defaults or the locale; views inherit it; leading and trailing swap sides in Auto
// Layout, stack views, cell text and SwiftUI's stacks, alignments, padding and text.

import XCTest
@testable import AppKit
@testable import SwiftUI

final class RightToLeftTests: XCTestCase, @unchecked Sendable {
    override func tearDown() { NSApplication._layoutDirectionOverride = nil }

    func testApplicationDirectionAndInheritance() {
        MainActor.assumeIsolated {
            XCTAssertTrue(NSApplication._isRightToLeftLanguage("ar_EG"))
            XCTAssertTrue(NSApplication._isRightToLeftLanguage("he-IL"))
            XCTAssertFalse(NSApplication._isRightToLeftLanguage("en_US"))
            NSApplication._layoutDirectionOverride = .rightToLeft
            XCTAssertEqual(NSApplication.shared.userInterfaceLayoutDirection, .rightToLeft)
            let parent = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
            let child = NSView(frame: .zero)
            parent.addSubview(child)
            XCTAssertEqual(child.userInterfaceLayoutDirection, .rightToLeft, "inherited from the application")
            parent.userInterfaceLayoutDirection = .leftToRight
            XCTAssertEqual(child.userInterfaceLayoutDirection, .leftToRight, "inherited from the superview")
            child.userInterfaceLayoutDirection = .rightToLeft
            XCTAssertEqual(child.userInterfaceLayoutDirection, .rightToLeft, "its own setting wins")
            NSApplication._layoutDirectionOverride = nil
        }
    }

    func testLeadingAndTrailingConstraintsMirror() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let container = w.contentView!
            let box = NSView(frame: .zero)
            box.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(box)
            NSLayoutConstraint.activate([
                box.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
                box.widthAnchor.constraint(equalToConstant: 50),
                box.topAnchor.constraint(equalTo: container.topAnchor), box.heightAnchor.constraint(equalToConstant: 30),
            ])
            container.layoutSubtreeIfNeeded()
            XCTAssertEqual(box.frame.minX, 20)
            container.userInterfaceLayoutDirection = .rightToLeft
            container.layoutSubtreeIfNeeded()
            XCTAssertEqual(box.frame.maxX, 280, "leading is the right edge, 20 points in from it")
            // A stack view's items run from the right, in order.
            let stack = NSStackView(views: [NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 20)), NSView(frame: NSRect(x: 0, y: 0, width: 60, height: 20))])
            stack.orientation = .horizontal
            stack.spacing = 10
            stack.translatesAutoresizingMaskIntoConstraints = false
            for v in stack.arrangedSubviews {
                v.widthAnchor.constraint(equalToConstant: v.frame.width).isActive = true
                v.heightAnchor.constraint(equalToConstant: 20).isActive = true
            }
            container.addSubview(stack)
            NSLayoutConstraint.activate([stack.leftAnchor.constraint(equalTo: container.leftAnchor), stack.rightAnchor.constraint(equalTo: container.rightAnchor), stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)])
            container.layoutSubtreeIfNeeded()
            let first = stack.arrangedSubviews[0].frame, second = stack.arrangedSubviews[1].frame
            XCTAssertEqual(first.maxX, 300, "the first item is at the right edge")
            XCTAssertEqual(second.maxX, 300 - 40 - 10, "the second follows to its left")
            w.close()
        }
    }

    func testNaturalTextAlignmentFollowsTheDirection() {
        MainActor.assumeIsolated {
            NSApplication._layoutDirectionOverride = .rightToLeft
            let field = NSTextField(labelWithString: "Hi")
            field.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
            field.alignment = .natural
            let image = NSImage(size: field.frame.size)
            image.lockFocus()
            field.draw(field.bounds)
            image.unlockFocus()
            let rep = image.representations.compactMap { $0 as? NSBitmapImageRep }.first ?? NSBitmapImageRep(data: image.tiffRepresentation!)!
            func ink(_ x0: Int, _ x1: Int) -> Int {
                var n = 0
                for x in x0..<x1 { for y in 0..<Int(rep.pixelsHigh) { if let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.3 { n += 1 } } }
                return n
            }
            let w = Int(rep.pixelsWide)   // lockFocus renders at 2x: scan the outer quarters in pixels
            XCTAssertGreaterThan(ink(w * 3 / 4, w), ink(0, w / 4), "natural alignment draws at the right in a right-to-left app")
            XCTAssertGreaterThan(ink(w * 3 / 4, w), 0)
            NSApplication._layoutDirectionOverride = nil
        }
    }

    func testSwiftUIStacksAlignmentPaddingAndTextMirror() {
        MainActor.assumeIsolated {
            struct Content: View {
                var body: some View {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 10) {
                            Color.red.frame(width: 40, height: 20)
                            Color.green.frame(width: 60, height: 20)
                        }
                        Color.blue.frame(width: 30, height: 20).padding(.leading, 25)
                        ZStack(alignment: .topTrailing) { Color.gray.frame(width: 100, height: 40); Color.yellow.frame(width: 10, height: 10) }
                        Text("Hello").frame(width: 100, alignment: .leading)
                    }
                    .frame(width: 300, height: 200, alignment: .topLeading)
                    .environment(\.layoutDirection, .rightToLeft)
                }
            }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let h = NSHostingView(rootView: Content())
            h.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
            w.contentView!.addSubview(h)
            w.makeKeyAndOrderFront(nil)
            h.layoutSubtreeIfNeeded()
            let root = (h.hostingRoot as? _ViewRoot)!
            @MainActor func frame<V: View>(_ type: V.Type, _ n: Int = 0) -> CGRect {
                var found: [_ViewNode] = []
                @MainActor func visit(_ node: _ViewNode) {
                    if node.viewType == V.self { found.append(node) }
                    for c in node.children { visit(c) }
                    for x in node.primitive?.extraNodes ?? [] { visit(x) }
                }
                if let r = root.rootNode { visit(r) }
                return found[n].frame ?? .zero
            }
            // The HStack's first item is at the right of the 110-wide row, which sits at the leading (right) edge.
            let colors = (0..<4).map { frame(Color.self, $0) }
            let red = colors[0], green = colors[1]
            XCTAssertEqual(red.maxX, 300, accuracy: 0.5, "HStack: first item at the right edge")
            XCTAssertEqual(green.maxX, 300 - 40 - 10, accuracy: 0.5)
            // VStack leading alignment puts the padded row at the right; the leading pad is on the right.
            let blue = colors[2]
            XCTAssertEqual(blue.maxX, 300 - 25, accuracy: 0.5, "leading padding is on the right")
            // ZStack topTrailing: the yellow square at the gray box's left edge.
            let gray = frame(Color.self, 3), yellow = frame(Color.self, 4)
            XCTAssertEqual(yellow.minX, gray.minX, accuracy: 0.5, "trailing is the left edge")
            // Text with leading alignment lands at the right of its 100-point frame.
            let textView = h.subviews.flatMap { all($0) }.compactMap { $0 as? _TextView }.first!
            let textFrame = frame(Text.self)
            XCTAssertEqual(textFrame.maxX, 300, accuracy: 0.5)
            let line = textView.layoutManager.lineFragmentUsedRect(forGlyphAt: 0, effectiveRange: nil)
            XCTAssertGreaterThan(line.minX, 20, "natural text is flush right in the text view")
            w.close()
        }
    }
    @MainActor private func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
}

final class RightToLeftSizingTests: XCTestCase, @unchecked Sendable {
    /// The HelloWindow SwiftUI demo crashed on Windows under RTL with a NaN window size:
    /// every layout construct it uses must size finitely in a right-to-left environment.
    func testDemoLikeContentSizesFinitelyRightToLeft() {
        MainActor.assumeIsolated {
            struct Row: Identifiable { let id: Int; let name: String; let moons: Int }
            struct Demo: View {
                let rows = [Row(id: 1, name: "Mercury", moons: 0), Row(id: 2, name: "Earth", moons: 1)]
                @State private var selected: Set<Int> = []
                @State private var name = ""
                @State private var on = true
                @State private var amount = 0.4
                @State private var tab = "a"
                @State private var pick = 1
                var body: some View {
                    TabView(selection: $tab) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SwiftUI on AppKitWin").font(.title).bold()
                            TextField("Name", text: $name)
                            Toggle("Enabled", isOn: $on)
                            Slider(value: $amount)
                            Color.blue.frame(width: 240 * CGFloat(amount) + 20, height: 20)
                            Picker("Pick", selection: $pick) { Text("One").tag(1); Text("Two").tag(2) }.pickerStyle(.segmented)
                            HStack { Button("Add") {}; Spacer(); Text("count 0") }
                            List(["a", "b"], id: \.self) { item in HStack { Circle().fill(Color.green).frame(width: 10, height: 10); Text(item); Spacer() } }.frame(height: 120)
                            GeometryReader { g in Text("\(Int(g.size.width))") }.frame(height: 20)
                            ScrollView { VStack { Text("row 0").frame(maxWidth: .infinity, alignment: .leading); Text("row 1") } }.frame(height: 60)
                        }
                        .padding(4)
                        .tabItem { Text("Controls") }.tag("a")
                        NavigationStack {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Pick:").foregroundColor(.secondary)
                                NavigationLink("Detail", destination: Text("Pushed").padding())
                                Spacer()
                                Text("depth").font(.caption)
                            }.padding(12)
                        }.tabItem { Text("Navigation") }.tag("b")
                        VStack(alignment: .leading, spacing: 8) {
                            Table(rows, selection: $selected) {
                                TableColumn("Name") { Text($0.name) }
                                TableColumn("Moons") { Text("\($0.moons)") }.width(60)
                            }.frame(minHeight: 180)
                            Text("Files").frame(maxWidth: .infinity, minHeight: 40).background(RoundedRectangle(cornerRadius: 6).fill(Color.gray))
                        }.padding(12).tabItem { Text("Data") }.tag("c")
                        VStack(alignment: .leading, spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.15))
                                RoundedRectangle(cornerRadius: 10).fill(Color.blue).frame(width: 120, height: 80)
                                    .overlay(Text("1.00x").foregroundColor(.white)).scaleEffect(1).rotationEffect(.zero).offset(.zero)
                            }.frame(minHeight: 220)
                            HStack { Text("Taps: 0").padding(8).background(Color.gray.opacity(0.2)); Spacer(); Button("Reset") {} }
                        }.tabItem { Text("Gestures") }.tag("d")
                    }
                    .padding(12)
                    .frame(minWidth: 420, minHeight: 360)
                }
            }
            NSApplication._layoutDirectionOverride = .rightToLeft      // the whole app, as APPKITWIN_LAYOUT_DIRECTION=rtl does
            defer { NSApplication._layoutDirectionOverride = nil }
            let h = NSHostingView(rootView: Demo())
            let unspecified = h.sizeThatFits(.unspecified)
            XCTAssertTrue(unspecified.width.isFinite && unspecified.height.isFinite, "sizeThatFits(.unspecified) \(unspecified)")
            XCTAssertLessThan(unspecified.width, 2000, "flush-right text must measure its own width, not the unbounded container's")
            let ideal = h.intrinsicContentSize
            XCTAssertTrue(ideal.width.isFinite && ideal.height.isFinite, "ideal size \(ideal)")
            let fit = h.fittingSize
            XCTAssertTrue(fit.width.isFinite && fit.height.isFinite, "fitting size \(fit)")
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            h.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
            w.contentView!.addSubview(h)
            w.makeKeyAndOrderFront(nil)
            h.layoutSubtreeIfNeeded()
            @MainActor func check(_ v: NSView) { let f = v.frame; XCTAssertTrue(f.origin.x.isFinite && f.width.isFinite, "\(type(of: v)) frame \(f)"); for s in v.subviews { check(s) } }
            check(h)
            w.close()
        }
    }
}
