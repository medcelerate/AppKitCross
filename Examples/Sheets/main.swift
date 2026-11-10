// Sheets: every way a sheet is presented (ADR-0019), on one window. An `NSAlert` sheet,
// the open panel as a sheet, a custom `NSWindow` sheet begun with `beginSheet` (with a
// sheet of its own, and the old `runModal(for:)` pattern), two sheets queued at once, and
// a SwiftUI pane with `.sheet` and `.confirmationDialog`. The status line reports every
// return code. Move or minimise the window while a sheet is up: the sheet follows.

import AppKit
import SwiftUI

/// The SwiftUI pane at the bottom of the window.
struct SheetPane: View {
    @State private var showSheet = false
    @State private var showDialog = false
    @State private var lastChoice = "nothing yet"
    var body: some View {
        HStack(spacing: 12) {
            Button("SwiftUI sheet") { showSheet = true }
            Button("Confirmation dialog") { showDialog = true }
            Text("SwiftUI: \(lastChoice)").foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .sheet(isPresented: $showSheet, onDismiss: { lastChoice = "sheet dismissed" }) { SheetBody() }
        .confirmationDialog("Discard the draft?", isPresented: $showDialog) {
            Button("Discard", role: .destructive) { lastChoice = "discarded" }
            Button("Keep editing", role: .cancel) { lastChoice = "kept" }
        }
    }
}

struct SheetBody: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A SwiftUI sheet").font(.headline)
            Text("Escape or Done dismisses it. The window behind takes no clicks meanwhile.")
            TextField("Your name", text: $name)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20)
        .frame(width: 360)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSSelectorHandling {
    var window: NSWindow!
    var status: NSTextField!
    var queued = 0

    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch action {
        case Selector(("showAlert:")): showAlert(); return true
        case Selector(("showOpenPanel:")): showOpenPanel(); return true
        case Selector(("showCustom:")): showCustom(); return true
        case Selector(("showModal:")): showModal(); return true
        case Selector(("showQueued:")): showQueued(); return true
        case Selector(("quit:")): NSApp.terminate(sender); return true
        default: return false
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let main = NSMenu(title: "Main")
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Alert Sheet", action: Selector(("showAlert:")), keyEquivalent: "1")
        file.addItem(withTitle: "Open Panel Sheet…", action: Selector(("showOpenPanel:")), keyEquivalent: "o")
        file.addItem(withTitle: "Custom Sheet", action: Selector(("showCustom:")), keyEquivalent: "2")
        file.addItem(withTitle: "Modal Sheet (runModal)", action: Selector(("showModal:")), keyEquivalent: "3")
        file.addItem(withTitle: "Two Queued Sheets", action: Selector(("showQueued:")), keyEquivalent: "4")
        file.addItem(NSMenuItem.separator())
        file.addItem(withTitle: "Quit", action: Selector(("quit:")), keyEquivalent: "q")
        fileItem.submenu = file
        main.addItem(fileItem)
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: Selector(("performMiniaturize:")), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: Selector(("performClose:")), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Sheets"
        window.delegate = self
        let content = window.contentView!

        let title = NSTextField(labelWithString: "Attached sheets")
        title.font = NSFont.boldSystemFont(ofSize: 22)
        let hint = NSTextField(wrappingLabelWithString: "Each button attaches a sheet under this title bar. While it is up the window takes no clicks and the keyboard goes to the sheet; drag or minimise the window and the sheet follows. The window's close button refuses until the sheet ends.")
        hint.preferredMaxLayoutWidth = 500
        status = NSTextField(wrappingLabelWithString: "ready")
        status.textColor = .secondaryLabelColor
        status.preferredMaxLayoutWidth = 500

        let alert = NSButton(title: "Alert sheet", target: self, action: Selector(("showAlert:")))
        let open = NSButton(title: "Open panel sheet", target: self, action: Selector(("showOpenPanel:")))
        let custom = NSButton(title: "Custom sheet", target: self, action: Selector(("showCustom:")))
        let modal = NSButton(title: "runModal sheet", target: self, action: Selector(("showModal:")))
        let two = NSButton(title: "Two queued", target: self, action: Selector(("showQueued:")))
        let row = NSStackView(views: [alert, open, custom, modal, two])
        row.orientation = .horizontal
        row.spacing = 8

        let column = NSStackView(views: [title, hint, row, status])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 14
        column.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            column.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            column.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
        ])

        let hosting = NSHostingView(rootView: SheetPane())
        hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 60)
        hosting.autoresizingMask = [.width, .maxYMargin]
        content.addSubview(hosting)

        window.center()
        window.makeKeyAndOrderFront(nil)

        // Scripted runs (screenshots): open one of the sheets at launch.
        let args = CommandLine.arguments
        if args.contains("--alert") { showAlert() }
        if args.contains("--custom") { showCustom() }
        if args.contains("--open") { showOpenPanel() }
        if args.contains("--queued") { showQueued() }
        if args.contains("--swiftui-sheet") {
            // The pane's button, found the way a user would press it.
            func buttons(_ v: NSView) -> [NSButton] { ([v] + v.subviews.flatMap { [$0] + $0.subviews }).compactMap { $0 as? NSButton } + v.subviews.flatMap(buttons) }
            hosting.layoutSubtreeIfNeeded()
            buttons(hosting).first { $0.title == "SwiftUI sheet" }?.performClick(nil)
        }
    }

    /// The status line keeps the last three reports, so two sheets ending in a row both show.
    private var reports: [String] = []
    private func report(_ what: String) {
        reports.append(what)
        if reports.count > 3 { reports.removeFirst() }
        status.stringValue = reports.joined(separator: "\n")
        print(what)
        fflush(nil)
    }

    private func describe(_ response: NSApplication.ModalResponse) -> String {
        switch response {
        case .OK: return "OK"
        case .cancel: return "cancel"
        case .abort: return "abort"
        case .stop: return "stop"
        case .continue: return "continue"
        case .alertFirstButtonReturn: return "first button"
        case .alertSecondButtonReturn: return "second button"
        case .alertThirdButtonReturn: return "third button"
        default: return "code \(response.rawValue)"
        }
    }

    // MARK: Sheets

    func showAlert() {
        let alert = NSAlert()
        alert.messageText = "Replace the existing file?"
        alert.informativeText = "A file with the same name already exists. Replacing it overwrites its contents."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in self?.report("alert sheet ended: \(self?.describe(response) ?? "")") }
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            self?.report("open panel ended: \(self?.describe(response) ?? "") \(panel.urls.first?.lastPathComponent ?? "")")
        }
    }

    /// A custom sheet: a text field, Cancel/OK, and a button that opens a sheet on the
    /// sheet (nested sheets attach to their own parent).
    private func makeCustomSheet(title: String, nested: Bool) -> (NSWindow, NSTextField) {
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: nested ? 170 : 140), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = title
        let content = sheet.contentView!
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.boldSystemFont(ofSize: 13)
        let field = NSTextField(string: "")
        field.placeholderString = "Type something, then OK"
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 340).isActive = true
        let cancel = NSButton(title: "Cancel", target: self, action: Selector(("sheetCancel:")))
        cancel.keyEquivalent = "\u{1B}"
        let ok = NSButton(title: "OK", target: self, action: Selector(("sheetOK:")))
        ok.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, ok])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        var rows: [NSView] = [label, field]
        if nested {
            let more = NSButton(title: "Sheet on this sheet", target: self, action: Selector(("sheetNested:")))
            rows.append(more)
        }
        rows.append(buttons)
        let column = NSStackView(views: rows)
        column.orientation = .vertical
        column.alignment = .trailing
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            column.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
        ])
        // The buttons end the sheet they sit in, whichever window that is.
        sheet.setActionHandler(for: Selector(("sheetCancel:"))) { _ in sheet.sheetParent?.endSheet(sheet, returnCode: .cancel) }
        sheet.setActionHandler(for: Selector(("sheetOK:"))) { _ in sheet.sheetParent?.endSheet(sheet, returnCode: .OK) }
        sheet.setActionHandler(for: Selector(("sheetNested:"))) { [weak self] _ in
            guard let self else { return }
            let (inner, _) = self.makeCustomSheet(title: "A sheet on the sheet", nested: false)
            sheet.beginSheet(inner) { [weak self] response in self?.report("nested sheet ended: \(self?.describe(response) ?? "")") }
        }
        cancel.target = sheet; ok.target = sheet
        for b in rows.compactMap({ $0 as? NSButton }) { b.target = sheet }
        return (sheet, field)
    }

    func showCustom() {
        let (sheet, field) = makeCustomSheet(title: "A custom sheet", nested: true)
        window.beginSheet(sheet) { [weak self] response in
            self?.report("custom sheet ended: \(self?.describe(response) ?? "")" + (field.stringValue.isEmpty ? "" : " text \"\(field.stringValue)\""))
        }
        sheet.makeFirstResponder(field)
    }

    /// The pre-10.9 pattern: begin the sheet, run the application-modal loop on it, end it.
    func showModal() {
        let (sheet, field) = makeCustomSheet(title: "A sheet under runModal(for:)", nested: false)
        sheet.setActionHandler(for: Selector(("sheetCancel:"))) { _ in NSApp.stopModal(withCode: .cancel) }
        sheet.setActionHandler(for: Selector(("sheetOK:"))) { _ in NSApp.stopModal(withCode: .OK) }
        window.beginSheet(sheet)
        sheet.makeFirstResponder(field)
        let response = NSApp.runModal(for: sheet)
        window.endSheet(sheet, returnCode: response)
        report("modal sheet ended: \(describe(response))" + (field.stringValue.isEmpty ? "" : " text \"\(field.stringValue)\""))
    }

    /// Two sheets begun at once: the second waits until the first ends.
    func showQueued() {
        queued += 1
        let (first, _) = makeCustomSheet(title: "First of two (the second is queued)", nested: false)
        let (second, _) = makeCustomSheet(title: "Second of two", nested: false)
        window.beginSheet(first) { [weak self] response in self?.report("first queued sheet ended: \(self?.describe(response) ?? "")") }
        window.beginSheet(second) { [weak self] response in self?.report("second queued sheet ended: \(self?.describe(response) ?? "")") }
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) { if window.attachedSheet != nil { report("moved with the sheet attached") } }
    func windowDidMiniaturize(_ notification: Notification) { report("minimized\(window.attachedSheet != nil ? " with the sheet" : "")") }
    func windowDidDeminiaturize(_ notification: Notification) { report("restored") }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
