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
    override func setUp() {
        super.setUp()
        // Closing a runner's last window quits off macOS (App.swift); not the test process.
        MainActor.assumeIsolated { _AppRunner._terminatesAfterLastWindowCloses = false }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            for w in NSApplication.shared.windows { w.close() }
            NSDocumentController._shared?.clearRecentDocuments(nil)
            NSDocumentController._shared = nil
            NSDocumentController._infoDictionaryOverride = nil
            _SwiftUIDocumentController.installed = nil
            _DocumentGroupEntry._reset()
            NSApplication.shared.mainMenu = nil
            _AppRunner._terminatesAfterLastWindowCloses = true
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

    /// Undo and redo of typing go through the document's undo manager (the text view
    /// registers them there) and take the document back to clean and edited again; the
    /// binding follows the text both ways.
    func testTypingUndoReturnsTheDocumentToClean() throws {
        try requireHostBackend()
        try MainActor.assumeIsolated {
            let (_, dc) = runApp()
            guard let doc = try dc.openUntitledDocumentAndDisplay(true) as? _HostingDocument, let tv = textView(of: doc) else { return XCTFail("no document") }
            doc.windowControllers.first?.window?.makeFirstResponder(tv)
            XCTAssertTrue(tv.undoManager === doc.undoManager, "the text view registers with the document's undo manager")
            tv.insertText("abc", replacementRange: NSRange(location: NSNotFound, length: 0))
            pump()
            XCTAssertTrue(doc.isDocumentEdited)
            doc.undoManager?.undo()
            pump()
            XCTAssertEqual(tv.string, "")
            XCTAssertEqual((doc._content as? NoteDocument)?.text, "", "the binding followed the undo")
            XCTAssertFalse(doc.isDocumentEdited, "undoing the only change leaves the document clean")
            doc.undoManager?.redo()
            pump()
            XCTAssertEqual((doc._content as? NoteDocument)?.text, "abc")
            XCTAssertTrue(doc.isDocumentEdited)
        }
    }

    /// The viewer's shapes (MarkdownView.swift): attributed text runs with AppKit fonts,
    /// links, strikethrough and code backgrounds; a Grid table with a divider row; a
    /// horizontally scrolling code block; list markers; a status bar on `.bar`; all in a
    /// scroll view with `textSelection`. Laid out and drawn without trapping.
    func testMarkdownViewerShapesRender() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            func run(_ text: String, size: CGFloat, bold: Bool = false, mono: Bool = false) -> AttributedString {
                var r = AttributedString(text)
                var font: NSFont = mono ? .monospacedSystemFont(ofSize: size, weight: bold ? .semibold : .regular) : .systemFont(ofSize: size, weight: bold ? .bold : .regular)
                if !mono, let italic = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.italic), size: size) { font = italic }
                r.font = Font(font)
                return r
            }
            var para = run("Plain ", size: 15)
            var code = run("code", size: 14, mono: true); code.backgroundColor = Color.primary.opacity(0.08)
            var link = run("link", size: 15); link.link = URL(string: "https://example.com"); link.foregroundColor = .accentColor; link.underlineStyle = .single
            var strike = run(" gone", size: 15); strike.strikethroughStyle = .single
            para.append(code); para.append(link); para.append(strike)
            let viewer = VStack(spacing: 0) {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(run("Heading", size: 30, bold: true)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                        Divider()
                        Text(para).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Image(systemName: "checkmark.square.fill").foregroundStyle(Color.accentColor)
                            Text("1.").font(Font(NSFont.systemFont(ofSize: 15, weight: .medium))).monospacedDigit().foregroundStyle(.secondary)
                            Text("item")
                        }
                        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                            GridRow { Text("A").bold(); Text("B").bold().gridColumnAlignment(.trailing) }
                            Divider().gridCellUnsizedAxes(.horizontal)
                            GridRow { Text("1"); Text("2").frame(maxWidth: .infinity, alignment: .trailing).background(Color.primary.opacity(0.03)) }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.12)))
                        VStack(alignment: .leading, spacing: 0) {
                            Text("SWIFT").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.tertiary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                Text("let x = 1 // a long line of code that scrolls sideways in its block").font(Font(NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))).padding(15)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.055)))
                    }
                    .frame(maxWidth: 690, alignment: .leading)
                    .padding(.horizontal, 40)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .textSelection(.enabled)
                .background(Color(nsColor: .textBackgroundColor))
                Divider()
                HStack(spacing: 12) {
                    Text("Viewer").fontWeight(.semibold)
                    Text("\u{2318}E to switch").foregroundStyle(.tertiary)
                    Spacer()
                    Text("3 words")
                }
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 5).background(.bar)
            }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 720), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            defer { w.close() }
            let h = NSHostingView(rootView: viewer)
            h.frame = w.contentView!.bounds
            w.contentView!.addSubview(h)
            w.makeKeyAndOrderFront(nil)
            h.layoutSubtreeIfNeeded()
            w.displayIfNeeded()
            let strings = texts(h)
            XCTAssertTrue(strings.contains("Plain codelink gone"), "\(strings)")
            XCTAssertTrue(strings.contains("A") && strings.contains("2"))
            let paragraph = allViews(h).compactMap { $0 as? _TextView }.first { $0.storage.string == "Plain codelink gone" }
            #if !os(Windows) || compiler(>=6.4)
            // With Windows' 6.2 toolchain `Text(AttributedString)` draws the plain characters
            // (it cannot link `AttributedString.runs`; AttributedText.swift), so the runs'
            // attributes are not there: a known gap (docs/compatibility/swiftui-apps.md).
            XCTAssertNotNil(paragraph?.storage.attribute(.link, at: 10, effectiveRange: nil), "the link run")
            XCTAssertNotNil(paragraph?.storage.attribute(.strikethroughStyle, at: 16, effectiveRange: nil), "the struck run")
            #endif
        }
    }

    /// The editor's highlighter (SyntaxHighlighter.swift): line-anchored regexes with
    /// look-behind over an NSTextStorage, dynamic colours from a provider, fonts per range.
    func testHighlighterShapes() {
        MainActor.assumeIsolated {
            let dynamic = NSColor(name: nil) { appearance in appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .white : .black }
            let storage = NSTextStorage(string: "# Title\n\nSome **bold** and *it* and `code`\n- [x] done\n")
            let full = NSRange(location: 0, length: storage.length)
            let base = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
            storage.beginEditing()
            storage.setAttributes([.font: base, .foregroundColor: NSColor.labelColor], range: full)
            let heading = try! NSRegularExpression(pattern: "^[ \\t]{0,3}(#{1,6})([ \\t]+)(.*)$", options: [.anchorsMatchLines])
            let strong = try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1", options: [.anchorsMatchLines])
            let emphasis = try! NSRegularExpression(pattern: "(?<![\\*\\w])(\\*)(?=[^\\s\\*])([^\\*\\n]+?)(?<=[^\\s\\*])(\\*)(?!\\*)", options: [.anchorsMatchLines])
            let task = try! NSRegularExpression(pattern: "^[ \\t]*(?:[-*+]|[0-9]{1,9}[.)])[ \\t]+(\\[[ xX]\\])", options: [.anchorsMatchLines])
            var hits: [String] = []
            for (name, re) in [("heading", heading), ("strong", strong), ("emphasis", emphasis), ("task", task)] {
                re.enumerateMatches(in: storage.string, range: full) { m, _, _ in
                    guard let m else { return }
                    hits.append(name)
                    storage.addAttributes([.foregroundColor: dynamic, .backgroundColor: NSColor.systemBlue], range: m.range(at: 1))
                }
            }
            storage.endEditing()
            XCTAssertEqual(hits, ["heading", "strong", "emphasis", "task"])
            XCTAssertNotNil(storage.attribute(.backgroundColor, at: 0, effectiveRange: nil))
            XCTAssertEqual(NSAppearance(named: .darkAqua)?.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
        }
    }

    /// The editor's layout (ContentView.swift): the NSTextView representable inside a
    /// `Group` framed to fill, above a divider and a status bar, fills the window: the
    /// PC showed it as a 90-point strip in the middle with the status bar under it.
    func testEditorRepresentableFillsTheWindow() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Editor: NSViewRepresentable {
                func makeNSView(context: Context) -> NSScrollView {
                    let scroll = NSTextView.scrollableTextView()
                    scroll.hasVerticalScroller = true
                    scroll.autohidesScrollers = true
                    (scroll.documentView as? NSTextView)?.textContainerInset = NSSize(width: 16, height: 18)
                    return scroll
                }
                func updateNSView(_ nsView: NSScrollView, context: Context) {}
            }
            let content = VStack(spacing: 0) {
                Group { Editor() }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                HStack { Text("Editor"); Spacer(); Text("0 chars") }.font(.system(size: 11)).padding(.horizontal, 14).padding(.vertical, 5).background(.bar)
            }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 720), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            defer { w.close() }
            let h = NSHostingView(rootView: content)
            h.frame = w.contentView!.bounds
            h.autoresizingMask = [.width, .height]
            w.contentView!.addSubview(h)
            w.makeKeyAndOrderFront(nil)
            h.layoutSubtreeIfNeeded()
            guard let scroll = allViews(h).compactMap({ $0 as? NSScrollView }).first else { return XCTFail("no scroll view") }
            let frame = scroll.convert(scroll.bounds, to: h)
            XCTAssertGreaterThan(frame.height, 650, "the editor takes the window's height less the status bar: \(frame)")
            XCTAssertEqual(frame.width, 920, accuracy: 1)
            XCTAssertLessThan(min(frame.minY, frame.maxY), 1, "at the top")
        }
    }

    /// Edit > Find in a SwiftUI app's menu bar: the text finder actions by tag (the PC's
    /// Ctrl+F did nothing: there was no Find item).
    func testEditMenuHasFind() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            _ = runApp()
            let menu = NSApplication.shared.mainMenu
            guard let find = menuItem("Find\u{2026}", in: menu) else { return XCTFail("no Find item") }
            XCTAssertEqual(find.action, Selector(("performTextFinderAction:")))
            XCTAssertEqual(find.tag, NSTextFinder.Action.showFindInterface.rawValue)
            XCTAssertEqual(find.keyEquivalent, "f")
            XCTAssertEqual(menuItem("Find Next", in: menu)?.tag, NSTextFinder.Action.nextMatch.rawValue)
            XCTAssertEqual(menuItem("Use Selection for Find", in: menu)?.keyEquivalent, "", "Cmd-E stays the app's")
        }
    }

    /// A command writing an @AppStorage key (Bigger Text) updates the windows reading it
    /// at once (the PC saw the sizes change only at the next mode switch).
    func testAppStorageWriteUpdatesOtherReaders() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let key = "SwiftUIDocumentAppTests.size"
            UserDefaults.standard.removeObject(forKey: key)
            defer { UserDefaults.standard.removeObject(forKey: key) }
            struct Reader: View {
                @AppStorage("SwiftUIDocumentAppTests.size") var size: Double = 15
                var body: some View { Text("size \(Int(size))") }
            }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
            defer { w.close() }
            let h = NSHostingView(rootView: Reader())
            h.frame = w.contentView!.bounds
            w.contentView!.addSubview(h)
            w.makeKeyAndOrderFront(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("size 15"))
            let command = AppStorage(wrappedValue: 15.0, key)    // the Commands struct's own
            command.wrappedValue = 16
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("size 16"), "\(texts(h))")
        }
    }

    /// A "+" key equivalent (Bigger Text) answers Ctrl+Plus (Shift+=) and Ctrl+=.
    func testPlusKeyEquivalentAnswersEquals() {
        MainActor.assumeIsolated {
            let item = NSMenuItem(title: "Bigger Text", action: Selector(("bigger:")), keyEquivalent: "+")
            item.keyEquivalentModifierMask = [.command]
            func key(_ c: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
                NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                                 characters: c, charactersIgnoringModifiers: c, isARepeat: false, keyCode: 24)!
            }
            XCTAssertTrue(item._matches(key("=", [.command])), "Ctrl+=")
            XCTAssertTrue(item._matches(key("+", [.command, .shift])), "Ctrl+Shift+= (Ctrl+Plus)")
            XCTAssertTrue(item._matches(key("+", [.command])), "the keypad's plus")
            XCTAssertFalse(item._matches(key("-", [.command])))
            XCTAssertFalse(item._matches(key("=", [.command, .option])))
            let minus = NSMenuItem(title: "Smaller Text", action: Selector(("smaller:")), keyEquivalent: "-")
            minus.keyEquivalentModifierMask = [.command]
            XCTAssertTrue(minus._matches(key("-", [.command])))
            XCTAssertFalse(minus._matches(key("=", [.command])))
        }
    }

    #if os(Windows)
    /// Clipboard text arrives with LF line ends and leaves with CR LF.
    func testClipboardLineEnds() {
        XCTAssertEqual(Win32Pasteboard.lf("a\r\nb\rc\nd"), "a\nb\nc\nd")
        XCTAssertEqual(Win32Pasteboard.crlf("a\nb\r\nc"), "a\r\nb\r\nc")
    }
    #endif

    /// A scene window opens at its `.defaultSize` even when its content's ideal size is a
    /// long scroll view's whole document (the PC's sample.md opened 1460 points tall at
    /// (0,0)), and a window without one still fits the screen.
    func testSceneWindowSizeIgnoresAScrollViewsIdealHeight() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Long: View {
                var body: some View {
                    ScrollView { VStack { ForEach(0..<300) { i in Text("line \(i)") } } }
                }
            }
            let runner = _AppRunner(name: "MD Vault")
            runner.run(scene: WindowGroup { Long() }.defaultSize(width: 920, height: 720))
            guard let w = runner.windows.last else { return XCTFail("no window") }
            defer { w.close() }
            XCTAssertEqual(w.contentRect(forFrameRect: w.frame).height, 720, accuracy: 1)
            runner.run(scene: WindowGroup { VStack { ForEach(0..<300) { i in Text("line \(i)") } } })
            guard let tall = runner.windows.last, tall !== w else { return XCTFail("no second window") }
            defer { tall.close() }
            if let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame, visible.height > 0 {
                XCTAssertLessThanOrEqual(tall.frame.height, visible.height + 1, "fits the screen")
            }
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
