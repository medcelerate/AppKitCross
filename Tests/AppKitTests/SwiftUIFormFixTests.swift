// Form fixes the Sibyl settings window needed on the PC: a grouped form scrolls and keeps its
// rows at their ideal heights, an expanded DisclosureGroup stacks its rows, titled controls
// are labelled rows inside a form (`labelsHidden()` turns that off), LabeledContent dims only
// text, and the SF Symbols names Sibyl uses are drawn (composed variants included).

import XCTest
@testable import AppKit
@testable import SwiftUI

@MainActor
private func host<V: View>(_ view: V, width: CGFloat = 420, height: CGFloat = 320) -> (NSWindow, NSHostingView<V>) {
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
@MainActor
private func textView(_ h: NSView, _ s: String) -> _TextView? { allViews(h).compactMap { $0 as? _TextView }.first { $0.storage.string == s } }
@MainActor
private func frameIn(_ h: NSView, _ v: NSView) -> CGRect { h.convert(v.bounds, from: v) }
/// Plain text fields (not secure ones, not the text views SwiftUI draws text with).
@MainActor
private func fields(_ h: NSView) -> [NSTextField] { allViews(h).compactMap { $0 as? NSTextField }.filter { !($0 is NSSecureTextField) && $0.isEditable } }

/// Sibyl's `settingsNote()`: a centred, secondary, full-width description.
extension View {
    fileprivate func _sibylNote() -> some View {
        font(.callout).foregroundStyle(Color.secondary).frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
    }
}
/// A grouped form's scroll document (flipped: y grows downward).
@MainActor
private func formDocument(_ h: NSView) -> NSView? { allViews(h).compactMap { $0 as? NSScrollView }.first?.documentView }
@MainActor
private func docFrame(_ doc: NSView, _ v: NSView) -> CGRect { doc.convert(v.bounds, from: v) }
/// The grouped cards (their rounded backgrounds) in document coordinates: shape views wider
/// and taller than a hairline.
@MainActor
private func cards(_ doc: NSView) -> [CGRect] {
    var seen: [CGRect] = []
    for v in allViews(doc) where v is _ShapeDrawingView {
        let f = docFrame(doc, v)
        if f.height > 4, f.width > 100, !seen.contains(where: { (r: CGRect) in r == f }) { seen.append(f) }
    }
    return seen
}
/// The hairline separators (dividers) in document coordinates.
@MainActor
private func hairlines(_ doc: NSView) -> [CGRect] {
    allViews(doc).filter { $0 is _ShapeDrawingView }.map { docFrame(doc, $0) }.filter { $0.height <= 1.5 && $0.width > 50 }
}
@MainActor
private func card(containing r: CGRect, in doc: NSView) -> CGRect? {
    cards(doc).filter { $0.insetBy(dx: -0.5, dy: -0.5).contains(r) }.min { $0.height < $1.height }
}

private func render(_ image: NSImage) -> CGImage {
    let ctx = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    image.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

final class SwiftUIFormFixTests: XCTestCase, @unchecked Sendable {
    // MARK: Grouped forms scroll

    func testGroupedFormScrollsInAShortFrameAndKeepsRowHeights() {
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var values = Array(repeating: "", count: 12)
                var body: some View {
                    Form {
                        Section("Destination") {
                            ForEach(0..<12, id: \.self) { i in TextField("Field \(i)", text: $values[i]) }
                        }
                    }
                    .formStyle(.grouped)
                    .frame(height: 210)
                }
            }
            let (w, h) = host(Probe())
            guard let scroll = allViews(h).compactMap({ $0 as? NSScrollView }).first else { return XCTFail("the grouped form is not a scroll view") }
            XCTAssertEqual(scroll.frame.height, 210, accuracy: 1, "the form takes its frame's height")
            XCTAssertGreaterThan(scroll.documentView?.frame.height ?? 0, 210, "the rows are taller than the frame: the form scrolls")
            let rows = fields(h)
            XCTAssertEqual(rows.count, 12)
            // A field's ideal height follows the platform font (about 21 on macOS, taller
            // with Segoe UI on Windows): every field keeps its own ideal height, unsqueezed.
            for f in rows {
                XCTAssertEqual(f.frame.height, f.fittingSize.height, accuracy: 1, "a field keeps its ideal height")
                XCTAssertGreaterThan(f.frame.height, 16)
            }
            let frames = rows.map { scroll.documentView!.convert($0.bounds, from: $0) }.sorted { $0.minY < $1.minY }
            for (a, b) in zip(frames, frames.dropFirst()) { XCTAssertLessThanOrEqual(a.maxY, b.minY + 0.5, "rows do not overlap") }
            w.close()
        }
    }

    func testGroupedFormFillsAFlexibleContainer() {
        MainActor.assumeIsolated {
            let (w, h) = host(HStack { Form { TextField("Name", text: .constant("")) }.formStyle(.grouped) }, width: 500, height: 380)
            guard let scroll = allViews(h).compactMap({ $0 as? NSScrollView }).first else { return XCTFail("no scroll view") }
            XCTAssertEqual(scroll.frame.height, 380, accuracy: 1)
            XCTAssertEqual(scroll.frame.width, 500, accuracy: 1)
            w.close()
        }
    }

    // MARK: DisclosureGroup in a grouped form (Sibyl's ActionAdder)

    func testDisclosureGroupExpandsWithEveryRowAtItsIdealHeight() {
        MainActor.assumeIsolated {
            enum Kind: String, CaseIterable { case note, cc }
            struct Adder: View {
                @State var expanded = false
                @State var kind = Kind.note
                @State var destination = "Synth"
                @State var address = ""
                @State var argument = ""
                @State var note = 60.0
                var body: some View {
                    DisclosureGroup("Add action", isExpanded: $expanded) {
                        Picker("Type", selection: $kind) { ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        Picker("Destination", selection: $destination) { Text("Synth").tag("Synth"); Text("Lights").tag("Lights") }
                        TextField("Address", text: $address, prompt: Text("/path"))
                        TextField("String argument (optional)", text: $argument)
                        LabeledContent("Note") { Slider(value: $note, in: 0...127) }
                        Button("Add") {}
                    }
                }
            }
            struct RuleEditor: View {
                @State var name = "Rule"
                @State var enabled = true
                var body: some View {
                    Form {
                        Section("Rule") {
                            TextField("Name", text: $name)
                            Toggle("Enabled", isOn: $enabled)
                        }
                        Section("Actions") {
                            HStack {
                                Image(systemName: "pianokeys")
                                Text("Note 60")
                                Spacer()
                                Button {} label: { Image(systemName: "minus.circle.fill") }.buttonStyle(.borderless)
                            }
                            Adder()
                        }
                    }
                    .formStyle(.grouped)
                }
            }
            let (w, h) = host(RuleEditor(), width: 520, height: 300)
            guard let expand = allViews(h).first(where: { $0.accessibilityLabel() == "expand" }) else { return XCTFail("no disclosure triangle") }
            XCTAssertTrue(expand.accessibilityPerformPress())
            h.layoutSubtreeIfNeeded()
            h.layoutSubtreeIfNeeded()
            guard let document = allViews(h).compactMap({ $0 as? NSScrollView }).first?.documentView else { return XCTFail("no scroll view") }
            let popups = allViews(h).compactMap { $0 as? NSPopUpButton }
            XCTAssertEqual(popups.count, 2, "both pickers show")
            let adderFields = fields(h).filter { $0.placeholderString == "/path" || $0.placeholderString == "" }
            XCTAssertEqual(adderFields.count, 3, "Name, Address and the argument field (the titles are labels in the form)")
            guard let add = allViews(h).compactMap({ $0 as? NSButton }).first(where: { $0.title == "Add" }),
                  let slider = allViews(h).compactMap({ $0 as? NSSlider }).first else { return XCTFail("no Add button or slider") }
            let controls: [NSView] = popups + adderFields + [slider, add]
            let frames = controls.map { document.convert($0.bounds, from: $0) }
            for (i, a) in frames.enumerated() {
                XCTAssertGreaterThanOrEqual(a.height, 15, "\(type(of: controls[i])) keeps its height")
                for (j, b) in frames.enumerated() where j > i {
                    XCTAssertFalse(a.insetBy(dx: 0.5, dy: 0.5).intersects(b), "\(type(of: controls[i])) \(a) overlaps \(type(of: controls[j])) \(b)")
                }
            }
            let addFrame = document.convert(add.bounds, from: add)
            for f in frames.dropLast() {
                if document.isFlipped { XCTAssertGreaterThanOrEqual(addFrame.minY, f.maxY - 0.5, "Add is below the fields") }
                else { XCTAssertLessThanOrEqual(addFrame.maxY, f.minY + 0.5, "Add is below the fields") }
            }
            // The action row's icon and its borderless minus button are drawn.
            let images = allViews(h).compactMap { $0 as? NSImageView }
            XCTAssertGreaterThanOrEqual(images.filter { $0.image != nil }.count, 2, "the row's symbol and the minus button's symbol")
            w.close()
        }
    }

    // MARK: Labels in forms

    func testTitledControlsAreLabelledRowsInAGroupedForm() {
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var name = ""
                @State var secret = ""
                @State var transport = "UDP"
                var body: some View {
                    Form {
                        TextField("Name", text: $name)
                        SecureField("Password", text: $secret)
                        Picker("Transport", selection: $transport) { Text("UDP").tag("UDP"); Text("TCP").tag("TCP") }
                        Toggle("Enabled", isOn: .constant(true))
                    }
                    .formStyle(.grouped)
                }
            }
            let (w, h) = host(Probe())
            let t = texts(h)
            for s in ["Name", "Password", "Transport"] { XCTAssertEqual(t.filter { $0 == s }.count, 1, "\(s) is shown once as a label: \(t)") }
            guard let field = fields(h).first, let secure = allViews(h).compactMap({ $0 as? NSSecureTextField }).first,
                  let popup = allViews(h).compactMap({ $0 as? NSPopUpButton }).first else { return XCTFail("controls missing") }
            XCTAssertEqual(field.placeholderString ?? "", "", "the title is the label, not the placeholder")
            XCTAssertEqual(secure.placeholderString ?? "", "")
            XCTAssertEqual(popup.accessibilityLabel(), "Transport", "the label still names the control")
            for (label, control) in [("Name", field as NSView), ("Password", secure), ("Transport", popup)] {
                let l = frameIn(h, textView(h, label)!), c = frameIn(h, control)
                XCTAssertLessThan(l.maxX, c.minX, "\(label) leads its control")
                XCTAssertEqual(l.midY, c.midY, accuracy: 3, "\(label) is on its control's row")
            }
            // Grouped rows put a fixed control at the trailing edge.
            XCTAssertGreaterThan(frameIn(h, popup).maxX, 300)
            XCTAssertNotNil(allViews(h).compactMap { $0 as? _SwiftUISwitchRow }.first { $0.label.stringValue == "Enabled" }, "a grouped form's toggle is a switch with its title beside it")
            w.close()
        }
    }

    func testColumnsFormSharesATrailingAlignedLabelColumn() {
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var a = ""
                @State var b = ""
                var body: some View {
                    Form {
                        TextField("Host", text: $a)
                        TextField("A much longer label", text: $b)
                        LabeledContent("Port", value: "9000")
                    }
                }
            }
            let (w, h) = host(Probe(), width: 480)
            h.layoutSubtreeIfNeeded()            // the label column arrives after the first pass
            h.layoutSubtreeIfNeeded()
            let host1 = frameIn(h, textView(h, "Host")!), long = frameIn(h, textView(h, "A much longer label")!), port = frameIn(h, textView(h, "Port")!)
            XCTAssertEqual(host1.maxX, long.maxX, accuracy: 1, "labels are trailing-aligned in one column")
            XCTAssertEqual(port.maxX, long.maxX, accuracy: 1, "LabeledContent's label is in the column too")
            let f = fields(h).map { frameIn(h, $0) }
            XCTAssertEqual(f.count, 2)
            XCTAssertEqual(f[0].minX, f[1].minX, accuracy: 1, "controls lead one column")
            XCTAssertGreaterThan(f[0].minX, long.maxX)
            XCTAssertEqual(frameIn(h, textView(h, "9000")!).minX, f[0].minX, accuracy: 1)
            // The column is stable: another pass measures and changes nothing.
            let passes = _ViewRoot._layoutPassCount
            h.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(_ViewRoot._layoutPassCount - passes, 1)
            XCTAssertEqual(frameIn(h, textView(h, "Host")!).maxX, host1.maxX, accuracy: 0.5)
            w.close()
        }
    }

    func testLabelsHiddenAndControlsOutsideAForm() {
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var name = ""
                @State var pick = 1
                var body: some View {
                    VStack {
                        TextField("Outside", text: $name)
                        Picker("Hidden picker", selection: $pick) { Text("One").tag(1); Text("Two").tag(2) }.labelsHidden()
                        Picker("Shown picker", selection: $pick) { Text("One").tag(1); Text("Two").tag(2) }
                        Form { TextField("Hidden label", text: $name).labelsHidden() }
                    }
                }
            }
            let (w, h) = host(Probe())
            let t = texts(h)
            XCTAssertFalse(t.contains("Outside"), "outside a form the title is only the placeholder")
            XCTAssertFalse(t.contains("Hidden label"), "labelsHidden keeps a form field unlabelled")
            XCTAssertFalse(t.contains("Hidden picker"))
            XCTAssertTrue(t.contains("Shown picker"), "a picker outside a form still shows its label")
            let placeholders = Set(fields(h).compactMap(\.placeholderString))
            XCTAssertEqual(placeholders, ["Outside", "Hidden label"])
            XCTAssertNotNil(allViews(h).compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == "Hidden picker" })
            w.close()
        }
    }

    func testLabeledContentDimsTextButNotControls() {
        MainActor.assumeIsolated {
            let (w, h) = host(Form {
                LabeledContent("Reminder", value: "1:00 PM")
                LabeledContent("Cooldown") { HStack { Slider(value: .constant(0.5)); Text("0.5 s") } }
            }.formStyle(.grouped))
            @MainActor func color(_ s: String) -> NSColor? { textView(h, s)?.storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor }
            XCTAssertNotNil(color("1:00 PM"))
            XCTAssertNotEqual(color("1:00 PM"), color("0.5 s"), "a value is secondary, a control's own text is not")
            XCTAssertEqual(color("0.5 s"), color("Cooldown"), "the control row keeps the primary colour")
            XCTAssertNotNil(allViews(h).first { $0 is NSSlider })
            w.close()
        }
    }

    // MARK: Grouped form layout (the PC's Settings screenshots against macOS's)

    /// Every footer shape Sibyl uses lands under its card: a Text after one Text row with no
    /// header, a footer of a VStack, a Label footer, and after a header and an optional row.
    /// A description written as a row (Audio ▸ Reliability, the License pane's "not active"
    /// section) is a row on macOS too, inside the card.
    func testGroupedFootersSitBelowTheirCards() {
        MainActor.assumeIsolated {
            struct Probe: View {
                var working = false
                var body: some View {
                    Form {
                        Section { Text("Only row") } footer: { Text("Footer one").font(.caption) }
                        Section {
                            LabeledContent("Status") { Text("Not enforced") }
                            if working { LabeledContent("") { Text("Contacting") } }
                        } header: { Text("License") } footer: { Text("Footer two")._sibylNote() }
                        Section("Reliability") {
                            LabeledContent("Dropped frames", value: "0")
                            Text("Row note")._sibylNote()
                        }
                        Section { Toggle("Add to this show", isOn: .constant(false)) } footer: {
                            VStack(spacing: 4) { Text("Footer three"); Text("Footer four") }._sibylNote()
                        }
                        Section { Button("Start Free Trial") {} } footer: { Label("Footer five", systemImage: "info.circle")._sibylNote() }
                    }
                    .formStyle(.grouped)
                }
            }
            let (w, h) = host(Probe(), width: 460, height: 700)
            // From the first pass the sections are cards of their own: no outer card holds
            // them (and their footers) while the sections' preference is on its way.
            // The form finds its sections among its rows without waiting for them to render
            // (inside a switch too, as the License pane's are).
            @ViewBuilder func licenseRows(_ state: Int) -> some View {
                Section { Text("Status") } header: { Text("License") } footer: { Text("Footer") }
                switch state {
                case 0: Section { Text("Not active") }
                default: Section { Button("Activate") {} } footer: { Text("Trial") }
                }
            }
            XCTAssertEqual(_formSectionRows(_ViewBox(licenseRows(0))).filter { $0.value is any _FormSectionMarker }.count, 2)
            XCTAssertFalse(_formSectionRows(_ViewBox(Group { Text("Name"); Toggle("On", isOn: .constant(true)) })).contains { $0.value is any _FormSectionMarker })
            if let first = formDocument(h) {
                let c = cards(first)
                let nested = c.contains(where: { (a: CGRect) -> Bool in c.contains(where: { (b: CGRect) -> Bool in a != b && a.contains(b) }) })
                XCTAssertFalse(nested, "no card holds another on the first pass: \(c)")
            } else { XCTFail("no scroll document on the first pass") }
            h.layoutSubtreeIfNeeded()
            guard let doc = formDocument(h) else { return XCTFail("no scroll document") }
            @MainActor func frame(_ s: String) -> CGRect? { textView(doc, s).map { docFrame(doc, $0) } }
            let pairs: [(row: String, footer: String)] = [("Only row", "Footer one"), ("Status", "Footer two"), ("Add to this show", "Footer three"),
                                                          ("Add to this show", "Footer four"), ("Start Free Trial", "Footer five")]
            for (row, footer) in pairs {
                let rowView: NSView? = textView(doc, row) ?? allViews(doc).compactMap { $0 as? NSButton }.first { $0.title == row }
                    ?? allViews(doc).compactMap { $0 as? _SwiftUISwitchRow }.first { $0.label.stringValue == row }
                guard let rowView, let f = frame(footer), let c = card(containing: docFrame(doc, rowView), in: doc) else { XCTFail("\(row)/\(footer) missing"); continue }
                XCTAssertGreaterThanOrEqual(f.minY, c.maxY - 0.5, "\(footer) \(f) is below the card \(c) of \(row)")
                XCTAssertFalse(cards(doc).contains { $0.insetBy(dx: 1, dy: 1).intersects(f) }, "\(footer) is inside no card")
                XCTAssertEqual(f.midX, c.midX, accuracy: 30, "\(footer) is centred under the card")
            }
            guard let note = frame("Row note"), let reliability = frame("Dropped frames"), let c = card(containing: reliability, in: doc) else { return XCTFail("Reliability missing") }
            XCTAssertTrue(c.contains(note), "a description written as a row stays inside its card, as on macOS")
            w.close()
        }
    }

    /// A grouped form of bare rows (Sibyl's Destinations editor) is one card with a hairline
    /// between each pair of rows.
    func testBareRowsGroupedFormHasSeparatorsBetweenRows() {
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var name = "Lights"
                @State var host = "10.0.0.2"
                @State var port = 9000
                @State var transport = "UDP"
                @State var enabled = true
                var body: some View {
                    Form {
                        TextField("Name", text: $name)
                        TextField("Host", text: $host)
                        TextField("Port", value: $port, format: .number)
                        Picker("Transport", selection: $transport) { Text("UDP").tag("UDP"); Text("TCP").tag("TCP") }
                        Toggle("Enabled", isOn: $enabled)
                    }
                    .formStyle(.grouped)
                    .frame(height: 260)
                }
            }
            let (w, h) = host(Probe(), width: 460, height: 300)
            guard let doc = formDocument(h) else { return XCTFail("no scroll document") }
            let lines = hairlines(doc)
            XCTAssertEqual(lines.count, 4, "n-1 separators between 5 rows: \(lines)")
            XCTAssertEqual(cards(doc).count, 1, "one card")
            let labels = ["Name", "Host", "Port", "Transport"].compactMap { textView(doc, $0).map { docFrame(doc, $0) } }
            XCTAssertEqual(labels.count, 4)
            let sortedLines = lines.sorted { $0.minY < $1.minY }
            for (i, l) in labels.enumerated() {
                XCTAssertLessThanOrEqual(l.maxY, sortedLines[i].minY + 0.5, "row \(i) is above separator \(i)")
                if i > 0 { XCTAssertGreaterThanOrEqual(l.minY, sortedLines[i - 1].maxY - 0.5, "row \(i) is below separator \(i - 1)") }
            }
            w.close()
        }
    }

    /// A header built from a Label and a Link (Sibyl's integrations) lines up with a Text
    /// header; a symbol without artwork does not push the title in by an empty icon slot;
    /// the Link keeps its caption font.
    func testNonTextSectionHeaderAlignsWithATextHeader() {
        MainActor.assumeIsolated {
            struct Probe: View {
                var body: some View {
                    Form {
                        Section { Text("Row a") } header: { Text("Plain") }
                        Section { Text("Row b") } header: {
                            HStack {
                                Label("Vor", systemImage: "no.such.symbol.anywhere")
                                Text("Added").font(.caption)
                                Spacer()
                                Link("Website", destination: URL(string: "https://example.com")!).font(.caption)
                            }
                        }
                        Section { Text("Row c") } header: { Label("Globe", systemImage: "globe") }
                    }
                    .formStyle(.grouped)
                }
            }
            let (w, h) = host(Probe(), width: 460, height: 500)
            guard let doc = formDocument(h), let plain = textView(doc, "Plain"), let vor = textView(doc, "Vor"), let globe = textView(doc, "Globe") else { return XCTFail("headers missing") }
            XCTAssertEqual(docFrame(doc, vor).minX, docFrame(doc, plain).minX, accuracy: 1, "an icon-less Label header starts where a Text header does")
            let icon = allViews(doc).compactMap { $0 as? NSImageView }.filter { $0.image != nil }.map { docFrame(doc, $0) }.first { abs($0.midY - docFrame(doc, globe).midY) < 6 }
            XCTAssertNotNil(icon, "a drawn symbol keeps its slot")
            if let icon { XCTAssertEqual(icon.minX, docFrame(doc, plain).minX, accuracy: 1, "a Label header's icon starts where a Text header does") }
            let font = plain.storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            let vorFont = vor.storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            XCTAssertEqual(vorFont?.pointSize, font?.pointSize, "the Label header takes the headline font")
            guard let link = allViews(doc).compactMap({ $0 as? NSButton }).first(where: { $0.title == "Website" }) else { return XCTFail("no link") }
            XCTAssertEqual(link.font?.pointSize ?? 0, Font.pointSize(.caption), accuracy: 0.1, "the link keeps its caption font")
            XCTAssertGreaterThan(docFrame(doc, link).maxX, 380, "the link sits at the trailing edge")
            w.close()
        }
    }

    /// A radio-group or inline picker in a grouped form: the label at the top-left of the
    /// row, the options under it, leading-aligned with it (the Look & Feel Motion picker).
    func testStackedPickerRowListsOptionsUnderItsLabel() {
        MainActor.assumeIsolated {
            for style in [_PickerStyleKind.inline, .radioGroup] {
                struct Probe: View {
                    let style: _PickerStyleKind
                    @State var motion = 1
                    var body: some View {
                        Form {
                            Section {
                                if style == .inline {
                                    Picker("Motion", selection: $motion) { Text("Bouncy").tag(1); Text("Snappy").tag(2); Text("Smooth").tag(3) }.pickerStyle(.inline)
                                } else {
                                    Picker("Motion", selection: $motion) { Text("Bouncy").tag(1); Text("Snappy").tag(2); Text("Smooth").tag(3) }.pickerStyle(.radioGroup)
                                }
                            } header: { Text("Motion header") }
                        }
                        .formStyle(.grouped)
                    }
                }
                let (w, h) = host(Probe(style: style), width: 460, height: 400)
                guard let doc = formDocument(h), let label = textView(doc, "Motion").map({ docFrame(doc, $0) }) else { XCTFail("\(style): no label"); continue }
                let options = ["Bouncy", "Snappy", "Smooth"].compactMap { t in allViews(doc).compactMap { $0 as? NSButton }.first { $0.title == t } }.map { docFrame(doc, $0) }
                XCTAssertEqual(options.count, 3, "\(style): three options")
                for (i, o) in options.enumerated() {
                    XCTAssertGreaterThanOrEqual(o.minY, label.maxY - 0.5, "\(style): option \(i) \(o) is under the label \(label)")
                    XCTAssertEqual(o.minX, label.minX, accuracy: 2, "\(style): option \(i) leads with the label")
                    if i > 0 { XCTAssertGreaterThanOrEqual(o.minY, options[i - 1].maxY - 0.5, "\(style): one option per line") }
                }
                w.close()
            }
        }
    }

    /// A pane ending in a long footer, in a short window: the scroll document is tall enough
    /// for the footer as wrapped at the width it is placed at.
    func testLongFinalFooterIsInsideTheScrollDocument() {
        MainActor.assumeIsolated {
            let long = String(repeating: "Applies to view changes, list updates, the channel list and the status bar. ", count: 6)
            struct Probe: View {
                let long: String
                var body: some View {
                    Form {
                        Section {
                            Toggle("Auto-scroll to newest", isOn: .constant(true))
                            Toggle("Newest line first", isOn: .constant(false))
                            Toggle("Show timecode", isOn: .constant(true))
                        } header: { Text("Reading") } footer: { Text("With newest first, the most recent line sits at the top.")._sibylNote() }
                        Section {
                            Toggle("Reduce", isOn: .constant(false))
                        } header: { Text("Motion") } footer: { Text(long)._sibylNote() }
                    }
                    .formStyle(.grouped)
                }
            }
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            let hosting = NSHostingView(rootView: Probe(long: long))
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            hosting.layoutSubtreeIfNeeded()
            guard let scroll = allViews(hosting).compactMap({ $0 as? NSScrollView }).first, let doc = scroll.documentView,
                  let footer = textView(doc, long) else { return XCTFail("no scroll document or footer") }
            let f = docFrame(doc, footer)
            XCTAssertGreaterThan(doc.frame.height, scroll.contentSize.height, "the pane scrolls")
            XCTAssertGreaterThan(f.height, 40, "the footer wraps onto several lines: \(f)")
            XCTAssertLessThanOrEqual(f.maxY, doc.frame.height + 0.5, "the wrapped footer \(f) is inside the document \(doc.frame)")
            XCTAssertLessThanOrEqual(f.maxX, doc.frame.width + 0.5, "the footer is wrapped at the document's width")
            XCTAssertLessThanOrEqual(footer.size(for: footer.bounds.width).height, footer.bounds.height + 0.5, "the footer's frame holds its text as wrapped at the frame's width")
            window.close()
        }
    }

    // MARK: System symbols

    static let sibylSymbols = [
        "antenna.radiowaves.left.and.right", "arrow.counterclockwise", "arrow.left", "arrow.right", "arrow.left.and.right.square",
        "bell.badge", "bell.badge.fill", "bolt", "bolt.fill", "bolt.slash", "bolt.horizontal", "bookmark", "cable.connector.slash",
        "character.bubble", "chart.bar.doc.horizontal", "checkmark.circle.fill", "checkmark.seal", "checkmark.seal.fill",
        "chevron.compact.left", "chevron.compact.right", "clock", "desktopcomputer", "ellipsis.circle", "eraser",
        "exclamationmark.triangle.fill", "globe", "highlighter", "list.bullet.rectangle", "minus.circle.fill", "network",
        "paintbrush", "pianokeys", "play.circle", "point.3.connected.trianglepath.dotted", "puzzlepiece.extension",
        "questionmark.circle", "rectangle.expand.vertical", "sidebar.trailing", "speaker.slash", "square.grid.3x3", "stop.circle",
        "text.bubble", "textformat.size.larger", "textformat.size.smaller", "tv.badge.wifi", "waveform", "waveform.slash", "xmark.seal",
    ]

    func testSibylSymbolsAreDrawn() {
        MainActor.assumeIsolated {
            for name in Self.sibylSymbols {
                guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { XCTFail("\(name) has no artwork"); continue }
                XCTAssertTrue(image.isTemplate, name)
                let px = NSBitmapImageRep(cgImage: render(image))
                var inked = 0
                for y in 0..<16 { for x in 0..<16 where (px.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3 { inked += 1 } }
                XCTAssertGreaterThan(inked, 8, "\(name) draws something")
                XCTAssertLessThan(inked, 256, "\(name) is not a solid block")
            }
            XCTAssertNil(NSImage(systemSymbolName: "no.such.symbol.anywhere", accessibilityDescription: nil), "an unknown name is still nil")
            XCTAssertNil(NSImage(systemSymbolName: "no.such.circle.fill", accessibilityDescription: nil), "a variant of an unknown base is nil")
            for composed in ["bolt.circle.fill", "waveform.circle", "trash.slash", "star.square", "folder.fill"] {
                XCTAssertNotNil(NSImage(systemSymbolName: composed, accessibilityDescription: nil), "\(composed) is composed from its base")
            }
            // The filled circle cuts its mark out: the centre of the minus is clear, the disc is not.
            let minus = NSBitmapImageRep(cgImage: render(NSImage(systemSymbolName: "minus.circle.fill", accessibilityDescription: nil)!))
            XCTAssertLessThan(minus.colorAt(x: 8, y: 8)!.alphaComponent, 0.3)
            XCTAssertGreaterThan(minus.colorAt(x: 8, y: 3)!.alphaComponent, 0.7)
        }
    }

    func testBorderlessButtonWithASymbolLabelHasAFrame() {
        MainActor.assumeIsolated {
            let (w, h) = host(HStack {
                Text("Row")
                Spacer()
                Button {} label: { Image(systemName: "minus.circle.fill") }.buttonStyle(.borderless)
            })
            guard let image = allViews(h).compactMap({ $0 as? NSImageView }).first else { return XCTFail("no image view") }
            XCTAssertNotNil(image.image, "the symbol resolves to drawn artwork")
            XCTAssertGreaterThan(image.frame.width, 0)
            XCTAssertGreaterThan(image.frame.height, 0)
            guard let button = allViews(h).first(where: { $0.accessibilityRole() == .button && $0 !== image }) else { return XCTFail("no button") }
            XCTAssertGreaterThan(button.frame.width, 0)
            XCTAssertGreaterThan(button.frame.height, 0)
            w.close()
        }
    }
}

