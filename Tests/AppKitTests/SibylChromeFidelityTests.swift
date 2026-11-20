// Sibyl's main window against the Mac reference (docs/port/mac-1100x700 in Sibyl): the
// channel and toolbar symbols' artwork, the unified band of a window with a sidebar (the
// sidebar toggle over the sidebar, the title after it, grey icons), the toolbar search
// field's shape, and overlay scrollers over SwiftUI content.

import XCTest
@testable import AppKit
@testable import SwiftUI

@MainActor private func _chromeViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(_chromeViews) }

/// An image drawn into a `size`-point square at 4 pixels a point (y up, as the artwork is).
@MainActor private func _render(_ image: NSImage, points: Int = 16) -> (CGImage, Int) {
    let scale = 4, side = points * scale
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    image.draw(in: NSRect(x: 0, y: 0, width: points, height: points))
    NSGraphicsContext.restoreGraphicsState()
    return (ctx.makeImage()!, scale)
}

/// Whether there is ink within half a point of (x, y) in the artwork's 16-point box (y up).
@MainActor private func _ink(_ image: CGImage, scale: Int, _ x: CGFloat, _ y: CGFloat) -> Bool {
    let px = NSBitmapImageRep._rgbaPixels(of: image)
    let cx = Int(x * CGFloat(scale)), cy = px.height - 1 - Int(y * CGFloat(scale))
    for dy in -1...1 { for dx in -1...1 {
        let xx = cx + dx, yy = cy + dy
        guard xx >= 0, yy >= 0, xx < px.width, yy < px.height else { continue }
        if px.bytes[(yy * px.width + xx) * 4 + 3] > 60 { return true }
    } }
    return false
}

final class SibylChromeFidelityTests: XCTestCase, @unchecked Sendable {
    // MARK: Symbols

