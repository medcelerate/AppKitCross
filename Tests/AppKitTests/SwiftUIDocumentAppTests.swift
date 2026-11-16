// What the second real app (Examples/MDVault, MD Vault) found missing, and its document
// flow rebuilt from the same shapes, so it runs on the headless host backend where the
// vendored executable itself is not run: a DocumentGroup over a FileDocument whose window
// hosts an NSTextView representable writing the document binding (new, type, edited,
// save, reopen, revert), the File menu a DocumentGroup gets, a `focusedSceneValue` read by
// a `@FocusedValue` in the scene's commands, `Font(NSFont)`, hierarchical foreground
// styles (`.tertiary`) and `textSelection`.

import XCTest
@testable import AppKit
@testable import SwiftUI
import UniformTypeIdentifiers

/// The app's MarkdownDocument, minus the Markdown UTI (plain text keeps the test free of
/// an Info.plist).
private struct NoteDocument: FileDocument {
    var text: String
    init(text: String = "") { self.text = text }
    static var readableContentTypes: [UTType] { [.plainText] }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        text = String(decoding: data, as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// The app's MarkdownTextEditor: an NSTextView whose delegate writes the binding.
private struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.string = text
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let tv = scroll.documentView as! NSTextView
        if tv.string != text { tv.string = text }
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor
        init(_ parent: NoteEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

private enum Mode: String { case editor, viewer }
private struct ModeKey: FocusedValueKey { typealias Value = Binding<Mode> }
extension FocusedValues {
    fileprivate var testMode: Binding<Mode>? {
        get { self[ModeKey.self] }
        set { self[ModeKey.self] = newValue }
    }
}

private struct NoteView: View {
    @Binding var document: NoteDocument
    @State private var mode: Mode = .editor
    var body: some View {
        VStack(spacing: 0) {
            NoteEditor(text: $document.text)
            Text("mode \(mode.rawValue)")
            Text("\(document.text.count) chars").foregroundStyle(.tertiary)
        }
        .focusedSceneValue(\.testMode, $mode)
    }
}

private struct ModeCommands: Commands {
    @FocusedValue(\.testMode) private var mode
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Toggle Mode") { mode?.wrappedValue = mode?.wrappedValue == .editor ? .viewer : .editor }
                .disabled(mode == nil)
        }
    }
}

@MainActor
private func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }
@MainActor
private func texts(_ v: NSView) -> [String] { allViews(v).compactMap { ($0 as? _TextView)?.storage.string } }
@MainActor
private func pump(_ seconds: TimeInterval = 0.05) { RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds)) }
@MainActor
private func menuItem(_ title: String, in menu: NSMenu?) -> NSMenuItem? {
    for item in menu?.items ?? [] {
        if item.title == title { return item }
        if let found = menuItem(title, in: item.submenu) { return found }
    }
    return nil
}

final class SwiftUIDocumentAppTests: XCTestCase, @unchecked Sendable {
    override func tearDown() {
        MainActor.assumeIsolated {
            for w in NSApplication.shared.windows { w.close() }
            NSDocumentController._shared?.clearRecentDocuments(nil)
            NSDocumentController._shared = nil
            NSDocumentController._infoDictionaryOverride = nil
            _SwiftUIDocumentController.installed = nil
            _DocumentGroupEntry._reset()
            NSApplication.shared.mainMenu = nil
        }
        super.tearDown()
    }

    /// The app's scene: a DocumentGroup with commands, run by a fresh runner and controller.
    @MainActor
    private func runApp() -> (_AppRunner, NSDocumentController) {
        for w in NSApplication.shared.windows { w.close() }
        NSDocumentController._shared = nil
        NSDocumentController._infoDictionaryOverride = [:]
        _SwiftUIDocumentController.installed = nil
        _DocumentGroupEntry._reset()
        let runner = _AppRunner(name: "MD Vault")
        runner.run(scene: DocumentGroup(newDocument: NoteDocument()) { file in NoteView(document: file.$document) }
            .defaultSize(width: 640, height: 480)
            .commands { ModeCommands() })
        runner.installMenuBar()
        let dc = NSDocumentController.shared
        dc.clearRecentDocuments(nil)
        return (runner, dc)
    }