/// A grouped form in a wide window keeps its cards to a centred column, as macOS caps the
/// inset-grouped form at about 606 pt (Sibyl's Settings panes spanned the full width).
@MainActor private func _colViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(_colViews) }

final class SwiftUIGroupedFormColumnTests: XCTestCase, @unchecked Sendable {
    @MainActor private func red(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
        let c = rep.colorAt(x: x, y: y) ?? .black
        return (c.usingColorSpace(.deviceRGB) ?? c).redComponent
    }
    func testGroupedFormContentIsCappedAndCentred() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let form = Form { Section("One") { Text("Row"); Text("Row 2"); Text("Row 3") } }.formStyle(.grouped)
            for width in [500.0, 900.0, 1200.0] {
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
                let hosting = NSHostingView(rootView: form)
                window.contentView = hosting
                hosting.layoutSubtreeIfNeeded()
                guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { XCTFail("no bitmap"); continue }
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                let scale = CGFloat(rep.pixelsWide) / hosting.bounds.width
                // The last row's empty trailing half: a white run (the card) between grey page margins.
                guard let text = _colViews(hosting).compactMap({ $0 as? _TextView }).last else { XCTFail("no row"); continue }
                let row = hosting.convert(text.bounds, from: text)
                let y = Int(row.midY * scale)
                var first = -1, last = -1
                for x in 0..<rep.pixelsWide where red(rep, x, y) > 0.98 { if first < 0 { first = x }; last = x }
                let cardWidth = CGFloat(last - first + 1) / scale, mid = CGFloat(first + last) / 2 / scale
                let expectedWidth = min(width - 32, 606)
                XCTAssertEqual(cardWidth, expectedWidth, accuracy: 3, "card width at \(width)")
                XCTAssertEqual(mid, width / 2, accuracy: 3, "card centred at \(width)")
                window.close()
            }
        }
    }
}