    /// `person.wave.2` (Sibyl's third channel): a bust with two sound arcs to the right of
    /// the head, each part its own stroke. Joining the arcs onto the head and shoulders
    /// (an arc appended after another shape draws a line from the current point) drew a
    /// tangled blob on Windows.
    func testPersonWaveIsABustWithTwoArcs() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            guard let image = NSImage(systemSymbolName: "person.wave.2", accessibilityDescription: nil) else { return XCTFail("no artwork") }
            let (cg, s) = _render(image)
            XCTAssertTrue(_ink(cg, scale: s, 6.7, 12.6), "the head's top")
            XCTAssertFalse(_ink(cg, scale: s, 6.7, 10.1), "the head is a ring, hollow inside")
            XCTAssertTrue(_ink(cg, scale: s, 6.5, 6.7), "the shoulders' dome")
            XCTAssertTrue(_ink(cg, scale: s, 6.5, 2), "the dome's base")
            XCTAssertTrue(_ink(cg, scale: s, 11.7, 10.1), "the inner arc, right of the head")
            XCTAssertTrue(_ink(cg, scale: s, 14.7, 10.1), "the outer arc")
            XCTAssertFalse(_ink(cg, scale: s, 10.4, 10.1), "a gap between the head and the inner arc")
            XCTAssertFalse(_ink(cg, scale: s, 13.2, 10.1), "a gap between the arcs")
            XCTAssertFalse(_ink(cg, scale: s, 13.5, 4), "nothing joins the arcs to the shoulders")
            XCTAssertFalse(_ink(cg, scale: s, 9.5, 14.3), "nothing joins the arcs over the head")
        }
    }

    /// `rectangle.expand.vertical` (the matrix's Expand All): a wide rectangle open at the
    /// middle of its top and bottom edges, an arrow leaving through each opening.
    func testRectangleExpandVerticalArrowsLeaveThroughTheEdges() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            guard let image = NSImage(systemSymbolName: "rectangle.expand.vertical", accessibilityDescription: nil) else { return XCTFail("no artwork") }
            let (cg, s) = _render(image)
            XCTAssertTrue(_ink(cg, scale: s, 3, 11.5), "the top edge's left part")
            XCTAssertTrue(_ink(cg, scale: s, 13, 4.5), "the bottom edge's right part")
            XCTAssertTrue(_ink(cg, scale: s, 1.5, 8), "the left side")
            XCTAssertFalse(_ink(cg, scale: s, 6.9, 11.5), "the top edge opens at the middle")
            XCTAssertFalse(_ink(cg, scale: s, 9.1, 4.5), "the bottom edge opens at the middle")
            XCTAssertTrue(_ink(cg, scale: s, 8, 11.5), "the up arrow's shaft crosses the top opening")
            XCTAssertTrue(_ink(cg, scale: s, 8, 14.3), "the up arrow's tip, above the rectangle")
            XCTAssertTrue(_ink(cg, scale: s, 8, 1.7), "the down arrow's tip, below the rectangle")
            XCTAssertFalse(_ink(cg, scale: s, 8, 8), "the rectangle's middle is empty")
        }
    }

    // MARK: Unified band with a sidebar

    @MainActor private final class SidebarState: ObservableObject {
        @Published var visibility: NavigationSplitViewVisibility = .all
    }

    private struct SidebarWindow: View {
        @ObservedObject var state: SidebarState
        var bound = false
        var body: some View {
            if bound {
                NavigationSplitView(columnVisibility: $state.visibility) { sidebar } detail: { detail }
            } else {
                NavigationSplitView { sidebar } detail: { detail }
            }
        }
        private var sidebar: some View {
            List { Text("Combined Log"); Text("Matrix") }
                .navigationSplitViewColumnWidth(min: 140, ideal: 250, max: 420)
        }
        private var detail: some View {
            Text("Detail")
                .navigationTitle("New Show")
                .navigationSubtitle("Stopped")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Start", systemImage: "play.fill") { }
                    }
                }
        }
    }

    @MainActor private func host<V: View>(_ view: V, width: CGFloat = 1100, height: CGFloat = 500) -> (NSWindow, NSHostingView<V>) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        let h = NSHostingView(rootView: view)
        h.frame = NSRect(x: 0, y: 0, width: width, height: height)
        h.autoresizingMask = [.width, .height]
        w.contentView = h
        w.makeKeyAndOrderFront(nil)
        (Platform.backend as! HostBackend).drain()
        return (w, h)
    }

    /// As on the Mac: the sidebar toggle over the sidebar column, then a separator on the
    /// sidebar's divider, then the title and subtitle after the sidebar.
    func testTitleFollowsTheSidebarBesideAToggle() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let (w, h) = host(SidebarWindow(state: SidebarState()))
            defer { w.close() }
            guard let tb = w.toolbar as? _SwiftUIToolbar, let band = w._toolbarView else { return XCTFail("no SwiftUI toolbar") }
            band.layoutSubtreeIfNeeded()
            let ids = tb.items.map(\.itemIdentifier)
            XCTAssertEqual(Array(ids.prefix(2)), [_SwiftUIToolbar.toggleSidebarID, _SwiftUIToolbar.sidebarSeparatorID], "the toggle and the sidebar's separator lead: \(ids)")
            guard let split = _chromeViews(h).compactMap({ $0 as? _SwiftUISplitView }).first,
                  let sidebarPane = split.arrangedSubviews.first else { return XCTFail("no split view") }
            let sidebarEdge = split.convert(NSPoint(x: sidebarPane.frame.maxX, y: 0), to: nil).x
            XCTAssertEqual(sidebarEdge, 250, accuracy: 2, "the sidebar opens at its ideal width")
            guard let title = band._titleFrame else { return XCTFail("the band shows no title") }
            XCTAssertGreaterThanOrEqual(title.minX, sidebarEdge, "the title starts after the sidebar column: \(title)")
            XCTAssertLessThan(title.minX, sidebarEdge + 24, "and right after it: \(title)")
            guard let toggle = tb.items.first(where: { $0.itemIdentifier == _SwiftUIToolbar.toggleSidebarID }),
                  let toggleFrame = band._frame(ofItem: toggle) else { return XCTFail("the toggle is not shown") }
            XCTAssertLessThan(toggleFrame.maxX, sidebarEdge, "the toggle sits over the sidebar: \(toggleFrame)")
            XCTAssertNotNil(toggle.image, "the toggle shows sidebar.leading")
        }
    }

    /// The toggle writes the split view's `columnVisibility` binding (all ↔ detail only).
    func testSidebarToggleHidesAndShowsTheSidebar() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let state = SidebarState()
            let (w, h) = host(SidebarWindow(state: state, bound: true))
            defer { w.close() }
            guard let tb = w.toolbar as? _SwiftUIToolbar, let band = w._toolbarView,
                  let toggle = tb.items.first(where: { $0.itemIdentifier == _SwiftUIToolbar.toggleSidebarID }),
                  let button = band.subviews.compactMap({ $0 as? _NSToolbarItemButton }).first(where: { $0.item === toggle })
            else { return XCTFail("no sidebar toggle") }
            @MainActor func paneCount() -> Int { _chromeViews(h).compactMap { $0 as? _SwiftUISplitView }.first?.arrangedSubviews.filter { !$0.isHidden }.count ?? 0 }
            XCTAssertEqual(paneCount(), 2)
            button.performClick(nil)
            (Platform.backend as! HostBackend).drain()
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(state.visibility, .detailOnly, "the toggle hid the sidebar")
            XCTAssertEqual(paneCount(), 1, "only the detail column is left")
            (Platform.backend as! HostBackend).drain()
            band.layoutSubtreeIfNeeded()
            XCTAssertLessThan(band._titleFrame?.minX ?? .infinity, 200, "with no sidebar the title follows the toggle: \(String(describing: band._titleFrame))")
            button.performClick(nil)
            (Platform.backend as! HostBackend).drain()
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(state.visibility, .all)
            XCTAssertEqual(paneCount(), 2, "the sidebar is back")
            (Platform.backend as! HostBackend).drain()
            band.layoutSubtreeIfNeeded()
            XCTAssertGreaterThanOrEqual(band._titleFrame?.minX ?? 0, 250, "and the title moves after it again")
        }
    }

    /// Without a `columnVisibility` binding (Sibyl's split view) the toggle collapses and
    /// restores the sidebar column itself; the sidebar comes back at its width.
    func testSidebarToggleCollapsesAnUnboundSidebar() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let (w, h) = host(SidebarWindow(state: SidebarState(), bound: false))
            defer { w.close() }
            guard let tb = w.toolbar as? _SwiftUIToolbar, let band = w._toolbarView,
                  let toggle = tb.items.first(where: { $0.itemIdentifier == _SwiftUIToolbar.toggleSidebarID }),
                  let button = band.subviews.compactMap({ $0 as? _NSToolbarItemButton }).first(where: { $0.item === toggle }),
                  let split = _chromeViews(h).compactMap({ $0 as? _SwiftUISplitView }).first
            else { return XCTFail("no sidebar toggle") }
            @MainActor func visible() -> [NSView] { split.arrangedSubviews.filter { !$0.isHidden } }
            XCTAssertEqual(visible().count, 2)
            let sidebarWidth = visible()[0].frame.width
            XCTAssertEqual(sidebarWidth, 250)
            button.performClick(nil)
            (Platform.backend as! HostBackend).drain()
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(visible().count, 1, "the sidebar is collapsed")
            XCTAssertEqual(visible()[0].frame.width, h.bounds.width, accuracy: 1, "the detail takes the width (less a divider)")
            button.performClick(nil)
            (Platform.backend as! HostBackend).drain()
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(visible().count, 2, "the sidebar is back")
            XCTAssertEqual(visible()[0].frame.width, sidebarWidth, "at its width")
        }
    }

    /// Toolbar symbols are the Mac's grey (label colour at reduced emphasis), not black.
    func testToolbarSymbolsAreGrey() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let (w, _) = host(SidebarWindow(state: SidebarState()))
            defer { w.close() }
            guard let tb = w.toolbar, let band = w._toolbarView else { return XCTFail("no toolbar") }
            band.layoutSubtreeIfNeeded()
            guard let play = tb.items.first(where: { $0.label == "Start" }), let frame = band._frame(ofItem: play),
                  let rep = band.bitmapImageRepForCachingDisplay(in: band.bounds) else { return XCTFail("no play item") }
            band.cacheDisplay(in: band.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / band.bounds.width
            var darkest: CGFloat = 1
            for y in Int(frame.minY * scale)..<Int(frame.maxY * scale) {
                for x in Int(frame.minX * scale)..<Int(frame.maxX * scale) {
                    guard let c = rep.colorAt(x: x, y: band.isFlipped ? y : rep.pixelsHigh - 1 - y)?.usingColorSpace(.sRGB) else { continue }
                    darkest = min(darkest, c.redComponent)
                }
            }
            XCTAssertGreaterThan(darkest, 0.3, "the symbol is grey, not black (darkest \(darkest))")
            XCTAssertLessThan(darkest, 0.6, "but clearly drawn (darkest \(darkest))")
        }
    }

    // MARK: Toolbar search field

    /// The Mac's toolbar search field: 325 by 28 points, a rounded rectangle (radius 6)
    /// with no fill over the band, the placeholder leading after the magnifier.
    func testToolbarSearchFieldIsTheMacRoundedRect() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Screen: View {
                @State var text = ""
                var body: some View { Text("Body").searchable(text: $text, placement: .toolbar, prompt: "Search transcript") }
            }
            let (w, _) = host(Screen())
            defer { w.close() }
            guard let band = w._toolbarView else { return XCTFail("no band") }
            band.layoutSubtreeIfNeeded()
            guard let field = _chromeViews(band).compactMap({ $0 as? NSSearchField }).first else { return XCTFail("no search field") }
            let frame = band.convert(field.bounds, from: field)
            XCTAssertEqual(frame.width, 325, accuracy: 1, "the Mac's width: \(frame)")
            XCTAssertEqual(frame.height, 28, accuracy: 1, "the Mac's height: \(frame)")
            XCTAssertFalse(field.centersPlaceholder, "the placeholder leads")
            guard let cell = field.cell as? NSSearchFieldCell else { return XCTFail("no cell") }
            XCTAssertTrue(cell._isInToolbar)
            XCTAssertFalse(cell._drawsCenteredPlaceholder)
            let text = field.convert(cell.searchTextRect(forBounds: field.bounds), to: band)
            XCTAssertEqual(text.minX - frame.minX, 29, accuracy: 3, "the text starts after the magnifier, as on the Mac: \(text) in \(frame)")

            guard let rep = band.bitmapImageRepForCachingDisplay(in: band.bounds) else { return XCTFail("no bitmap") }
            band.cacheDisplay(in: band.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / band.bounds.width
            @MainActor func px(_ x: CGFloat, _ y: CGFloat) -> NSColor {
                let row = band.isFlipped ? y : band.bounds.height - y
                return rep.colorAt(x: Int((x * scale).rounded()), y: Int((row * scale).rounded()))?.usingColorSpace(.sRGB) ?? .black
            }
            let outside = px(frame.minX - 4, frame.midY).redComponent
            XCTAssertEqual(px(frame.minX + 0.5, frame.minY + 0.5).redComponent, outside, accuracy: 0.02, "the corner is rounded off: the band shows")
            XCTAssertEqual(px(frame.maxX - 40, frame.minY + 4).redComponent, outside, accuracy: 0.02, "no fill of its own: the band shows inside")
            XCTAssertLessThan(px(frame.minX + 0.5, frame.midY).redComponent, outside - 0.02, "the outline at the left edge")
            // The placeholder's ink sits in the left part of the field, not around its centre.
            var inkXs: [CGFloat] = []
            for x in stride(from: frame.minX + 24, to: frame.maxX - 8, by: 0.5) where px(x, frame.midY).redComponent < outside - 0.15 { inkXs.append(x) }
            guard let first = inkXs.first, let last = inkXs.last else { return XCTFail("no placeholder drawn") }
            XCTAssertLessThan(first - frame.minX, 34, "the placeholder starts after the magnifier (\(first - frame.minX))")
            XCTAssertLessThan(last, frame.midX, "and ends before the middle (\(last) vs \(frame.midX))")
        }
    }

    // MARK: Overlay scrollers

    /// SwiftUI content scrolls under overlay scrollers: hidden while idle, shown while
    /// scrolling, faded out after; the content keeps the whole height.
    func testSwiftUIScrollViewUsesOverlayScrollers() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Matrix: View {
                var body: some View {
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) { ForEach(0..<6) { i in Text("Column \(i)").frame(width: 300, height: 200) } }
                    }
                }
            }
            let (w, h) = host(Matrix(), width: 600, height: 300)
            defer { w.close() }
            guard let scroll = _chromeViews(h).compactMap({ $0 as? NSScrollView }).first, let hs = scroll.horizontalScroller else { return XCTFail("no scroll view") }
            XCTAssertEqual(scroll.scrollerStyle, .overlay, "SwiftUI content takes the preferred (overlay) style")
            XCTAssertEqual(hs.scrollerStyle, .overlay)
            XCTAssertTrue(hs.isHidden, "an idle overlay scroller is hidden")
            XCTAssertEqual(scroll.contentView.frame.height, scroll.bounds.height, accuracy: 0.5, "the content keeps the whole height")

            let saved = NSScrollView._overlayHoldInterval
            NSScrollView._overlayHoldInterval = 0.05
            defer { NSScrollView._overlayHoldInterval = saved }
            scroll.contentView.scroll(to: NSPoint(x: 120, y: scroll.contentView.bounds.minY))
            scroll.reflectScrolledClipView(scroll.contentView)
            XCTAssertTrue(scroll._overlayScrollersRevealed)
            XCTAssertFalse(hs.isHidden, "scrolling shows the scroller")
            XCTAssertGreaterThan(hs.frame.width, 300)
            let deadline = Date().addingTimeInterval(2)
            while !hs.isHidden, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
            XCTAssertTrue(hs.isHidden, "the scroller fades out once scrolling stops")
            XCTAssertEqual(hs.alphaValue, 1, "and is whole again for the next scroll")

            // An app's explicit legacy style keeps the always-shown scroller beside the content.
            scroll.scrollerStyle = .legacy
            XCTAssertEqual(scroll.scrollerStyle, .legacy)
            XCTAssertFalse(hs.isHidden, "a legacy scroller is shown while needed")
            XCTAssertLessThan(scroll.contentView.frame.height, scroll.bounds.height, "and takes its room from the content")
        }
    }

    /// An AppKit scroll view outside SwiftUI keeps legacy scrollers.
    func testAppKitScrollViewStaysLegacy() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
            scroll.hasHorizontalScroller = true
            scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 100))
            XCTAssertEqual(scroll.scrollerStyle, .legacy)
            XCTAssertEqual(scroll.horizontalScroller?.isHidden, false)
        }
    }
}

