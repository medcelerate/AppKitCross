// Sibyl's inspector and settings forms against the Mac: picker items drawn from their views
// (a Label's title and icon, not a type name), a selection no item carries shows a blank
// pop-up, Toggle is a switch in a grouped form, a grouped form's text field is plain and
// trailing, stepped sliders show their ticks, form rows fit their column, and the inspector
// opens at its minimum width. The macOS numbers come from probing SwiftUI on macOS 15.

import XCTest
@testable import AppKit
@testable import SwiftUI

@MainActor
private func host<V: View>(_ view: V, width: CGFloat = 320, height: CGFloat = 400) -> (NSWindow, NSHostingView<V>) {
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

private enum Tint: String, CaseIterable, Identifiable, Hashable {
    case red, blue
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var color: Color { self == .red ? .red : .blue }
}

/// Sibyl's TintLabel: a Label built from a styled Text and Image.
private struct TintLabel: View {
    let tint: Tint
    var body: some View {
        Label {
            Text(tint.label).foregroundStyle(tint.color)
        } icon: {
            Image(systemName: "circle.fill").foregroundStyle(tint.color)
        }
    }
}

final class SwiftUIInspectorFidelityTests: XCTestCase, @unchecked Sendable {
    func testPickerItemsShowTheirLabelViews() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var tint = Tint.blue
                @State var symbol = "mic"
                var body: some View {
                    Form {
                        Picker("Colour", selection: $tint) {
                            ForEach(Tint.allCases) { TintLabel(tint: $0).tag($0) }
                        }
                        Picker("Icon", selection: $symbol) {
                            ForEach(["mic", "star"], id: \.self) { s in
                                Label(s, systemImage: s).labelStyle(.iconOnly).tag(s)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .formStyle(.grouped)
                }
            }
            let (w, h) = host(Probe())
            let popUps = allViews(h).compactMap { $0 as? NSPopUpButton }
            XCTAssertEqual(popUps.count, 2)
            XCTAssertEqual(popUps[0].itemTitles, ["Red", "Blue"], "a custom view's Label gives its title, not a type name")
            XCTAssertEqual(popUps[0].titleOfSelectedItem, "Blue")
            XCTAssertNotNil(popUps[0].item(at: 0)?.image, "the Label's icon goes on the menu item")
            XCTAssertEqual(popUps[1].itemTitles, ["mic", "star"], "a Label under modifiers still gives its title")
            XCTAssertNotNil(popUps[1].item(at: 1)?.image)
            XCTAssertFalse(popUps.flatMap(\.itemTitles).contains { $0.contains("<") || $0.contains("Label") })
            w.close()
        }
    }

    func testPickerWithoutAMatchingItemShowsABlankTitle() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var language: String? = nil
                @State var code = "xx"
                var body: some View {
                    VStack {
                        Picker("Language", selection: $language) {
                            Text("Afrikaans").tag(String?.some("af"))
                            Text("English").tag(String?.some("en"))
                        }
                        Picker("Code", selection: $code) {
                            ForEach(["af", "en"], id: \.self) { Text($0) }
                        }
                        Button("Pick") { language = "en"; code = "en" }
                    }
                }
            }
            let (w, h) = host(Probe())
            let popUps = allViews(h).compactMap { $0 as? NSPopUpButton }
            XCTAssertEqual(popUps.count, 2)
            // macOS: a nil selection (or one no item is tagged with) shows an empty pop-up.
            // The picker asks for no selected item (`selectItem(at: -1)`); that shows as
            // blank once NSPopUpButtonCell leaves a nil selection alone, as AppKit does.
            let probe = NSPopUpButton(frame: .zero, pullsDown: false)
            probe.addItems(withTitles: ["a", "b"])
            probe.selectItem(at: -1)
            if probe.indexOfSelectedItem == -1 {
                XCTAssertEqual(popUps[0].indexOfSelectedItem, -1)
                XCTAssertNil(popUps[0].titleOfSelectedItem)
                XCTAssertEqual(popUps[1].indexOfSelectedItem, -1)
            }
            let button = allViews(h).compactMap { $0 as? NSButton }.first { $0.title == "Pick" }!
            _ = button.sendAction(button.action, to: button.target)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(popUps[0].titleOfSelectedItem, "English")
            XCTAssertEqual(popUps[1].titleOfSelectedItem, "en", "a ForEach's ids tag its rows")
            w.close()
        }
    }

    func testToggleInAGroupedFormIsASwitch() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var a = true
                @State var b = false
                var body: some View {
                    VStack {
                        Form { Toggle("Mute transcription", isOn: $a) }.formStyle(.grouped)
                        Form { Toggle("Columns", isOn: $b) }
                        Form { Toggle("Checkbox", isOn: $b).toggleStyle(.checkbox) }.formStyle(.grouped)
                    }
                }
            }
            let (w, h) = host(Probe(), height: 500)
            let switches = allViews(h).compactMap { $0 as? NSSwitch }
            XCTAssertEqual(switches.count, 1, "only the grouped form's automatic toggle is a switch")
            XCTAssertEqual(switches.first?.state, .on)
            let checkboxes = allViews(h).compactMap { $0 as? NSButton }.filter { !($0 is NSSwitch) && ["Columns", "Checkbox"].contains($0.title) }
            XCTAssertEqual(checkboxes.count, 2)
            w.close()
        }
    }

    func testGroupedFormTextFieldIsPlainAndTrailing() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var name = "Show"
                @State var other = "x"
                var body: some View {
                    Form {
                        TextField("Name", text: $name)
                        TextField("Bordered", text: $other).textFieldStyle(.roundedBorder)
                    }
                    .formStyle(.grouped)
                }
            }
            let (w, h) = host(Probe())
            let fields = allViews(h).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
            let plain = fields.first { $0.stringValue == "Show" }!
            let bordered = fields.first { $0.stringValue == "x" }!
            XCTAssertFalse(plain.isBezeled, "macOS draws a grouped form's field without a bezel")
            XCTAssertFalse(plain.drawsBackground)
            XCTAssertEqual(plain.alignment, .right)
            XCTAssertTrue(bordered.isBezeled, ".roundedBorder keeps the bezel")
            XCTAssertNotEqual(bordered.alignment, .right)
            w.close()
        }
    }

    func testSteppedSliderShowsTickMarks() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var size = 14.0
                @State var cooldown = 2.0
                @State var free = 0.5
                var body: some View {
                    VStack {
                        Slider(value: $size, in: 11...32, step: 1)
                        Slider(value: $cooldown, in: 0...30, step: 0.5)
                        Slider(value: $free, in: 0...1)
                        Slider(value: $size, in: 11...32, step: 1) { Text("Size") } minimumValueLabel: { Text("small") } maximumValueLabel: { Text("LARGE") }
                    }
                }
            }
            let (w, h) = host(Probe())
            let sliders = allViews(h).compactMap { $0 as? NSSlider }
            XCTAssertEqual(sliders.count, 4)
            // macOS: steps + 1 tick marks, values only on the ticks.
            XCTAssertEqual(sliders[0].numberOfTickMarks, 22)
            XCTAssertTrue(sliders[0].allowsTickMarkValuesOnly)
            XCTAssertEqual(sliders[1].numberOfTickMarks, 61)
            XCTAssertEqual(sliders[2].numberOfTickMarks, 0)
            XCTAssertEqual(sliders[3].numberOfTickMarks, 22)
            let labels = allViews(h).compactMap { ($0 as? _TextView)?.storage.string }
            XCTAssertTrue(labels.contains("small") && labels.contains("LARGE"), "the value labels are drawn as the views given")
            let small = allViews(h).first { ($0 as? _TextView)?.storage.string == "small" }!
            let large = allViews(h).first { ($0 as? _TextView)?.storage.string == "LARGE" }!
            let sf = sliders[3].convert(sliders[3].bounds, to: nil)
            XCTAssertLessThanOrEqual(small.convert(small.bounds, to: nil).maxX, sf.minX + 1)
            XCTAssertGreaterThanOrEqual(large.convert(large.bounds, to: nil).minX, sf.maxX - 1)
            w.close()
        }
    }

    func testGroupedFormRowsFitANarrowColumn() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var name = "A rather long channel name"
                @State var tint = Tint.blue
                @State var muted = false
                @State var engine = "Long-form speech recogniser (on device)"
                var body: some View {
                    Form {
                        Section("Channel") {
                            TextField("Name", text: $name)
                            Picker("Colour", selection: $tint) { ForEach(Tint.allCases) { TintLabel(tint: $0).tag($0) } }
                            Picker("Model", selection: $engine) {
                                Text("Long-form speech recogniser (on device)").tag("Long-form speech recogniser (on device)")
                                Text("Whisper").tag("Whisper")
                            }
                            Toggle("Mute transcription while the channel is idle", isOn: $muted)
                            LabeledContent("Status") {
                                HStack { Image(systemName: "waveform"); Text("Installed and ready to transcribe") }
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
            }
            let width: CGFloat = 210
            let (w, h) = host(Probe(), width: width, height: 400)
            let hostFrame = h.convert(h.bounds, to: nil)
            for v in allViews(h) where (v is NSControl || v is _TextView) && !v.isHiddenOrHasHiddenAncestor {
                let f = v.convert(v.bounds, to: nil)
                XCTAssertLessThanOrEqual(f.maxX, hostFrame.maxX + 0.5, "\(type(of: v)) \(f) overflows the \(width)-point column")
            }
            w.close()
        }
    }

    func testGroupedFormRowHeightMatchesMacOS() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Probe: View {
                var body: some View {
                    Form {
                        Section("Show") {
                            LabeledContent("Channels", value: "3")
                            LabeledContent("Lines captured", value: "12")
                            LabeledContent("State", value: "Idle")
                        }
                    }
                    .formStyle(.grouped)
                }
            }
            let (w, h) = host(Probe())
            let ys = ["Channels", "Lines captured", "State"].map { title in
                allViews(h).first { ($0 as? _TextView)?.storage.string == title }!.convert(NSPoint.zero, to: h).y
            }
            // macOS 15: a grouped form's text rows are 37 points apart (36 and a separator).
            XCTAssertEqual(abs(ys[1] - ys[0]), 37, accuracy: 0.5)
            XCTAssertEqual(abs(ys[2] - ys[1]), 37, accuracy: 0.5)
            w.close()
        }
    }

    func testInspectorOpensAtItsMinimumWidth() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Probe: View {
                let mode: Int
                var body: some View {
                    NavigationSplitView {
                        List { Text("Sidebar") }.navigationSplitViewColumnWidth(min: 140, ideal: 250, max: 420)
                    } detail: {
                        Text("Detail")
                            .inspector(isPresented: .constant(true)) {
                                switch mode {
                                case 0: Form { Text("x") }.formStyle(.grouped).inspectorColumnWidth(min: 210, ideal: 330, max: 520)
                                case 1: Form { Text("x") }.formStyle(.grouped).inspectorColumnWidth(ideal: 330)
                                case 2: Form { Text("x") }.formStyle(.grouped).inspectorColumnWidth(300)
                                default: Form { Text("x") }.formStyle(.grouped)
                                }
                            }
                    }
                }
            }
            // macOS 15 at 1100 points: sidebar 250, then the inspector at its minimum (210),
            // at 270 when no minimum is given (an ideal alone is not used), at a fixed width.
            for (mode, expected) in [(0, 210.0), (1, 270.0), (2, 300.0), (3, 270.0)] {
                let (w, h) = host(Probe(mode: mode), width: 1100, height: 700)
                let splits = allViews(h).compactMap { $0 as? NSSplitView }
                XCTAssertEqual(splits.count, 2)
                XCTAssertEqual(splits[0].subviews.first?.frame.width ?? 0, 250, accuracy: 0.5, "mode \(mode)")
                let inner = splits[1].subviews.filter { !$0.isHidden }
                XCTAssertEqual(inner.last?.frame.width ?? 0, CGFloat(expected), accuracy: 0.5, "mode \(mode)")
                w.close()
            }
        }
    }
    /// Sibyl's channel inspector (a grouped Form in a 210-point `.inspector` column of an
    /// 1100×700 window): every row fits the column, as on the Mac. Labels truncate, pop-ups,
    /// switches, fields and buttons shrink to what is left, and each card sits inside the
    /// column by the form's inset, with nothing drawn past it.
    func testInspectorFormFitsItsColumn() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var name = "Production"
                @State var tint = Tint.blue
                @State var product = "Product: Shure ULX-D Receiver"
                @State var hardware = "1 — Shure ULX-D Receiver Channel One Left"
                @State var muted = false
                @State var speakers = true
                @State var notes = "Crew names, venue names and cue labels are the ones worth adding to this list."
                var body: some View {
                    NavigationSplitView {
                        List { Text("Production") }.navigationSplitViewColumnWidth(min: 140, ideal: 250, max: 420)
                    } detail: {
                        Text("Detail")
                            .inspector(isPresented: .constant(true)) {
                                Form {
                                    Section("Channel") {
                                        TextField("Name", text: $name)
                                        Picker("Colour", selection: $tint) { ForEach(Tint.allCases) { TintLabel(tint: $0).tag($0) } }
                                        Picker("Product Configuration", selection: $product) {
                                            Text("Product: Shure ULX-D Receiver").tag("Product: Shure ULX-D Receiver")
                                            Text("Product: Sennheiser EW-DX Receiver").tag("Product: Sennheiser EW-DX Receiver")
                                        }
                                    }
                                    Section("Input") {
                                        Picker("Hardware Channel", selection: $hardware) {
                                            Text("1 — Shure ULX-D Receiver Channel One Left").tag("1 — Shure ULX-D Receiver Channel One Left")
                                        }
                                        Toggle("Mute transcription while the channel is idle", isOn: $muted)
                                        Toggle("Label speakers on this channel", isOn: $speakers)
                                        LabeledContent("Model Status") {
                                            HStack(spacing: 6) { Image(systemName: "checkmark.circle.fill"); Text("Installed") }
                                        }
                                        LabeledContent("Status", value: "Ready")
                                    }
                                    Section("Channel Vocabulary") {
                                        HStack {
                                            TextField("", text: $notes, prompt: Text("Add a name, cue label or piece of jargon"), axis: .vertical)
                                                .textFieldStyle(.roundedBorder).labelsHidden()
                                            Button("Add") {}
                                        }
                                        TextField("Notes", text: $notes, axis: .vertical)
                                    }
                                    Section {
                                        Button("Clear This Channel's Transcript", role: .destructive) {}
                                        Button("Delete Channel", role: .destructive) {}
                                    }
                                }
                                .formStyle(.grouped)
                                .inspectorColumnWidth(min: 210, ideal: 330, max: 520)
                            }
                    }
                }
            }
            let (w, h) = host(Probe(), width: 1100, height: 700)
            h.layoutSubtreeIfNeeded()
            let splits = allViews(h).compactMap { $0 as? NSSplitView }
            guard splits.count == 2, let pane = splits[1].subviews.filter({ !$0.isHidden }).last else { return XCTFail("no inspector column") }
            let column = pane.convert(pane.bounds, to: nil)
            XCTAssertEqual(column.width, 210, accuracy: 0.5)
            // No view of the inspector extends right of its column.
            for v in allViews(pane) where !v.isHiddenOrHasHiddenAncestor && v.frame.width > 0 {
                let f = v.convert(v.bounds, to: nil)
                XCTAssertLessThanOrEqual(f.maxX, column.maxX + 0.5, "\(type(of: v)) \(f) extends right of the inspector column \(column)")
            }
            // Each control and label also sits inside its card: right of the card's 16-point
            // inset from the column, and the cards themselves end at the inset.
            let inset: CGFloat = 16
            for v in allViews(pane) where (v is NSControl || v is _TextView) && !v.isHiddenOrHasHiddenAncestor && v.frame.width > 0 {
                let f = v.convert(v.bounds, to: nil)
                XCTAssertLessThanOrEqual(f.maxX, column.maxX - inset + 0.5, "\(type(of: v)) \(f) overflows its card in \(column)")
            }
            // The switches show whole (not half cut by the card's edge).
            let switches = allViews(pane).compactMap { $0 as? NSSwitch }
            XCTAssertEqual(switches.count, 2)
            for s in switches { XCTAssertGreaterThanOrEqual(s.frame.width, s.intrinsicContentSize.width - 0.5, "a switch keeps its size") }
            // Pixels: the strip between the cards' right edge and the column's edge is the page
            // (window background) only; the card's border sits at the inset.
            guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { return XCTFail("no bitmap") }
            h.cacheDisplay(in: h.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / h.bounds.width
            let colInHost = h.convert(pane.bounds, from: pane)
            func px(_ x: CGFloat, _ y: CGFloat) -> NSColor {
                let c = rep.colorAt(x: Int(x * scale), y: Int(y * scale)) ?? .black
                return c.usingColorSpace(.deviceRGB) ?? c
            }
            let page = px(colInHost.maxX - 3, colInHost.minY + 8)
            var cardEdge = 0
            for yPt in stride(from: colInHost.minY + 30, to: colInHost.maxY - 4, by: 4) {
                for xPt in stride(from: colInHost.maxX - inset + 2, to: colInHost.maxX - 1, by: 1) {
                    let c = px(xPt, yPt)
                    let d = abs(c.redComponent - page.redComponent) + abs(c.greenComponent - page.greenComponent) + abs(c.blueComponent - page.blueComponent)
                    XCTAssertLessThan(d, 0.06, "something is drawn in the inset right of the cards at (\(xPt), \(yPt)): \(c) vs page \(page)")
                    if d >= 0.06 { return w.close() }
                }
                let border = px(colInHost.maxX - inset, yPt), inside = px(colInHost.maxX - inset - 3, yPt)
                if abs(inside.redComponent - page.redComponent) > 0.02 || abs(border.redComponent - page.redComponent) > 0.02 { cardEdge += 1 }
            }
            XCTAssertGreaterThan(cardEdge, 10, "the cards reach the column's inset")
            w.close()
        }
    }
    /// Sibyl's Icon picker: icon-only Label items. The closed pop-up draws the selected
    /// item's glyph (template, label colour), not the symbol's name; an image-and-title
    /// item (the Colour picker's swatch and name) draws both; a `Label("", systemImage:)`
    /// draws the image alone. The menu items keep their titles and images.
    func testPickerFaceDrawsTheSelectedItemsImage() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var symbol = "headphones"
                @State var bare = "star"
                @State var tint = Tint.blue
                var body: some View {
                    Form {
                        Picker("Icon", selection: $symbol) {
                            ForEach(["star", "headphones"], id: \.self) { s in
                                Label(s, systemImage: s).labelStyle(.iconOnly).tag(s)
                            }
                        }
                        .pickerStyle(.menu)
                        Picker("Bare", selection: $bare) {
                            ForEach(["star", "mic"], id: \.self) { s in Label("", systemImage: s).tag(s) }
                        }
                        Picker("Colour", selection: $tint) {
                            ForEach(Tint.allCases) { TintLabel(tint: $0).tag($0) }
                        }
                    }
                    .formStyle(.grouped)
                }
            }
            let (w, h) = host(Probe(), width: 320, height: 300)
            let popUps = allViews(h).compactMap { $0 as? NSPopUpButton }
            XCTAssertEqual(popUps.count, 3)
            guard popUps.count == 3 else { return w.close() }
            let (icon, bare, colour) = (popUps[0], popUps[1], popUps[2])
            XCTAssertEqual(icon.itemTitles, ["star", "headphones"], "the menu items keep their titles")
            XCTAssertNotNil(icon.selectedItem?.image)
            XCTAssertEqual(icon.imagePosition, .imageOnly, "an icon-only label's face is its image alone")
            XCTAssertEqual(colour.imagePosition, .imageLeft)
            XCTAssertNotNil(colour.selectedItem?.image, "the swatch is the Colour item's image")
            // The face is sized for the glyph, not the symbol's name.
            let chrome = NSPopUpButtonCell.titleInset + NSPopUpButtonCell.arrowAreaWidth
            XCTAssertEqual(icon.cell!.cellSize.width, (16 + chrome).rounded(.up), accuracy: 0.5)
            XCTAssertEqual(bare.cell!.cellSize.width, (16 + chrome).rounded(.up), accuracy: 0.5)
            let blueWidth = "Blue".size(withAttributes: [.font: colour.font ?? NSFont.systemFont(ofSize: 13)]).width
            XCTAssertGreaterThanOrEqual(colour.cell!.cellSize.width, (16 + 4 + blueWidth + chrome).rounded(.down), "image, gap and title")

            // Pixels: ink (dark against the white bezel) per point column of the face.
            @MainActor func inkColumns(_ b: NSPopUpButton) -> [Int] {
                guard let rep = b.bitmapImageRepForCachingDisplay(in: b.bounds) else { return [] }
                b.cacheDisplay(in: b.bounds, to: rep)
                let scale = CGFloat(rep.pixelsWide) / b.bounds.width
                var columns: [Int] = []
                let faceEnd = b.bounds.width - NSPopUpButtonCell.arrowAreaWidth
                for x in stride(from: CGFloat(3), to: faceEnd, by: 1) {
                    var ink = 0
                    for y in stride(from: CGFloat(3), to: b.bounds.height - 3, by: 1) {
                        guard let c = rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.deviceRGB) else { continue }
                        if (c.redComponent + c.greenComponent + c.blueComponent) / 3 < 0.6 && c.alphaComponent > 0.5 { ink += 1 }
                    }
                    if ink > 0 { columns.append(Int(x)) }
                }
                return columns
            }
            let inset = Int(NSPopUpButtonCell.titleInset)
            for (name, b) in [("icon", icon), ("bare", bare)] {
                let ink = inkColumns(b)
                XCTAssertFalse(ink.isEmpty, "\(name): the glyph is drawn")
                XCTAssertTrue(ink.allSatisfy { $0 >= inset - 1 && $0 <= inset + 16 }, "\(name): only the 16-point glyph is drawn, no symbol name: \(ink)")
            }
            let colourInk = inkColumns(colour)
            XCTAssertTrue(colourInk.contains { $0 >= inset && $0 < inset + 16 }, "the swatch is drawn: \(colourInk)")
            XCTAssertTrue(colourInk.contains { $0 >= inset + 20 }, "the title follows the swatch: \(colourInk)")
            w.close()
        }
    }
}
