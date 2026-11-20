// The opt-in macOS control look (ADR-0051, `APPKITWIN_MAC_CONTROLS=1`) and the
// unconditional fixes that came with it, checked in pixels on the host backend: each
// control is rendered under both looks, light and dark, and (where the look changes
// with it) in a key and a non-key window.

import XCTest
@testable import AppKit
@testable import SwiftUI

@MainActor private func _macViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(_macViews) }

final class MacControlsPixelTests: XCTestCase, @unchecked Sendable {
    private typealias RGB = (r: CGFloat, g: CGFloat, b: CGFloat)

    override func tearDown() { _NSControlStyle._override = nil; super.tearDown() }

    /// Runs `body` with the control look forced on or off.
    @MainActor private func withLook(mac: Bool, _ body: () -> Void) {
        _NSControlStyle._override = mac
        defer { _NSControlStyle._override = nil }
        body()
    }

    @MainActor private func render(_ view: NSView) -> (rep: NSBitmapImageRep, scale: CGFloat)? {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return (rep, CGFloat(rep.pixelsWide) / view.bounds.width)
    }

    /// The pixel composited over white (transparent corners read as white).
    @MainActor private func pixel(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat, scale: CGFloat) -> RGB {
        let c = rep.colorAt(x: Int((x * scale).rounded()), y: Int((y * scale).rounded())) ?? .clear
        let rgb = c.usingColorSpace(.deviceRGB) ?? c
        let a = rgb.alphaComponent
        return (rgb.redComponent * a + (1 - a), rgb.greenComponent * a + (1 - a), rgb.blueComponent * a + (1 - a))
    }
    /// The pixel's alpha (the bitmap is transparent outside a bezel).
    @MainActor private func alpha(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat, scale: CGFloat) -> CGFloat {
        let c = rep.colorAt(x: Int((x * scale).rounded()), y: Int((y * scale).rounded())) ?? .clear
        return (c.usingColorSpace(.deviceRGB) ?? c).alphaComponent
    }
    private func lum(_ c: RGB) -> CGFloat { (c.r + c.g + c.b) / 3 }
    private func isGrey(_ c: RGB) -> Bool { abs(c.r - c.g) < 0.06 && abs(c.g - c.b) < 0.06 }
    private func isAccent(_ c: RGB) -> Bool { c.b > c.r + 0.2 }
    private func close(_ a: RGB, _ b: RGB, _ t: CGFloat = 0.03) -> Bool { abs(a.r - b.r) <= t && abs(a.g - b.g) <= t && abs(a.b - b.b) <= t }
    private func fmt(_ c: RGB) -> String { String(format: "(%.2f %.2f %.2f)", c.r, c.g, c.b) }