/// A symbol image follows its font and `imageScale`, as SF Symbols do: a
/// ContentUnavailableView's 44 pt glyph is drawn large, not at the 16 pt artwork size.
final class SymbolFontSizeTests: XCTestCase, @unchecked Sendable {
    @MainActor private func views(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(views) }
    func testSymbolsScaleWithTheFont() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Glyphs: View {
                var body: some View {
                    HStack(alignment: .top, spacing: 20) {
                        Image(systemName: "bolt.horizontal")
                        Image(systemName: "bolt.horizontal").font(.system(size: 44))
                        Image(systemName: "bolt.horizontal").imageScale(.large)
                        Image(systemName: "bolt.horizontal").imageScale(.small)
                    }
                }
            }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let h = NSHostingView(rootView: Glyphs())
            w.contentView = h
            h.layoutSubtreeIfNeeded()
            let images = views(h).compactMap { $0 as? _SymbolImageView }.sorted { $0.frame.minX < $1.frame.minX }
            XCTAssertEqual(images.count, 4)
            guard images.count == 4 else { return }
            let base = images[0].frame.height
            XCTAssertEqual(images[1].frame.height, (base * 44 / 13).rounded(), accuracy: 1, "44 pt font: \(images[1].frame)")
            XCTAssertEqual(images[2].frame.height, (base * 1.27).rounded(), accuracy: 1, "large scale: \(images[2].frame)")
            XCTAssertEqual(images[3].frame.height, (base * 0.78).rounded(), accuracy: 1, "small scale: \(images[3].frame)")
            XCTAssertTrue(images[1].scalesUp, "the large glyph draws up to its laid-out size")
            w.close()
        }
    }
}