    @MainActor
    private func textView(of document: NSDocument) -> NSTextView? {
        guard let content = document.windowControllers.first?.window?.contentView else { return nil }
        content.layoutSubtreeIfNeeded()
        return allViews(content).compactMap { $0 as? NSTextView }.first
    }

    /// New document, type, the edited mark, Save, close, reopen: the document's value
    /// travels through the binding, the file wrapper and back.
    func testDocumentGroupNewTypeSaveReopen() throws {
        try requireHostBackend()
        try MainActor.assumeIsolated {
            let (_, dc) = runApp()
            XCTAssertTrue(dc is _SwiftUIDocumentController, "a DocumentGroup installs SwiftUI's document controller")
            XCTAssertEqual(dc.defaultType, UTType.plainText.identifier, "the group's first writable type, without an Info.plist")
            XCTAssertTrue(dc.documentClass(forType: UTType.plainText.identifier) == _HostingDocument.self)

            let made = try dc.openUntitledDocumentAndDisplay(true)
            guard let doc = made as? _HostingDocument, let window = doc.windowControllers.first?.window else { return XCTFail("no document window: \(made) \(made.windowControllers)") }
            XCTAssertTrue(window.isVisible)
            XCTAssertEqual(window.title, "Untitled")
            XCTAssertEqual(window.frame.size.width, 640, accuracy: 60, "the scene's default size")
            XCTAssertFalse(doc.isDocumentEdited)

            guard let tv = textView(of: doc) else { return XCTFail("no text view in the document window") }
            tv.insertText("# Hello", replacementRange: NSRange(location: NSNotFound, length: 0))
            print("DEBUG tv.string=\(tv.string) editable=\(tv.isEditable) delegate=\(String(describing: tv.delegate))")
            XCTAssertEqual((doc._content as? NoteDocument)?.text, "# Hello", "the representable wrote the binding")
            pump()
            XCTAssertTrue(doc.isDocumentEdited, "a binding write marks the document edited")
            XCTAssertTrue(window.isDocumentEdited)
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(window.contentView!).contains("7 chars"), "the view follows the value: \(texts(window.contentView!))")

            let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MDVaultTests-\(getpid())")
            try? FileManager.default.removeItem(at: dir)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("note.txt")
            var saveError: Error? = NSError(domain: "pending", code: 0)
            doc.save(to: url, ofType: UTType.plainText.identifier, for: .saveOperation) { saveError = $0 }
            pump()
            XCTAssertNil(saveError)
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "# Hello")
            XCTAssertFalse(doc.isDocumentEdited, "saved")
            XCTAssertEqual(window.title, "note.txt")
            XCTAssertEqual(window.representedURL?.lastPathComponent, "note.txt")

            doc.close()
            XCTAssertFalse(dc.documents.contains { $0 === doc })
            XCTAssertEqual(try dc.typeForContents(of: url), UTType.plainText.identifier)
            var reopened: NSDocument?
            dc.openDocument(withContentsOf: url, display: true) { d, _, error in reopened = d; XCTAssertNil(error) }
            guard let again = reopened as? _HostingDocument else { return XCTFail("not reopened") }
            XCTAssertEqual((again._content as? NoteDocument)?.text, "# Hello")
            XCTAssertEqual(textView(of: again)?.string, "# Hello", "the reopened window shows the file")
            XCTAssertFalse(again.isDocumentEdited)

