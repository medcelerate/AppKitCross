// Members a real third-party SwiftUI app (Examples/DailyTodo, Daily To Do) found missing:
// LabeledContent, FormStyle, ContentUnavailableView; and the app's two screens rebuilt from
// the same views (a NavigationStack with a toolbar, a date field, a text field, a list of
// checkbox rows, an empty-state overlay, a grouped settings form in a sheet) so the whole
// tree is exercised on the headless host backend, where the executable itself is not run.

import XCTest
@testable import AppKit
@testable import SwiftUI

@MainActor
private func host<V: View>(_ view: V, width: CGFloat = 560, height: CGFloat = 420) -> (NSWindow, NSHostingView<V>) {
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
private func buttons(_ v: NSView) -> [NSButton] { allViews(v).compactMap { $0 as? NSButton } }

final class SwiftUIRealAppTests: XCTestCase, @unchecked Sendable {
    func testLabeledContentShowsLabelAndValue() {
        MainActor.assumeIsolated {
            let (w, h) = host(Form {
                LabeledContent("Reminder time", value: "1:00 PM")
                LabeledContent("Next opening") { Text("Tomorrow") }
                LabeledContent { Text("custom") } label: { Text("Label") }
            })
            let t = texts(h)
            for s in ["Reminder time", "1:00 PM", "Next opening", "Tomorrow", "Label", "custom"] { XCTAssertTrue(t.contains(s), s) }
            // The label leads and the value trails on one row, as AppKit's forms lay them out.
            let views = allViews(h).compactMap { $0 as? _TextView }
            let label = views.first { $0.storage.string == "Reminder time" }!
            let value = views.first { $0.storage.string == "1:00 PM" }!
            XCTAssertLessThan(label.frame.minX, value.frame.minX)
            XCTAssertEqual(h.convert(label.frame, from: label.superview).midY, h.convert(value.frame, from: value.superview).midY, accuracy: 2)
            w.close()
        }
    }

    func testFormStylesLayOutTheirRows() {
        MainActor.assumeIsolated {
            struct Settings: View {
                var body: some View {
                    Form {
                        Section("Workday") { Toggle("Midday reminder", isOn: .constant(true)) }
                        Section("Schedule") { LabeledContent("Next reminder", value: "Disabled") }
                    }
                    .formStyle(.grouped)
                }
            }
            let (w, h) = host(Settings())
            let t = texts(h)
            for s in ["Workday", "Schedule", "Next reminder", "Disabled"] { XCTAssertTrue(t.contains(s), s) }
            XCTAssertNotNil(buttons(h).first { $0.title == "Midday reminder" })
            w.close()
            let (w2, h2) = host(Form { Text("columns") }.formStyle(.columns))
            XCTAssertTrue(texts(h2).contains("columns"))
            w2.close()
        }
    }

    func testContentUnavailableViewShowsTitleAndDescription() {
        MainActor.assumeIsolated {
            let (w, h) = host(ContentUnavailableView("No tasks", systemImage: "checkmark.circle", description: Text("Add a task for the selected day.")))
            let t = texts(h)
            XCTAssertTrue(t.contains("No tasks"))
            XCTAssertTrue(t.contains("Add a task for the selected day."))
            // Centred in the host, title above the description.
            let views = allViews(h).compactMap { $0 as? _TextView }
            let title = h.convert(views.first { $0.storage.string == "No tasks" }!.frame, from: views[0].superview)
            let desc = h.convert(views.first { $0.storage.string == "Add a task for the selected day." }!.frame, from: views[0].superview)
            XCTAssertEqual(title.midX, h.bounds.midX, accuracy: 4)
            XCTAssertGreaterThan(desc.midY, title.midY, "flipped: the description is below the title")
            let (w2, h2) = host(ContentUnavailableView.search(text: "zzz"))
            XCTAssertTrue(texts(h2).contains { $0.contains("zzz") })
            w2.close()
            w.close()
        }
    }

    /// A WindowGroup window: titled by the content's navigation title, and under
    /// `.windowResizability(.contentSize)` still resizable when the content has only a minimum.
    func testWindowGroupTitleAndContentSizeResizability() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Main: View {
                var body: some View {
                    // A column that grows without bound (the app's list does), with a minimum.
                    NavigationStack { VStack { HStack { Text("Tasks"); Spacer() }; Spacer() }.frame(minWidth: 560, minHeight: 420).navigationTitle("Daily To Do") }
                }
            }
            let runner = _AppRunner(name: "DailyTodo")
            runner.run(scene: WindowGroup { Main() }.windowResizability(.contentSize))
            guard let w = runner.windows.last else { return XCTFail("no window") }
            defer { w.close() }
            w.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(w.title, "Daily To Do")
            XCTAssertTrue(w.styleMask.contains(.resizable), "a minimum without a maximum leaves the window resizable")
            XCTAssertGreaterThanOrEqual(w.minSize.width, 560)
            XCTAssertGreaterThanOrEqual(w.minSize.height, 420)
            XCTAssertGreaterThan(w.maxSize.width, 10_000, "no maximum from the content")
        }
    }

    /// An animating progress indicator runs frames only while its window shows: closed or
    /// ordered out, it neither invalidates nor keeps the frame clock going (the idle-sheet
    /// test on Linux CI caught two spinners of an earlier test still ticking in closed windows).
    func testProgressIndicatorAnimatesOnlyWhileItsWindowShows() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let spinner = NSProgressIndicator(frame: NSRect(x: 10, y: 10, width: 32, height: 32))
            spinner.style = .spinning
            w.contentView!.addSubview(spinner)
            spinner.startAnimation(nil)
            @MainActor func invalidationsOverOneTick() -> Int {
                let before = NSView._invalidationCount
                CARuntime.tick()
                return NSView._invalidationCount - before
            }
            XCTAssertEqual(invalidationsOverOneTick(), 0, "not shown yet: no frames")
            w.makeKeyAndOrderFront(nil)
            XCTAssertGreaterThan(invalidationsOverOneTick(), 0, "shown: the spinner turns")
            w.orderOut(nil)
            XCTAssertEqual(invalidationsOverOneTick(), 0, "ordered out: no frames")
            w.makeKeyAndOrderFront(nil)
            XCTAssertGreaterThan(invalidationsOverOneTick(), 0, "shown again: it turns again")
            w.close()
            XCTAssertEqual(invalidationsOverOneTick(), 0, "closed: no frames")
        }
    }

    /// A presented sheet with a date picker, a pop-up picker and a toolbar left idle performs
    /// no root measurement, no layout pass and no invalidation per frame once it has settled
    /// (on Windows a loop of toolbar re-sizing, content layout and repaint kept a core busy).
    func testIdleSheetPerformsNoWork() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            final class Store: ObservableObject { @Published var day = Date(); @Published var zone = "Zone 3" }
            struct Settings: View {
                @EnvironmentObject var store: Store
                @Environment(\.dismiss) var dismiss
                var body: some View {
                    Form {
                        DatePicker("Workday starts", selection: $store.day, displayedComponents: .hourAndMinute)
                        Picker("Time zone", selection: $store.zone) { ForEach((0..<400).map { "Zone \($0)" }, id: \.self) { Text($0).tag($0) } }
                        TextField("Filter", text: .constant(""))
                        LabeledContent("Next", value: "Tomorrow")
                    }
                    .formStyle(.grouped).padding().frame(width: 420, height: 360)
                    .toolbar { Button("Done") { dismiss() } }
                }
            }
            struct Main: View {
                @State var showSettings = false
                var body: some View {
                    VStack { Button("Settings") { showSettings = true }; Text("main") }
                        .frame(minWidth: 400, minHeight: 300)
                        .sheet(isPresented: $showSettings) { Settings() }
                }
            }
            let savedDuration = NSWindow._sheetAnimationDuration
            NSWindow._sheetAnimationDuration = 0
            defer { NSWindow._sheetAnimationDuration = savedDuration }
            let store = Store()
            let (w, h) = host(Main().environmentObject(store))
            buttons(h).first { $0.title == "Settings" }?.performClick(nil)
            let backend = Platform.backend as! HostBackend
            backend.drain()
            h.layoutSubtreeIfNeeded()
            guard let sheet = w.sheets.first else { return XCTFail("no sheet") }
            // One "frame": paint what needs it, run posted blocks, tick the animation clock.
            @MainActor func frame() {
                sheet.displayIfNeeded(); w.displayIfNeeded()
                backend.drain()
                CARuntime.tick()
            }
            for _ in 0..<4 { frame() }        // settle
            let layouts = _ViewRoot._layoutPassCount, fits = _ViewRoot._sizeThatFitsCount, invalidations = NSView._invalidationCount
            for _ in 0..<5 { frame() }
            XCTAssertEqual(_ViewRoot._layoutPassCount - layouts, 0, "an idle sheet lays nothing out")
            XCTAssertEqual(_ViewRoot._sizeThatFitsCount - fits, 0, "an idle sheet measures nothing")
            XCTAssertEqual(NSView._invalidationCount - invalidations, 0, "an idle sheet invalidates nothing")
            w.close()
        }
    }

    /// Daily To Do's main window and its settings sheet, built from the same views the app uses.
    func testDailyTodoScreensHostAndTheSettingsSheetOpens() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Item: Identifiable { let id = UUID(); var title: String; var done = false }
            final class Store: ObservableObject {
                @Published var items: [Item] = []
                @Published var day = Date()
                @Published var reminder = true
                @Published var zone = "Europe/London"
                var pending: Int { items.filter { !$0.done }.count }
            }
            struct Row: View {
                @EnvironmentObject var store: Store
                let item: Item
                var body: some View {
                    HStack(spacing: 12) {
                        Toggle("", isOn: Binding(get: { item.done }, set: { v in store.items = store.items.map { $0.id == item.id ? Item(title: $0.title, done: v) : $0 } }))
                            .toggleStyle(.checkbox).labelsHidden()
                        Text(item.title).strikethrough(item.done).foregroundStyle(item.done ? .secondary : .primary)
                        Spacer()
                        Button { } label: { Label("Move to next working day", systemImage: "arrow.right.circle") }.disabled(item.done).help("Move")
                    }
                }
            }
            struct Settings: View {
                @EnvironmentObject var store: Store
                @Environment(\.dismiss) var dismiss
                var body: some View {
                    Form {
                        Section("Workday") {
                            DatePicker("Workday starts", selection: $store.day, displayedComponents: .hourAndMinute)
                            Picker("Time zone", selection: $store.zone) {
                                ForEach(["Europe/London", "Asia/Kolkata", "America/New_York"], id: \.self) { Text($0).tag($0) }
                            }
                            TextField("Filter time zones", text: .constant(""))
                            Toggle("Midday reminder", isOn: $store.reminder)
                        }
                        Section("Schedule") {
                            LabeledContent("Reminder time", value: "1:00 PM")
                            LabeledContent("Next reminder", value: store.reminder ? "Tomorrow" : "Disabled")
                        }
                    }
                    .formStyle(.grouped)
                    .padding()
                    .frame(width: 560, height: 560)
                    .toolbar { Button("Done") { dismiss() } }
                }
            }
            struct Main: View {
                @EnvironmentObject var store: Store
                @State var newTitle = ""
                @State var showSettings = false
                var body: some View {
                    NavigationStack {
                        VStack(spacing: 0) {
                            HStack {
                                DatePicker("Day", selection: $store.day, displayedComponents: .date).datePickerStyle(.field)
                                Spacer()
                                Button("Today") { store.day = Date() }
                            }.padding()
                            HStack(spacing: 8) {
                                TextField("Add a task", text: $newTitle).textFieldStyle(.roundedBorder).onSubmit { add() }
                                Button("Add") { add() }.disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }.padding([.horizontal, .bottom])
                            List { ForEach(store.items) { Row(item: $0) } }
                                .listStyle(.inset)
                                .overlay { if store.items.isEmpty { ContentUnavailableView("No tasks", systemImage: "checkmark.circle", description: Text("Add a task for the selected day.")) } }
                            HStack { Text("\(store.pending) pending").foregroundStyle(.secondary); Spacer() }.padding()
                        }
                        .frame(minWidth: 560, minHeight: 420)
                        .navigationTitle("Daily To Do")
                        .toolbar { ToolbarItem(placement: .primaryAction) { Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") } } }
                        .sheet(isPresented: $showSettings) { Settings() }
                    }
                }
                func add() { store.items.append(Item(title: newTitle)); newTitle = "" }
            }
            let savedDuration = NSWindow._sheetAnimationDuration
            NSWindow._sheetAnimationDuration = 0
            defer { NSWindow._sheetAnimationDuration = savedDuration }
            let store = Store()
            let (w, h) = host(Main().environmentObject(store))
            XCTAssertTrue(texts(h).contains("No tasks"), "empty state over the list")
            XCTAssertTrue(texts(h).contains("0 pending"))
            XCTAssertNotNil(buttons(h).first { $0.title == "Today" })
            XCTAssertEqual(buttons(h).first { $0.title == "Add" }?.isEnabled, false, "Add is disabled while the field is empty")
            (Platform.backend as! HostBackend).drain()
            h.layoutSubtreeIfNeeded()
            guard let tb = w.toolbar as? _SwiftUIToolbar else { return XCTFail("the toolbar button did not reach the window's NSToolbar") }
            // A Button whose label is a Label (icon and title) is the port's custom button view.
            let settingsButton = tb.items.compactMap(\.view).flatMap(allViews).compactMap { $0 as? _ContainerView }.first { $0.accessibilityPress != nil }
            XCTAssertNotNil(settingsButton, "the primary-action item hosts the Settings button")
            XCTAssertTrue(tb.items.compactMap(\.view).flatMap(allViews).compactMap { ($0 as? _TextView)?.storage.string }.contains("Settings"))
            // A press on the button (or on the label inside it) is the button's, not a
            // title-bar drag: the Win32 frame asks the window before it moves the window.
            if let b = settingsButton {
                let p = b.convert(NSPoint(x: b.bounds.midX, y: b.bounds.midY), to: nil)
                XCTAssertEqual(w.platformWindowHitTest(p), .client, "the toolbar's custom button is content, not caption")
            }
            // The list takes the height the fixed rows leave: the header sits at the top and
            // the footer at the bottom, with no empty band and nothing pushed out.
            @MainActor func offsets(_ v: NSView) -> (top: CGFloat, bottom: CGFloat) {
                let r = v.convert(v.bounds, to: h)
                return h.isFlipped ? (r.minY, h.bounds.height - r.maxY) : (h.bounds.height - r.maxY, r.minY)
            }
            if let day = allViews(h).first(where: { $0 is NSDatePicker }) { XCTAssertLessThan(offsets(day).top, 40, "the Day row is at the top") }
            if let footer = allViews(h).compactMap({ $0 as? _TextView }).first(where: { $0.storage.string == "0 pending" }) {
                let o = offsets(footer)
                XCTAssertGreaterThanOrEqual(o.bottom, 0, "the footer is inside the window")
                XCTAssertLessThan(o.bottom, 40, "the footer sits at the bottom")
            } else { XCTFail("no footer text") }

            // Typing into the field and adding: the field follows its binding back to empty
            // while it is still being edited.
            guard let field = allViews(h).compactMap({ $0 as? NSTextField }).first(where: { $0.isEditable }) else { return XCTFail("no task field") }
            XCTAssertTrue(w.makeFirstResponder(field))
            (field.currentEditor as? NSTextView)?.insertText("Write the report", replacementRange: NSRange(location: 0, length: 0))
            (Platform.backend as! HostBackend).drain()
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(buttons(h).first { $0.title == "Add" }?.isEnabled, true, "Add enables once there is text")
            buttons(h).first { $0.title == "Add" }?.performClick(nil)
            (Platform.backend as! HostBackend).drain()
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(store.items.map(\.title), ["Write the report"])
            XCTAssertEqual(field.stringValue, "", "the binding cleared the field")
            XCTAssertEqual(field.currentEditor?.string ?? "", "", "and the field editor shows it cleared")

            // The date field keeps its selected field across body updates, so arrows step it.
            if let picker = allViews(h).compactMap({ $0 as? NSDatePicker }).first {
                let before = store.day
                XCTAssertTrue(w.makeFirstResponder(picker))
                let up = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil,
                                          characters: "\u{F700}", charactersIgnoringModifiers: "\u{F700}", isARepeat: false, keyCode: 126)!
                picker.keyDown(with: up)
                (Platform.backend as! HostBackend).drain()
                h.layoutSubtreeIfNeeded()
                XCTAssertNotEqual(store.day, before, "Up steps the selected field into the binding")
                XCTAssertGreaterThanOrEqual(picker._dateCell?._selectedField ?? -1, 0, "the field stays selected after the body update")
                picker.keyDown(with: up)
                (Platform.backend as! HostBackend).drain()
                XCTAssertGreaterThan(abs(store.day.timeIntervalSince(before)), 86_000, "a second Up steps again")
            }

            store.items = [Item(title: "Write the report"), Item(title: "Call the bank", done: true)]
            h.layoutSubtreeIfNeeded()
            if let footer = allViews(h).compactMap({ $0 as? _TextView }).first(where: { $0.storage.string == "1 pending" }) {
                XCTAssertLessThan(offsets(footer).bottom, 40, "the footer stays at the bottom once there are rows")
            }
            XCTAssertFalse(texts(h).contains("No tasks"), "the empty state goes once there are rows")
            XCTAssertTrue(texts(h).contains("Write the report"))
            XCTAssertTrue(texts(h).contains("1 pending"))
            let checkboxes = buttons(h).filter { $0.title.isEmpty && $0.allowsMixedState == false && $0.state != .mixed && $0.image == nil }
            XCTAssertGreaterThanOrEqual(checkboxes.count, 2, "one checkbox per row")

            // The settings sheet: a grouped form with a time picker, a pop-up and read-only rows.
            settingsButton?.accessibilityPress?()
            (Platform.backend as! HostBackend).drain()
            h.layoutSubtreeIfNeeded()
            guard w.sheets.count == 1 else { return XCTFail("the Settings sheet did not attach to the main window") }
            let sheet = w.sheets[0]
            let st = texts(sheet.contentView!)
            for s in ["Workday", "Schedule", "Reminder time", "1:00 PM", "Next reminder", "Tomorrow"] { XCTAssertTrue(st.contains(s), s) }
            // The sheet's frame holds its content (560 tall) plus its own toolbar band, and
            // keeps that height when the parent reports a frame (it shrank by the band each time).
            let sheetHeight = sheet.frame.height
            XCTAssertGreaterThan(sheetHeight, 560, "content plus the Done toolbar's band")
            w.setFrameOrigin(NSPoint(x: w.frame.minX + 10, y: w.frame.minY))
            (Platform.backend as! HostBackend).drain()
            XCTAssertEqual(sheet.frame.height, sheetHeight, "the parent moving keeps the sheet's height")
            // The grouped form is a card on the first open: its section header sits inside the
            // card's inset, as it does on every later open.
            @MainActor func headerInset(_ root: NSView) -> CGFloat? {
                allViews(root).compactMap { $0 as? _TextView }.first { $0.storage.string == "Workday" }.map { $0.convert($0.bounds, to: root).minX }
            }
            let firstOpenInset = headerInset(sheet.contentView!)
            XCTAssertNotNil(firstOpenInset)
            XCTAssertNotNil(allViews(sheet.contentView!).first { $0 is NSDatePicker }, "the hour-and-minute picker is an NSDatePicker")
            XCTAssertNotNil(allViews(sheet.contentView!).first { $0 is NSPopUpButton }, "the time zone picker is a pop-up")
            buttons(sheet.contentView!).first { $0.title == "Midday reminder" }?.performClick(nil)
            (Platform.backend as! HostBackend).drain()
            sheet.contentView!.layoutSubtreeIfNeeded()   // the sheet hosts its own view tree
            XCTAssertFalse(store.reminder)
            XCTAssertTrue(texts(sheet.contentView!).contains("Disabled"), "the read-only row follows the model")
            (Platform.backend as! HostBackend).drain()
            // Settings edits reach the model (the app saves on each change): the time
            // picker's stepper and the time zone pop-up write their bindings.
            if let picker = allViews(sheet.contentView!).compactMap({ $0 as? NSDatePicker }).first, let cell = picker._dateCell {
                let dayBefore = store.day
                XCTAssertTrue(sheet.makeFirstResponder(picker))
                let stepper = cell._stepperRect(forBounds: picker._cellFrame)
                let upHalf = NSPoint(x: stepper.midX, y: picker.isFlipped ? stepper.minY + stepper.height * 0.25 : stepper.maxY - stepper.height * 0.25)
                let inWindow = picker.convert(upHalf, to: nil)
                for (type, n) in [(NSEvent.EventType.leftMouseDown, 1), (.leftMouseUp, 2)] {
                    sheet.sendEvent(NSEvent.mouseEvent(with: type, location: inWindow, modifierFlags: [], timestamp: 0, windowNumber: sheet.windowNumber, context: nil, eventNumber: n, clickCount: 1, pressure: 1)!)
                }
                (Platform.backend as! HostBackend).drain()
                XCTAssertNotEqual(store.day, dayBefore, "a stepper click steps the workday start into the model")
            } else { XCTFail("no time picker in the sheet") }
            if let popup = allViews(sheet.contentView!).compactMap({ $0 as? NSPopUpButton }).first {
                XCTAssertEqual(store.zone, "Europe/London")
                popup.performClick(nil)                       // opens the menu over the button
                XCTAssertTrue(_NSMenuTracker.isTracking, "the pop-up's menu is tracking")
                for code in [UInt16(125), 36] {               // down, return: the next zone
                    NSApplication.shared.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: sheet.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!)
                }
                (Platform.backend as! HostBackend).drain()
                XCTAssertFalse(_NSMenuTracker.isTracking)
                XCTAssertEqual(store.zone, "Asia/Kolkata", "choosing in the pop-up writes the binding")
            } else { XCTFail("no time zone pop-up in the sheet") }
            let sheetButtons = buttons(sheet.contentView!) + (sheet.toolbar?.items.compactMap(\.view).flatMap(allViews).compactMap { $0 as? NSButton } ?? [])
            guard let done = sheetButtons.first(where: { $0.title == "Done" }) else { return XCTFail("no Done button in the sheet or its toolbar") }
            done.performClick(nil)
            (Platform.backend as! HostBackend).drain()
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(w.sheets.isEmpty, "Done dismisses the sheet")
            // A second open lays the grouped form out the same way as the first.
            settingsButton?.accessibilityPress?()
            (Platform.backend as! HostBackend).drain()
            h.layoutSubtreeIfNeeded()
            if let again = w.sheets.first {
                again.contentView!.layoutSubtreeIfNeeded()
                XCTAssertEqual(headerInset(again.contentView!), firstOpenInset, "the grouped card is there on the first open as on the second")
                XCTAssertGreaterThanOrEqual(headerInset(again.contentView!) ?? 0, 28, "the header is inset by the card and the form padding")
                (buttons(again.contentView!) + (again.toolbar?.items.compactMap(\.view).flatMap(allViews).compactMap { $0 as? NSButton } ?? [])).first { $0.title == "Done" }?.performClick(nil)
                (Platform.backend as! HostBackend).drain()
            } else { XCTFail("the sheet did not open a second time") }
            w.close()
        }
    }
}