    @MainActor private func makeWindow(_ size: NSSize, dark: Bool) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        if dark { w.appearance = NSAppearance(named: .darkAqua) }
        return w
    }

    // MARK: Push buttons

    func testPushButtonIsShadedOnlyUnderTheMacLook() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            for dark in [false, true] {
                for mac in [false, true] {
                    withLook(mac: mac) {
                        let window = makeWindow(NSSize(width: 160, height: 60), dark: dark)
                        defer { window.close() }
                        let button = NSButton(title: "Install", target: nil, action: nil)
                        button.frame = NSRect(x: 20, y: 16, width: 120, height: 28)
                        window.contentView?.addSubview(button)
                        window.makeKeyAndOrderFront(nil)
                        guard let (rep, scale) = render(button) else { return XCTFail("no bitmap") }
                        // Inside the bezel, clear of the title: 8 points in from the left.
                        let top = pixel(rep, 8, 3, scale: scale), bottom = pixel(rep, 8, 23, scale: scale)
                        let what = "\(mac ? "mac" : "default") \(dark ? "dark" : "light")"
                        if mac {
                            XCTAssertGreaterThan(lum(top) - lum(bottom), 0.02, "\(what): the bezel shades from light at the top \(fmt(top)) to darker at the bottom \(fmt(bottom))")
                        } else {
                            XCTAssertTrue(close(top, bottom), "\(what): the flat bezel is one colour: \(fmt(top)) vs \(fmt(bottom))")
                        }
                        // The hairline at the left edge's midpoint differs from the fill beside it.
                        let edge = pixel(rep, 0.5, 14, scale: scale), fill = pixel(rep, 4, 14, scale: scale)
                        XCTAssertFalse(close(edge, fill, 0.02), "\(what): the bezel has a hairline: edge \(fmt(edge)) fill \(fmt(fill))")
                    }
                }
            }
        }
    }

    func testDefaultButtonGreysInAnInactiveWindowOnlyUnderTheMacLook() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            for mac in [false, true] {
                withLook(mac: mac) {
                    let window = makeWindow(NSSize(width: 160, height: 60), dark: false)
                    defer { window.close() }
                    let button = NSButton(title: "OK", target: nil, action: nil)
                    button.keyEquivalent = "\r"
                    button.frame = NSRect(x: 20, y: 16, width: 120, height: 28)
                    window.contentView?.addSubview(button)
                    window.makeKeyAndOrderFront(nil)
                    guard let (rep, scale) = render(button) else { return XCTFail("no bitmap") }
                    XCTAssertTrue(isAccent(pixel(rep, 8, 14, scale: scale)), "\(mac ? "mac" : "default"): the default button is the accent in a key window: \(fmt(pixel(rep, 8, 14, scale: scale)))")
                    window.resignKey()
                    guard let (rep2, _) = render(button) else { return XCTFail("no bitmap") }
                    let p = pixel(rep2, 8, 14, scale: scale)
                    if mac { XCTAssertTrue(isGrey(p), "mac: the default button greys with its window: \(fmt(p))") }
                    else { XCTAssertTrue(isAccent(p), "default: the accent stays in an inactive window: \(fmt(p))") }
                }
            }
        }
    }

    func testDestructiveButtonHasARedTitleAndNoAccentBezel() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            for mac in [false, true] {
                withLook(mac: mac) {
                    let window = makeWindow(NSSize(width: 200, height: 60), dark: false)
                    defer { window.close() }
                    let button = NSButton(title: "Delete Channel", target: nil, action: nil)
                    button.keyEquivalent = "\r"
                    button.hasDestructiveAction = true
                    button.frame = NSRect(x: 20, y: 16, width: 160, height: 28)
                    window.contentView?.addSubview(button)
                    window.makeKeyAndOrderFront(nil)
                    guard let (rep, scale) = render(button) else { return XCTFail("no bitmap") }
                    XCTAssertFalse(isAccent(pixel(rep, 8, 14, scale: scale)), "\(mac ? "mac" : "default"): a destructive default button keeps a plain bezel")
                    var red = false
                    for x in stride(from: CGFloat(30), to: 130, by: 1) { for y in stride(from: CGFloat(8), to: 20, by: 1) {
                        let p = pixel(rep, x, y, scale: scale)
                        if p.r > 0.75 && p.g < 0.5 && p.b < 0.5 { red = true }
                    } }
                    XCTAssertTrue(red, "\(mac ? "mac" : "default"): the destructive title is red")
                }
            }
        }
    }

    // MARK: Text fields

    func testTextFieldShowsAFocusRingWhileEditing() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            for dark in [false, true] {
                for mac in [false, true] {
                    withLook(mac: mac) {
                        let window = makeWindow(NSSize(width: 200, height: 60), dark: dark)
                        defer { window.close() }
                        let field = NSTextField(frame: NSRect(x: 20, y: 18, width: 160, height: 22))
                        field.stringValue = "New Show"
                        window.contentView?.addSubview(field)
                        window.makeKeyAndOrderFront(nil)
                        let what = "\(mac ? "mac" : "default") \(dark ? "dark" : "light")"
                        guard let (rep, scale) = render(field) else { return XCTFail("no bitmap") }
                        let edge = pixel(rep, 0.5, 11, scale: scale)
                        XCTAssertFalse(isAccent(edge), "\(what): no focus ring at rest: \(fmt(edge))")
                        XCTAssertTrue(window.makeFirstResponder(field))
                        XCTAssertNotNil(field.currentEditor(), "editing in the field editor")
                        guard let (rep2, _) = render(field) else { return XCTFail("no bitmap") }
                        // The ring: the accent at the edge (default) or just inside it (mac, 3 points wide).
                        let ring = mac ? pixel(rep2, 2, 11, scale: scale) : pixel(rep2, 0.5, 11, scale: scale)
                        XCTAssertTrue(isAccent(ring), "\(what): the focus ring shows while the field editor is up: \(fmt(ring))")
                    }
                }
            }
        }
    }

    func testGroupedFormTextFieldIsPlainTrailingTextUntilEdited() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Panel: View {
                @State var name = "New Show"
                var body: some View {
                    Form { Section("Show") { TextField("Name", text: $name) } }.formStyle(.grouped)
                }
            }
            for mac in [false, true] {
                withLook(mac: mac) {
                    let window = makeWindow(NSSize(width: 420, height: 200), dark: false)
                    defer { window.close() }
                    let hosting = NSHostingView(rootView: Panel())
                    hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 200)
                    window.contentView = hosting
                    window.makeKeyAndOrderFront(nil)
                    (Platform.backend as! HostBackend).drain()
                    guard let field = _macViews(hosting).compactMap({ $0 as? NSTextField }).first(where: { $0.isEditable }) else { return XCTFail("no editable field") }
                    XCTAssertEqual(field.alignment, .right, "the value is trailing-aligned")
                    XCTAssertFalse(field.isBezeled, "plain at rest")
                    let frame = hosting.convert(field.bounds, from: field)
                    guard let (rep, scale) = render(hosting) else { return XCTFail("no bitmap") }
                    let top = hosting.isFlipped ? frame.minY : hosting.bounds.height - frame.maxY
                    let edge = pixel(rep, frame.minX + 0.5, top + frame.height / 2, scale: scale)
                    let card = pixel(rep, frame.minX - 4, top + frame.height / 2, scale: scale)
                    XCTAssertTrue(close(edge, card, 0.02), "\(mac ? "mac" : "default"): no bezel at rest: edge \(fmt(edge)) card \(fmt(card))")
                    XCTAssertTrue(window.makeFirstResponder(field))
                    (Platform.backend as! HostBackend).drain()
                    guard let (rep2, _) = render(hosting) else { return XCTFail("no bitmap") }
                    let editing = pixel(rep2, frame.minX + (mac ? 2 : 0.5), top + frame.height / 2, scale: scale)
                    XCTAssertFalse(close(editing, card, 0.02), "\(mac ? "mac" : "default"): the bezel and ring show while editing: \(fmt(editing)) vs card \(fmt(card))")
                }
            }
        }
    }

    // MARK: Toggles and pickers in a grouped form

    func testGroupedFormToggleIsASwitchAndPickerIsBorderless() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Panel: View {
                var body: some View {
                    Form {
                        Section("Trigger") {
                            Toggle("Enabled", isOn: .constant(true))
                            Picker("Match", selection: .constant(0)) { Text("Contains any of").tag(0); Text("Contains all of").tag(1) }
                        }
                    }
                    .formStyle(.grouped)
                }
            }
            for mac in [false, true] {
                withLook(mac: mac) {
                    let window = makeWindow(NSSize(width: 420, height: 220), dark: false)
                    defer { window.close() }
                    let hosting = NSHostingView(rootView: Panel())
                    hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 220)
                    window.contentView = hosting
                    window.makeKeyAndOrderFront(nil)
                    (Platform.backend as! HostBackend).drain()
                    let views = _macViews(hosting)
                    XCTAssertNotNil(views.first { $0 is NSSwitch }, "the automatic toggle style is a switch in a grouped form")
                    XCTAssertNil(views.first { ($0 as? NSButton)?.cell is NSButtonCell && ($0 as? NSButton)?.title == "Enabled" }, "no checkbox")
                    guard let popUp = views.compactMap({ $0 as? NSPopUpButton }).first else { return XCTFail("no pop-up") }
                    XCTAssertFalse(popUp.isBordered, "the grouped row's pop-up is borderless")
                    let frame = hosting.convert(popUp.bounds, from: popUp)
                    guard let (rep, scale) = render(hosting) else { return XCTFail("no bitmap") }
                    let top = hosting.isFlipped ? frame.minY : hosting.bounds.height - frame.maxY
                    let edge = pixel(rep, frame.minX + 0.5, top + frame.height / 2, scale: scale)
                    let card = pixel(rep, frame.minX - 4, top + frame.height / 2, scale: scale)
                    XCTAssertTrue(close(edge, card, 0.02), "\(mac ? "mac" : "default"): no bezel around the title: \(fmt(edge)) vs \(fmt(card))")
                    // The chevron box at the trailing end is not the accent cap.
                    let cap = pixel(rep, frame.maxX - 12, top + frame.height / 2 - 6, scale: scale)
                    XCTAssertFalse(isAccent(cap), "\(mac ? "mac" : "default"): the chevrons sit in a plain bezel, not a blue cap: \(fmt(cap))")
                }
            }
        }
    }

    // MARK: Sliders

    func testSteppedSliderShowsATickPerStep() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Panel: View {
                var body: some View {
                    VStack {
                        Slider(value: .constant(15), in: 11...32, step: 1)
                        Slider(value: .constant(2), in: 0...30, step: 0.5)
                        Slider(value: .constant(0.5))
                    }.padding()
                }
            }
            for dark in [false, true] {
                for mac in [false, true] {
                    withLook(mac: mac) {
                        let window = makeWindow(NSSize(width: 300, height: 120), dark: dark)
                        defer { window.close() }
                        let hosting = NSHostingView(rootView: Panel())
                        hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 120)
                        window.contentView = hosting
                        window.makeKeyAndOrderFront(nil)
                        (Platform.backend as! HostBackend).drain()
                        let sliders = _macViews(hosting).compactMap { $0 as? NSSlider }
                        XCTAssertEqual(sliders.map(\.numberOfTickMarks), [22, 61, 0])
                        XCTAssertEqual(sliders.map(\.allowsTickMarkValuesOnly), [true, true, false])
                        guard let first = sliders.first, let (rep, scale) = render(first) else { return XCTFail("no bitmap") }
                        // A tick well away from the knob (the last one) differs from the background.
                        guard let cell = first.cell as? NSSliderCell else { return XCTFail("no cell") }
                        let tick = cell.rectOfTickMark(at: 21)
                        // The tick's end nearest minY (clear of the bar under the mac comb), as a bitmap row.
                        let y = first.isFlipped ? tick.minY + 1 : first.bounds.height - (tick.minY + 1)
                        // Compared by coverage: a dark tick is white on a transparent bitmap.
                        let at = alpha(rep, tick.midX, y, scale: scale)
                        let beside = alpha(rep, tick.midX - 2.5, y, scale: scale)
                        XCTAssertGreaterThan(at, beside + 0.2, "\(mac ? "mac" : "default") \(dark ? "dark" : "light"): the tick is drawn: \(at) vs \(beside)")
                    }
                }
            }
        }
    }

    // MARK: Search field

    func testSearchFieldIsARoundedRectWithALeadingPlaceholder() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            for mac in [false, true] {
                withLook(mac: mac) {
                    let window = makeWindow(NSSize(width: 260, height: 60), dark: false)
                    defer { window.close() }
                    let band = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 60))
                    window.contentView = band
                    let field = NSSearchField(frame: NSRect(x: 20, y: 16, width: 220, height: 28))
                    field.placeholderString = "Search transcript"
                    // Leading, as in a toolbar (outside one the port keeps the centred
                    // placeholder of `centersPlaceholder`, PR 92).
                    field.centersPlaceholder = false
                    band.addSubview(field)
                    window.makeKeyAndOrderFront(nil)
                    guard let (rep, scale) = render(field) else { return XCTFail("no bitmap") }
                    // Two points in from a corner is inside a 6-point corner (a capsule's
                    // 14-point corner would leave it outside, showing what is behind).
                    XCTAssertLessThan(alpha(rep, 0.5, 0.5, scale: scale), 0.3, "\(mac ? "mac" : "default"): the corner itself is outside the bezel")
                    XCTAssertGreaterThan(alpha(rep, 2.5, 2.5, scale: scale), 0.7, "\(mac ? "mac" : "default"): (2.5, 2.5) is inside a 6-point corner (a capsule leaves it outside)")
                    // The placeholder's ink is in the leading third of the text area, none in the trailing third.
                    @MainActor func darkest(_ xs: StrideThrough<CGFloat>) -> CGFloat {
                        var m: CGFloat = 1
                        for x in xs { for y in stride(from: CGFloat(8), through: 20, by: 1) { m = min(m, lum(pixel(rep, x, y, scale: scale))) } }
                        return m
                    }
                    // The placeholder colour is a light grey (about 0.75); the fill is white.
                    XCTAssertLessThan(darkest(stride(from: 26, through: 80, by: 1)), 0.85, "\(mac ? "mac" : "default"): the placeholder starts at the leading edge")
                    XCTAssertGreaterThan(darkest(stride(from: 150, through: 190, by: 1)), 0.95, "\(mac ? "mac" : "default"): nothing in the trailing third")
                }
            }
        }
    }

    // MARK: Alerts

    /// macOS's compact alert is the port's only alert (PR 92): the look does not change it.
    /// Checked under both looks: narrow, a destructive first button stacks above Cancel and
    /// never takes Return, the sheet is centred in the parent, which dims.
    func testAlertIsCompactStackedAndCentredUnderBothLooks() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            for mac in [false, true] {
                withLook(mac: mac) {
                    let parent = makeWindow(NSSize(width: 600, height: 400), dark: false)
                    defer { parent.close() }
                    parent.makeKeyAndOrderFront(nil)
                    let alert = NSAlert()
                    alert.messageText = "Delete “Production”?"
                    alert.informativeText = "The channel and its on-screen transcript are removed."
                    alert.icon = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
                    alert.addButton(withTitle: "Delete Channel").hasDestructiveAction = true
                    _ = alert.addButton(withTitle: "Cancel")
                    let panel = alert.window
                    let buttons = alert.buttons
                    let what = mac ? "mac" : "default"
                    XCTAssertEqual(panel.frame.width, NSAlert._width, "\(what): the compact alert")
                    XCTAssertGreaterThan(buttons[0].frame.minY, buttons[1].frame.minY, "\(what): a destructive button stacks on top")
                    XCTAssertEqual(buttons[0].frame.width, buttons[1].frame.width)
                    XCTAssertNotNil(_macViews(panel.contentView!).first { $0 is NSImageView }, "\(what): the icon")
                    // AppKit's NSAlert: the first button answers Return even when destructive
                    // (SwiftUI's alert, which has roles, gives a destructive button no Return).
                    XCTAssertEqual(buttons[0].keyEquivalent, "\r", "\(what): the first button is the default")
                    XCTAssertEqual(buttons[1].keyEquivalent, "\u{1B}", "\(what): Cancel answers Escape")
                    var response: NSApplication.ModalResponse? = nil
                    alert.beginSheetModal(for: parent) { response = $0 }
                    (Platform.backend as! HostBackend).drain()
                    XCTAssertTrue(parent.attachedSheet === panel)
                    XCTAssertTrue(parent._dimsForSheet, "\(what): the parent dims behind the sheet")
                    XCTAssertEqual(panel.frame.midX, parent.frame.midX, accuracy: 2, "\(what): centred in the parent")
                    XCTAssertLessThan(panel.frame.maxY, parent.frame.maxY, "\(what): below the title bar")
                    XCTAssertGreaterThan(panel.frame.minY, parent.frame.minY, "\(what): inside the parent")
                    buttons[1].performClick(nil)
                    (Platform.backend as! HostBackend).drain()
                    XCTAssertEqual(response, .alertSecondButtonReturn)
                    XCTAssertFalse(parent._dimsForSheet, "\(what): the dimming goes with the sheet")
                }
            }
        }
    }

    // MARK: Scrollers

    /// An AppKit scroll view (TextEdit's document) keeps legacy scrollers by default and
    /// takes overlay ones under the mac look; SwiftUI-hosted content is overlay either way
    /// (PR 92). An app's explicit `scrollerStyle` wins under both.
    func testAppKitScrollViewOverlaysItsScrollersOnlyUnderTheMacLook() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            for mac in [false, true] {
                withLook(mac: mac) {
                    let window = makeWindow(NSSize(width: 200, height: 100), dark: false)
                    defer { window.close() }
                    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
                    scroll.hasVerticalScroller = true
                    let doc = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 1000))
                    scroll.documentView = doc
                    window.contentView?.addSubview(scroll)
                    window.makeKeyAndOrderFront(nil)
                    scroll.tile()
                    guard let scroller = scroll.verticalScroller else { return XCTFail("no scroller") }
                    let what = mac ? "mac" : "default"
                    if mac {
                        XCTAssertEqual(scroll.scrollerStyle, .overlay, what)
                        XCTAssertEqual(scroll.contentView.frame.width, 200, "\(what): the content keeps the full width")
                        XCTAssertTrue(scroller.isHidden, "\(what): hidden at rest")
                    } else {
                        XCTAssertEqual(scroll.scrollerStyle, .legacy, what)
                        XCTAssertEqual(scroll.contentView.frame.width, 185, "\(what): the legacy bar takes 15 points")
                        XCTAssertFalse(scroller.isHidden, "\(what): always shown")
                    }
                    scroll.scrollerStyle = .legacy
                    XCTAssertEqual(scroll.contentView.frame.width, 185, "\(what): an explicit legacy style wins")
                }
            }
        }
    }

    /// Under the mac look an AppKit scroll view's overlay pill shows on the first wheel
    /// notch of a fresh window, paints above the content, holds, fades (its alpha sampled
    /// in the scroll view's composite as the run loop turns) and hides, whole again.
    func testOverlayScrollerShowsOnTheFirstScrollThenFadesAndHides() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            withLook(mac: true) {
                let saved = NSScrollView._overlayHoldInterval
                NSScrollView._overlayHoldInterval = 0.1
                defer { NSScrollView._overlayHoldInterval = saved }
                let window = makeWindow(NSSize(width: 200, height: 100), dark: false)
                defer { window.close() }
                let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
                scroll.hasVerticalScroller = true
                scroll.drawsBackground = true
                scroll.backgroundColor = .white
                let doc = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 1000))
                scroll.documentView = doc
                window.contentView?.addSubview(scroll)
                window.makeKeyAndOrderFront(nil)
                scroll.tile()
                guard let scroller = scroll.verticalScroller else { return XCTFail("no scroller") }
                XCTAssertTrue(scroller.isHidden, "hidden at rest")
                // One wheel notch on the fresh window.
                let wheel = NSEvent._scrollEvent(location: NSPoint(x: 100, y: 50), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, deltaX: 0, deltaY: 3, precise: false)
                scroll.scrollWheel(with: wheel)
                XCTAssertTrue(scroll._overlayScrollersRevealed, "the first scroll shows the overlay scrollers")
                XCTAssertFalse(scroller.isHidden)
                XCTAssertEqual(scroller.alphaValue, 1)
                // The pill, in the scroll view's composite: the darkest pixel down the knob's
                // centre column (the knob sits wherever the scroll put it).
                let knob = scroll.convert(scroller.rect(for: .knob), from: scroller)
                let column = knob.maxX - 3.5
                @MainActor func darkest(_ rep: NSBitmapImageRep, scale: CGFloat) -> RGB {
                    var best: RGB = (1, 1, 1)
                    for y in stride(from: 0.5, to: scroll.bounds.height, by: 1) {
                        let p = pixel(rep, column, y, scale: scale)
                        if lum(p) < lum(best) { best = p }
                    }
                    return best
                }
                guard let (rep, scale) = render(scroll) else { return XCTFail("no bitmap") }
                let shown = darkest(rep, scale: scale)
                XCTAssertLessThan(lum(shown), 0.8, "the pill paints above the content: \(fmt(shown))")
                // The run loop turns until the fade starts: a partly faded pill is lighter.
                let deadline = Date().addingTimeInterval(3)
                while scroller.alphaValue >= 1, !scroller.isHidden, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
                XCTAssertTrue(scroll._overlayScrollersRevealed, "still shown while fading")
                XCTAssertFalse(scroller.isHidden)
                XCTAssertLessThan(scroller.alphaValue, 1, "fading: alpha \(scroller.alphaValue)")
                XCTAssertGreaterThan(scroller.alphaValue, 0, "fading: alpha \(scroller.alphaValue)")
                guard let (rep2, _) = render(scroll) else { return XCTFail("no bitmap") }
                let fading = darkest(rep2, scale: scale)
                XCTAssertGreaterThan(lum(fading), lum(shown) + 0.03, "a fading pill is lighter: \(fmt(fading)) vs \(fmt(shown))")
                // A scroll during the fade brings the pill straight back.
                scroll.scrollWheel(with: wheel)
                XCTAssertEqual(scroller.alphaValue, 1, "a scroll during the fade restores the pill")
                // Through the hold and the whole fade: hidden, alpha reset for the next showing.
                while !scroller.isHidden, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
                XCTAssertFalse(scroll._overlayScrollersRevealed, "hidden after the fade")
                XCTAssertTrue(scroller.isHidden)
                XCTAssertEqual(scroller.alphaValue, 1)
                guard let (rep3, _) = render(scroll) else { return XCTFail("no bitmap") }
                let gone = darkest(rep3, scale: scale)
                XCTAssertGreaterThan(lum(gone), 0.97, "the content shows where the pill was: \(fmt(gone))")
            }
        }
    }

    /// An empty field being edited still shows its placeholder (a find bar opens with its
    /// search field focused and empty): the composite with a placeholder differs from the
    /// same editing field without one, under both looks.
    func testPlaceholderShowsWhileAnEmptyFieldIsEdited() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            for mac in [false, true] {
                withLook(mac: mac) {
                    @MainActor func editingField(_ placeholder: String?, search: Bool) -> NSBitmapImageRep? {
                        let window = makeWindow(NSSize(width: 200, height: 60), dark: false)
                        defer { window.close() }
                        let field: NSTextField = search ? NSSearchField(frame: NSRect(x: 10, y: 19, width: 180, height: 22)) : NSTextField(frame: NSRect(x: 10, y: 19, width: 180, height: 22))
                        field.placeholderString = placeholder
                        window.contentView?.addSubview(field)
                        window.makeKeyAndOrderFront(nil)
                        XCTAssertTrue(window.makeFirstResponder(field))
                        XCTAssertNotNil(field.currentEditor(), "editing")
                        XCTAssertEqual(field.currentEditor()?.string, "")
                        return render(window.contentView!)?.rep
                    }
                    for search in [false, true] {
                        let what = "\(mac ? "mac" : "default") \(search ? "search field" : "text field")"
                        guard let with = editingField("Search", search: search), let without = editingField(nil, search: search),
                              let a = with.tiffRepresentation, let b = without.tiffRepresentation else { return XCTFail("\(what): no bitmap") }
                        XCTAssertNotEqual(a, b, "\(what): the placeholder is drawn under the empty editor")
                    }
                }
            }
        }
    }

    // MARK: Typing cost

    /// A keystroke in a TextEdit-like window (a text view in a scroll view) costs the same
    /// with the macOS look on: the look changes no per-keystroke drawing of a text view.
    /// Printed for the PC checklist; asserted loosely (the host's load varies).
    func testKeystrokeCostDoesNotGrowUnderTheMacLook() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            @MainActor func msPerKeystroke(mac: Bool) -> Double {
                var ms = 0.0
                withLook(mac: mac) {
                    let window = makeWindow(NSSize(width: 600, height: 400), dark: false)
                    defer { window.close() }
                    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
                    scroll.hasVerticalScroller = true
                    scroll.autohidesScrollers = true
                    let tv = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
                    tv.isVerticallyResizable = true
                    tv.autoresizingMask = [.width]
                    tv.textContainer?.widthTracksTextView = true
                    tv.isContinuousSpellCheckingEnabled = true
                    tv.allowsUndo = true
                    scroll.documentView = tv
                    window.contentView = scroll
                    window.makeKeyAndOrderFront(nil)
                    _ = window.makeFirstResponder(tv)
                    window.displayIfNeeded()
                    let text = "The quick brown fox jumps over the lazy dog. "
                    let chars = Array(repeating: text, count: 8).joined()
                    let start = Date()
                    for ch in chars {
                        let s = String(ch)
                        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                 characters: s, charactersIgnoringModifiers: s, isARepeat: false, keyCode: 0)!
                        window.sendEvent(e)
                        CARuntime.tick()
                        window.displayIfNeeded()
                    }
                    ms = Date().timeIntervalSince(start) * 1000 / Double(chars.count)
                    XCTAssertEqual(tv.string, chars)
                }
                return ms
            }
            _ = msPerKeystroke(mac: false)        // warm the caches once
            let off = msPerKeystroke(mac: false), on = msPerKeystroke(mac: true)
            print("keystroke in a text view: default look \(String(format: "%.2f", off)) ms, mac look \(String(format: "%.2f", on)) ms")
            XCTAssertLessThan(on, max(off * 1.5, off + 2), "the mac look does not slow typing: \(on) ms vs \(off) ms")
        }
    }

    // MARK: Inactive windows

    func testSwitchGreysInAnInactiveWindowOnlyUnderTheMacLook() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            for dark in [false, true] {
                for mac in [false, true] {
                    withLook(mac: mac) {
                        let window = makeWindow(NSSize(width: 120, height: 60), dark: dark)
                        defer { window.close() }
                        let toggle = NSSwitch(frame: NSRect(x: 20, y: 20, width: 38, height: 22))
                        toggle.state = .on
                        window.contentView?.addSubview(toggle)
                        window.makeKeyAndOrderFront(nil)
                        let what = "\(mac ? "mac" : "default") \(dark ? "dark" : "light")"
                        guard let (rep, scale) = render(toggle) else { return XCTFail("no bitmap") }
                        let track = NSPoint(x: toggle.bounds.width * 0.3, y: toggle.bounds.height / 2)
                        XCTAssertTrue(isAccent(pixel(rep, track.x, track.y, scale: scale)), "\(what): the track is the accent in a key window")
                        window.resignKey()
                        guard let (rep2, _) = render(toggle) else { return XCTFail("no bitmap") }
                        let p = pixel(rep2, track.x, track.y, scale: scale)
                        if mac { XCTAssertTrue(isGrey(p), "\(what): grey in an inactive window: \(fmt(p))") }
                        else { XCTAssertTrue(isAccent(p), "\(what): the accent stays: \(fmt(p))") }
                    }
                }
            }
        }
    }
}