            // Revert: an edit, then back to the file.
            textView(of: again)?.insertText(" world", replacementRange: NSRange(location: NSNotFound, length: 0))
            pump()
            XCTAssertTrue(again.isDocumentEdited)
            try again.revert(toContentsOf: url, ofType: UTType.plainText.identifier)
            pump()
            again.windowControllers.first?.window?.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual((again._content as? NoteDocument)?.text, "# Hello")
            XCTAssertEqual(textView(of: again)?.string, "# Hello", "the view shows the reverted text")
            XCTAssertFalse(again.isDocumentEdited)
        }
    }

    /// A DocumentGroup's File menu has the document commands, not New Window.
    func testDocumentGroupFileMenu() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            _ = runApp()
            let menu = NSApplication.shared.mainMenu
            for (title, action) in [("New", "newDocument:"), ("Open\u{2026}", "openDocument:"), ("Save", "saveDocument:"),
                                    ("Save As\u{2026}", "saveDocumentAs:"), ("Revert to Saved", "revertDocumentToSaved:"), ("Close", "performClose:")] {
                XCTAssertEqual(menuItem(title, in: menu)?.action, Selector((action)), title)
            }
            XCTAssertNotNil(menuItem("Open Recent", in: menu)?.submenu)
            XCTAssertNil(menuItem("New Window", in: menu))
        }
    }

    /// A command reading `@FocusedValue` is disabled with no document window and acts on
    /// the key document window's published binding once there is one.
    func testFocusedSceneValueDrivesCommands() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let (_, dc) = runApp()
            pump()
            XCTAssertEqual(menuItem("Toggle Mode", in: NSApplication.shared.mainMenu)?.isEnabled, false, "nothing focused: disabled")
            dc.newDocument(nil)
            guard let doc = dc.documents.last, let window = doc.windowControllers.first?.window else { return XCTFail("no window") }
            window.makeKeyAndOrderFront(nil)
            window.contentView?.layoutSubtreeIfNeeded()
            pump()
            guard let item = menuItem("Toggle Mode", in: NSApplication.shared.mainMenu) else { return XCTFail("no command") }
            XCTAssertTrue(item.isEnabled, "the key window publishes the mode: enabled")
            XCTAssertTrue(NSApplication.shared.sendAction(item.action!, to: item.target, from: item))
            pump()
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(window.contentView!).contains("mode viewer"), "the command changed the view's state: \(texts(window.contentView!))")
        }
    }

    /// `Font(nsFont)` draws in that font; `.foregroundStyle(.tertiary)` is the tertiary
    /// label colour; `.textSelection(.enabled)` is accepted.
    func testFontFromNSFontAndHierarchicalStyles() {
        MainActor.assumeIsolated {
            let mono = NSFont.monospacedSystemFont(ofSize: 17, weight: .regular)
            let f = Font(mono)
            XCTAssertEqual(f.nsFont.fontName, mono.fontName)
            XCTAssertEqual(f.nsFont.pointSize, 17)
            XCTAssertEqual(Font(mono), Font(NSFont.monospacedSystemFont(ofSize: 17, weight: .regular)), "equal fonts compare equal")
            var env = EnvironmentValues()
            XCTAssertEqual(HierarchicalShapeStyle.tertiary._resolvedColor(env).nsColor, NSColor.tertiaryLabelColor)
            XCTAssertEqual(HierarchicalShapeStyle.secondary._resolvedColor(env).nsColor, NSColor.secondaryLabelColor)
            env.foregroundColor = .red
            XCTAssertEqual(HierarchicalShapeStyle.primary._resolvedColor(env), .red, "primary is the foreground colour")

            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
            defer { w.close() }
            let h = NSHostingView(rootView: VStack {
                Text("mono").font(Font(mono))
                Text("faint").foregroundStyle(.tertiary)
            }.textSelection(.enabled))
            h.frame = w.contentView!.bounds
            w.contentView!.addSubview(h)
            h.layoutSubtreeIfNeeded()
            let views = allViews(h).compactMap { $0 as? _TextView }
            let monoText = views.first { $0.storage.string == "mono" }
            XCTAssertEqual((monoText?.storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName, mono.fontName)
            let faint = views.first { $0.storage.string == "faint" }
            XCTAssertEqual(faint?.storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, NSColor.tertiaryLabelColor)
        }
    }

    #if !canImport(Darwin)
    /// `UTType(importedAs:)` returns the Info.plist's declaration (its extensions), as
    /// Apple's does, instead of replacing it with a bare one.
    func testImportedTypeKeepsItsDeclaration() {
        UTType._declare(identifier: "org.appkitcross.test.markdown", conformsTo: ["public.plain-text"], extensions: ["mdtest"], mimeTypes: [], description: "Test", exported: false)
        let t = UTType(importedAs: "org.appkitcross.test.markdown")
        XCTAssertEqual(t.preferredFilenameExtension, "mdtest")
        XCTAssertTrue(t.conforms(to: .plainText))
        XCTAssertEqual(UTType(filenameExtension: "mdtest")?.identifier, "org.appkitcross.test.markdown")
    }
    #endif
}
